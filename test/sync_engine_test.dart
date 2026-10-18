import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:insurance_mobile/core/db/app_database.dart';
import 'package:insurance_mobile/core/db/meta_store.dart';
import 'package:insurance_mobile/core/network/api_exceptions.dart';
import 'package:insurance_mobile/core/sync/sync_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fakes.dart';

void main() {
  late Database db;
  late FakeTransport transport;
  late SyncEngine engine;

  setUp(() async {
    db = await openTestDb();
    transport = FakeTransport();
    engine = SyncEngine(db: db, transport: transport);
  });

  tearDown(() async => db.close());

  Map<String, dynamic> changesOf(int request) =>
      transport.requests[request]['changes'] as Map<String, dynamic>;

  group('payload', () {
    test('references unsynced parents by uuid and synced parents by server id', () async {
      final newFarmer = await insertFarmer(db);
      final newFarm = await insertFarm(db, farmerUuid: newFarmer);
      final syncedFarmer = await insertFarmer(db, serverId: 41, status: SyncStatus.synced, idNumber: '2');
      await insertFarm(db, farmerUuid: syncedFarmer);
      final syncedFarm = await insertFarm(db, farmerUuid: syncedFarmer, serverId: 5, status: SyncStatus.synced);
      await insertQuotation(db, farmUuid: newFarm);
      await insertQuotation(db, farmUuid: syncedFarm);

      await engine.sync();
      final changes = changesOf(0);

      final farmers = changes['farmers'] as List;
      expect(farmers, hasLength(1), reason: 'synced rows are not re-sent');
      expect(farmers.single['client_uuid'], newFarmer);
      expect(farmers.single['registration_latitude'], '-1.286389');
      expect(farmers.single['next_of_kin'], [
        {'name': 'John', 'relationship': 'Spouse', 'phone_number': '0700000000'}
      ]);
      expect(farmers.single.containsKey('email'), isTrue, reason: 'optional farmer fields may be cleared');

      final farms = changes['farms'] as List;
      expect(farms, hasLength(2));
      expect(farms[0]['farmer_uuid'], newFarmer);
      expect(farms[0].containsKey('farmer'), isFalse);
      expect(farms[1]['farmer'], 41);
      expect(farms[1].containsKey('farmer_uuid'), isFalse);
      expect(farms[0]['farm_size'], '2.50');

      final quotations = changes['quotations'] as List;
      expect(quotations[0]['farm_uuid'], newFarm);
      expect(quotations[1]['farm'], 5);
      expect(quotations[1]['insurance_product'], 3);
      expect(quotations[1]['sum_insured'], '50000.00');

      expect(transport.requests[0]['last_sync'], isNull);
      expect(transport.requests[0]['include_reference'], isTrue);
    });

    test('sends last_sync from the previous successful sync', () async {
      await engine.sync();
      await engine.sync();
      expect(transport.requests[1]['last_sync'], serverTime);
      await engine.sync(fullDownload: true);
      expect(transport.requests[2]['last_sync'], isNull);
    });

    test('rows in error are not re-sent until edited', () async {
      final uuid = await insertFarmer(db, status: SyncStatus.error);
      await engine.sync();
      expect(changesOf(0), isEmpty);
      await db.update(Tables.farmers, {'sync_status': SyncStatus.pending},
          where: 'client_uuid = ?', whereArgs: [uuid]);
      await engine.sync();
      expect((changesOf(1)['farmers'] as List).single['client_uuid'], uuid);
    });
  });

  group('per-item results', () {
    test('created stores server id and replaces the local copy with the record', () async {
      final farmer = await insertFarmer(db);
      final farm = await insertFarm(db, farmerUuid: farmer);
      transport.onSync = (payload) {
        final response = echoCreated(payload);
        final farmerResult = (response['results']['farmers'] as List).single;
        farmerResult['record'] = {
          ...farmerResult['record'],
          'farmer_id': 100,
          'first_name': 'JANE',
          'registration_latitude': '-1.286389',
          'next_of_kin': [
            {'next_of_kin_id': 9, 'farmer': 100, 'name': 'John', 'relationship': 'Spouse', 'phone_number': '07'}
          ],
        };
        final farmResult = (response['results']['farms'] as List).single;
        farmResult['record'] = {...farmResult['record'], 'farm_id': 101, 'farmer': 100};
        return response;
      };

      final report = await engine.sync();

      expect(report.ok, isTrue);
      expect(report.saved, 2);
      final f = await rowOf(db, Tables.farmers, farmer);
      expect(f['server_id'], 100);
      expect(f['sync_status'], SyncStatus.synced);
      expect(f['first_name'], 'JANE');
      expect(f['next_of_kin'], '[{"name":"John","relationship":"Spouse","phone_number":"07"}]');
      final fm = await rowOf(db, Tables.farms, farm);
      expect(fm['server_id'], 101);
      expect(fm['farmer_uuid'], farmer, reason: 'parent link survives');
      expect(fm['sync_status'], SyncStatus.synced);
    });

    test('updated marks synced', () async {
      final uuid = await insertFarmer(db, serverId: 7);
      transport.onSync = (payload) => okResponse(results: {
            'farmers': [
              {'client_uuid': uuid, 'status': 'updated', 'server_id': 7, 'record': {'farmer_id': 7, 'first_name': 'Jane', 'last_name': 'W'}}
            ]
          });
      await engine.sync();
      final row = await rowOf(db, Tables.farmers, uuid);
      expect(row['sync_status'], SyncStatus.synced);
      expect(row['last_name'], 'W');
    });

    test('duplicate links the farmer to the existing server record and tells the officer', () async {
      final uuid = await insertFarmer(db);
      final farm = await insertFarm(db, farmerUuid: uuid);
      transport.onSync = (payload) => okResponse(results: {
            'farmers': [
              {
                'client_uuid': uuid,
                'status': 'duplicate',
                'server_id': 55,
                'errors': {'id_number': ['A farmer with this ID number already exists.']}
              }
            ],
            'farms': [
              {'client_uuid': farm, 'status': 'pending_parent', 'server_id': null,
               'errors': {'farmer': ['Linked record has not been synced yet.']}}
            ],
          });

      final report = await engine.sync();

      expect(report.duplicates, 1);
      expect(report.notices.single, contains('already registered'));
      final row = await rowOf(db, Tables.farmers, uuid);
      expect(row['server_id'], 55);
      expect(row['sync_status'], SyncStatus.synced);
      expect(row['uuid_on_server'], 0);
      expect(row['notice'], contains('#55'));
      // Server copy wasn't in updates -> next sync is a full download.
      expect(await MetaStore.get(db, MetaKeys.forceFullDownload), '1');

      // Next sync: the farm now references the farmer by its server id.
      transport.onSync = (payload) => okResponse();
      await engine.sync();
      final farms = changesOf(1)['farms'] as List;
      expect(farms.single['farmer'], 55);
      expect(farms.single.containsKey('farmer_uuid'), isFalse);
      expect(transport.requests[1]['last_sync'], isNull, reason: 'full download to fetch the server copy');
      expect(await MetaStore.get(db, MetaKeys.forceFullDownload), isNull);
    });

    test('locked discards local edits and takes the server copy from updates', () async {
      final farmer = await insertFarmer(db, serverId: 1, status: SyncStatus.synced);
      final farm = await insertFarm(db, farmerUuid: farmer, serverId: 2, status: SyncStatus.synced);
      final quote = await insertQuotation(db, farmUuid: farm, serverId: 3, status: SyncStatus.synced, policyStatus: 'WRITTEN');
      final claim = await insertClaim(db, quotationUuid: quote, serverId: 17); // edited locally -> pending
      transport.onSync = (payload) => okResponse(results: {
            'claims': [
              {'client_uuid': claim, 'status': 'locked', 'server_id': 17,
               'errors': {'status': ['This record is APPROVED and can no longer be changed from the field.']}}
            ]
          }, updates: {
            'claims': [
              {'claim_id': 17, 'client_uuid': claim, 'quotation': 3, 'farmer': 1, 'claim_number': 'CLM-1',
               'estimated_loss_amount': '15000.00', 'approved_amount': '12000.00', 'status': 'APPROVED',
               'loss_details': {'cause': 'Drought'}}
            ]
          });

      final report = await engine.sync();

      expect(report.locked, 1);
      final row = await rowOf(db, Tables.claims, claim);
      expect(row['sync_status'], SyncStatus.synced);
      expect(row['status'], 'APPROVED');
      expect(row['estimated_loss_amount'], 15000.0);
      expect(row['quotation_uuid'], quote);
      expect(await MetaStore.get(db, MetaKeys.forceFullDownload), isNull);
    });

    test('pending_parent keeps the record queued and re-sends it', () async {
      final farmer = await insertFarmer(db);
      final farm = await insertFarm(db, farmerUuid: farmer);
      transport.onSync = (payload) => okResponse(results: {
            'farmers': [
              {'client_uuid': farmer, 'status': 'error', 'server_id': null,
               'errors': {'first_name': ['This field may not be blank.']}}
            ],
            'farms': [
              {'client_uuid': farm, 'status': 'pending_parent', 'server_id': null,
               'errors': {'farmer': ['Linked record has not been synced yet.']}}
            ],
          });

      final report = await engine.sync();
      expect(report.waitingForParent, 1);
      expect(report.rejected, 1);
      expect((await rowOf(db, Tables.farms, farm))['sync_status'], SyncStatus.pendingParent);

      transport.onSync = (payload) => okResponse();
      await engine.sync();
      final changes = changesOf(1);
      expect(changes.containsKey('farmers'), isFalse, reason: 'error rows wait for the officer');
      expect((changes['farms'] as List).single['farmer_uuid'], farmer);
    });

    test('error stores readable messages', () async {
      final farmer = await insertFarmer(db);
      transport.onSync = (payload) => okResponse(results: {
            'farmers': [
              {'client_uuid': farmer, 'status': 'error', 'server_id': null,
               'errors': {'phone_number': ['Enter a valid phone number.'], 'non_field_errors': ['Bad data.']}}
            ]
          });
      await engine.sync();
      final row = await rowOf(db, Tables.farmers, farmer);
      expect(row['sync_status'], SyncStatus.error);
      expect(row['sync_error'], 'Phone number: Enter a valid phone number.; Bad data.');
      expect(row['server_id'], isNull);
    });

    test('edits made while the request was in flight stay pending', () async {
      final farmer = await insertFarmer(db);
      transport.onSync = (payload) async {
        await db.update(Tables.farmers, {'phone_number': '0799999999', 'updated_at': 'later'},
            where: 'client_uuid = ?', whereArgs: [farmer]);
        return echoCreated(payload);
      };
      await engine.sync();
      final row = await rowOf(db, Tables.farmers, farmer);
      expect(row['server_id'], 100);
      expect(row['sync_status'], SyncStatus.pending);
      expect(row['phone_number'], '0799999999');
    });
  });

  group('updates and reference', () {
    test('upserts by client_uuid, then server id, else inserts; resolves parents', () async {
      final known = await insertFarmer(db, serverId: 1, status: SyncStatus.synced);
      final byServerId = await insertFarmer(db, serverId: 2, status: SyncStatus.synced, idNumber: '2');
      final pendingEdit = await insertFarmer(db, serverId: 3, idNumber: '3');
      transport.onSync = (payload) => okResponse(updates: {
            'farmers': [
              {'farmer_id': 1, 'client_uuid': known, 'first_name': 'Known', 'last_name': 'A', 'id_number': '1', 'phone_number': '1'},
              {'farmer_id': 2, 'client_uuid': null, 'first_name': 'ByServerId', 'last_name': 'B', 'id_number': '2', 'phone_number': '2'},
              {'farmer_id': 3, 'client_uuid': pendingEdit, 'first_name': 'ServerName', 'last_name': 'C', 'id_number': '3', 'phone_number': '3'},
              {'farmer_id': 4, 'client_uuid': null, 'first_name': 'Office', 'last_name': 'D', 'id_number': '4', 'phone_number': '4'},
            ],
            'farms': [
              {'farm_id': 9, 'client_uuid': null, 'farmer': 4, 'farm_name': 'Office farm', 'farm_size': '1.00', 'unit_of_measure': 'HECTARES'}
            ],
            'quotations': [
              {'quotation_id': 12, 'farm': 9, 'farmer': 4, 'insurance_product': 3, 'sum_insured': '1000.00',
               'premium_amount': '50.00', 'status': 'WRITTEN', 'policy_number': 'POL-1', 'product_name': 'Maize'}
            ],
          }, reference: {
            'insurance_products': [
              {'product_id': 3, 'product_name': 'Maize Long Rains', 'average_premium_rate': '5.00', 'status': 'ACTIVE'}
            ],
            'crops': [{'crop_id': 1, 'crop': 'Maize'}],
          });

      final report = await engine.sync();

      expect(report.ok, isTrue);
      expect((await rowOf(db, Tables.farmers, known))['first_name'], 'Known');
      expect((await rowOf(db, Tables.farmers, byServerId))['first_name'], 'ByServerId');
      expect((await rowOf(db, Tables.farmers, pendingEdit))['first_name'], 'Jane',
          reason: 'local unsynced edit wins');
      final office = (await db.query(Tables.farmers, where: 'server_id = 4')).single;
      expect(office['first_name'], 'Office');
      expect(office['uuid_on_server'], 0);
      expect(office['client_uuid'], isNotEmpty);
      final farm = (await db.query(Tables.farms, where: 'server_id = 9')).single;
      expect(farm['farmer_uuid'], office['client_uuid']);
      final quote = (await db.query(Tables.quotations, where: 'server_id = 12')).single;
      expect(quote['farm_uuid'], farm['client_uuid']);
      expect(quote['status'], 'WRITTEN');

      final products = await db.query(Tables.reference, where: "kind = 'insurance_products'");
      expect(products.single['server_id'], 3);
      expect(await db.query(Tables.reference, where: "kind = 'crops'"), hasLength(1));
      expect(await MetaStore.get(db, MetaKeys.lastSync), serverTime);
    });

    test('reference data is replaced, not appended', () async {
      transport.onSync = (p) => okResponse(reference: {
            'insurance_products': [
              {'product_id': 1}, {'product_id': 2}
            ]
          });
      await engine.sync();
      transport.onSync = (p) => okResponse(reference: {
            'insurance_products': [
              {'product_id': 2}
            ]
          });
      await engine.sync();
      final rows = await db.query(Tables.reference);
      expect(rows.map((r) => r['server_id']), [2]);
    });
  });

  group('locations', () {
    test('the location tree is stored when sent and kept when omitted', () async {
      transport.onSync = (p) => okResponse(reference: {
            'administrative_units': [
              {'unit_id': 1, 'parent': null, 'level': 'COUNTY', 'name': 'Nakuru'},
              {'unit_id': 2, 'parent': 1, 'level': 'SUB_COUNTY', 'name': 'Njoro'},
            ],
          });
      await engine.sync();
      transport.onSync = (p) => okResponse(reference: {'crops': []});
      await engine.sync();
      final units = await db.query(Tables.adminUnits, orderBy: 'unit_id');
      expect(units.map((u) => u['name']), ['Nakuru', 'Njoro']);
      expect(units.last['parent_id'], 1);
      expect(await db.query(Tables.reference, where: "kind = 'administrative_units'"), isEmpty);

      transport.onSync = (p) => okResponse(reference: {
            'administrative_units': [
              {'unit_id': 1, 'parent': null, 'level': 'COUNTY', 'name': 'Nakuru'},
            ],
          });
      await engine.sync();
      expect(await db.query(Tables.adminUnits), hasLength(1), reason: 'a sent tree replaces the local one');
    });

    test('farm location fields go up and come down', () async {
      final farmer = await insertFarmer(db, serverId: 41, status: SyncStatus.synced);
      final farm = await insertFarm(db, farmerUuid: farmer);
      await db.update(Tables.farms, {'administrative_unit_id': 7, 'location_unit_id': 11, 'village': 'Kapsita', 'clan': ''},
          where: 'client_uuid = ?', whereArgs: [farm]);
      transport.onSync = (p) => okResponse(updates: {
            'farms': [
              {'farm_id': 9, 'client_uuid': null, 'farmer': 41, 'farm_name': 'Office farm', 'farm_size': '1.00',
               'unit_of_measure': 'ACRES', 'administrative_unit': 8, 'location_unit': 12, 'village': 'Kamara', 'clan': 'Kipsigis A'}
            ],
          });

      await engine.sync();

      final sent = (changesOf(0)['farms'] as List).single;
      expect(sent['administrative_unit'], 7);
      expect(sent['location_unit'], 11);
      expect(sent['village'], 'Kapsita');
      expect(sent.containsKey('clan'), isTrue, reason: 'a cleared clan must reach the server');
      expect(sent['clan'], isNull);
      final office = (await db.query(Tables.farms, where: 'server_id = 9')).single;
      expect(office['administrative_unit_id'], 8);
      expect(office['location_unit_id'], 12);
      expect(office['village'], 'Kamara');
      expect(office['clan'], 'Kipsigis A');
    });
  });

  group('public ids', () {
    test('a new install asks for UUIDs straight away', () async {
      await engine.sync();
      expect(transport.uuidRequests, [true]);
    });

    test('an old install switches to UUIDs once nothing is waiting to upload', () async {
      await MetaStore.set(db, MetaKeys.idFormat, 'numeric');
      await MetaStore.set(db, MetaKeys.lastSync, serverTime);
      await insertFarmer(db, serverId: 41, status: SyncStatus.synced, idNumber: '2');
      final pending = await insertFarmer(db);
      transport.onSync = echoCreated;

      await engine.sync();
      expect(transport.uuidRequests, [false], reason: 'pending records go up with numeric ids first');
      expect(await db.query(Tables.farmers), hasLength(2));

      transport.onSync = (p) => okResponse(updates: {
            'farmers': [
              {'farmer_id': 'b6a1c2d4-0000-4000-8000-000000000001', 'client_uuid': pending,
               'first_name': 'Jane', 'last_name': 'W', 'id_number': '12345678', 'phone_number': '07'},
            ],
          });
      await engine.sync();
      expect(transport.uuidRequests, [false, true]);
      expect(transport.requests[1]['last_sync'], isNull, reason: 'everything is downloaded again');
      final farmers = await db.query(Tables.farmers);
      expect(farmers.map((f) => f['server_id']), ['b6a1c2d4-0000-4000-8000-000000000001']);
      expect(farmers.single['client_uuid'], pending, reason: 'device records keep their uuid');
      expect(await MetaStore.get(db, MetaKeys.idFormat), 'uuid');
    });

    test('UUID server ids link parents and go back up as references', () async {
      const farmerId = 'b6a1c2d4-0000-4000-8000-0000000000aa';
      transport.onSync = (p) => okResponse(updates: {
            'farmers': [
              {'farmer_id': farmerId, 'client_uuid': null, 'first_name': 'O', 'last_name': 'D',
               'id_number': '9', 'phone_number': '9'}
            ],
            'farms': [
              {'farm_id': 'b6a1c2d4-0000-4000-8000-0000000000bb', 'client_uuid': null, 'farmer': farmerId,
               'farm_name': 'Office farm', 'farm_size': '1.00', 'unit_of_measure': 'ACRES'}
            ],
          });
      await engine.sync();
      final office = (await db.query(Tables.farmers)).single;
      final farm = (await db.query(Tables.farms)).single;
      expect(farm['farmer_uuid'], office['client_uuid']);
      await insertQuotation(db, farmUuid: farm['client_uuid'] as String);
      transport.onSync = (p) => okResponse();
      await engine.sync();
      final sent = (changesOf(1)['quotations'] as List).single;
      expect(sent['farm'], 'b6a1c2d4-0000-4000-8000-0000000000bb');
    });
  });

  group('failures', () {
    test('network failure keeps every local record and last_sync', () async {
      await MetaStore.set(db, MetaKeys.lastSync, 'previous');
      final farmer = await insertFarmer(db);
      transport.onSync = (payload) => throw const NetworkException();

      final report = await engine.sync();

      expect(report.ok, isFalse);
      expect(report.error, isA<NetworkException>());
      final row = await rowOf(db, Tables.farmers, farmer);
      expect(row['sync_status'], SyncStatus.pending);
      expect(row['server_id'], isNull);
      expect(await MetaStore.get(db, MetaKeys.lastSync), 'previous');
    });

    test('a response that cannot be fully applied is rolled back', () async {
      await MetaStore.set(db, MetaKeys.lastSync, 'previous');
      final farmer = await insertFarmer(db);
      transport.onSync = (payload) => okResponse(results: {
            'farmers': [
              {'client_uuid': farmer, 'status': 'created', 'server_id': 100,
               'record': {'farmer_id': 100, 'first_name': 'X', 'last_name': 'Y', 'id_number': '1', 'phone_number': '1'}}
            ]
          }, updates: {
            'inspections': [
              {'inspection_id': 1, 'farm': 1, 'inspection_type': 'MID_SEASON'}
            ]
          });
      // Make applying the second half of the response fail.
      await db.execute("CREATE TRIGGER boom BEFORE INSERT ON inspections BEGIN SELECT RAISE(ABORT, 'boom'); END");

      final report = await engine.sync();

      expect(report.ok, isFalse);
      final row = await rowOf(db, Tables.farmers, farmer);
      expect(row['server_id'], isNull, reason: 'results rolled back with the rest');
      expect(row['sync_status'], SyncStatus.pending);
      expect(await MetaStore.get(db, MetaKeys.lastSync), 'previous');
    });

    test('missing server_time is treated as a failure', () async {
      final farmer = await insertFarmer(db);
      transport.onSync = (payload) => {'results': {}, 'updates': {}};
      final report = await engine.sync();
      expect(report.ok, isFalse);
      expect((await rowOf(db, Tables.farmers, farmer))['sync_status'], SyncStatus.pending);
      expect(await MetaStore.get(db, MetaKeys.lastSync), isNull);
    });
  });

  test('concurrent sync calls share one run', () async {
    final gate = Completer<void>();
    transport.onSync = (payload) async {
      await gate.future;
      return okResponse();
    };
    final first = engine.sync();
    final second = engine.sync();
    expect(engine.isRunning, isTrue);
    gate.complete();
    final reports = await Future.wait([first, second]);
    expect(identical(reports[0], reports[1]), isTrue);
    expect(transport.requests, hasLength(1));
    expect(engine.isRunning, isFalse);

    await engine.sync();
    expect(transport.requests, hasLength(2), reason: 'a later call runs again');
  });

  group('photos', () {
    late File photoFile;

    setUp(() async {
      photoFile = File('${(await Directory.systemTemp.createTemp('photo')).path}/p.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF]);
    });

    Future<String> insertPhoto(String entityType, String owner) async {
      final uuid = newUuid();
      await db.insert(Tables.media, {
        'client_uuid': uuid,
        'entity_type': entityType,
        'entity_uuid': owner,
        'file_path': photoFile.path,
        'latitude': -1.5,
        'longitude': 36.9,
        'taken_at': nowIso(),
        'updated_at': nowIso(),
      });
      return uuid;
    }

    Future<Map<String, Object?>> photo(String uuid) async =>
        (await db.query(Tables.media, where: 'client_uuid = ?', whereArgs: [uuid])).single;

    test('upload after the owner syncs, using its server id', () async {
      final farmer = await insertFarmer(db);
      final pic = await insertPhoto('farmer', farmer);
      transport.onSync = echoCreated;

      final report = await engine.sync();

      expect(report.photosUploaded, 1);
      final upload = transport.uploads.single;
      expect(upload['entity_type'], 'farmer');
      expect(upload['entity_id'], 100);
      expect(upload['client_uuid'], pic);
      expect(upload['latitude'], '-1.500000');
      expect((await photo(pic))['sync_status'], SyncStatus.synced);
      expect((await rowOf(db, Tables.farmers, farmer))['photo_url'], contains(pic));
    });

    test('photos of unsynced records wait; 409 pending_parent retries later', () async {
      final farmer = await insertFarmer(db, serverId: 1, status: SyncStatus.synced);
      final farm = await insertFarm(db, farmerUuid: farmer, serverId: 2, status: SyncStatus.synced);
      final quote = await insertQuotation(db, farmUuid: farm, serverId: 3, status: SyncStatus.synced);
      final claim = await insertClaim(db, quotationUuid: quote);
      final pic = await insertPhoto('claim', claim);

      transport.onSync = (payload) => okResponse(results: {
            'claims': [
              {'client_uuid': claim, 'status': 'error', 'errors': {'estimated_loss_amount': ['Too high']}}
            ]
          });
      var report = await engine.sync();
      expect(transport.uploads, isEmpty);
      expect(report.photosWaiting, 1);

      await db.update(Tables.claims, {'server_id': 17, 'sync_status': SyncStatus.synced});
      transport.onSync = (payload) => okResponse();
      transport.onUpload = (fields, path) => (409, {'code': 'pending_parent'});
      report = await engine.sync();
      expect(transport.uploads, hasLength(1));
      expect((await photo(pic))['sync_status'], SyncStatus.pending);

      transport.onUpload = (fields, path) => (200, {'file_url': 'http://x/p.jpg'});
      report = await engine.sync();
      expect(report.photosUploaded, 1);
      expect((await photo(pic))['sync_status'], SyncStatus.synced);
    });

    test('network failure during upload keeps photos queued', () async {
      final farmer = await insertFarmer(db, serverId: 1, status: SyncStatus.synced);
      final pic = await insertPhoto('farmer', farmer);
      transport.onUpload = (fields, path) => throw const NetworkException();
      final report = await engine.sync();
      expect(report.ok, isTrue, reason: 'data sync itself succeeded');
      expect(report.photoError, isA<NetworkException>());
      expect((await photo(pic))['sync_status'], SyncStatus.pending);
    });
  });
}
