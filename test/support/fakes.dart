import 'dart:async';
import 'dart:io';

import 'package:insurance_mobile/core/db/app_database.dart';
import 'package:insurance_mobile/core/sync/sync_transport.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Fake HTTP layer for the sync engine.
class FakeTransport implements SyncTransport {
  final List<Map<String, dynamic>> requests = [];
  final List<bool> uuidRequests = [];
  final List<Map<String, Object?>> uploads = [];

  /// Builds the /sync/ response from the request. Throw to simulate failures.
  FutureOr<Map<String, dynamic>> Function(Map<String, dynamic> payload) onSync =
      (payload) => okResponse();

  FutureOr<(int, Map<String, dynamic>)> Function(Map<String, Object?> fields, String path) onUpload =
      (fields, path) => (201, {'file_url': 'http://server/media/${fields['client_uuid']}.jpg'});

  @override
  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload, {bool uuidIds = false}) async {
    requests.add(payload);
    uuidRequests.add(uuidIds);
    return onSync(payload);
  }

  @override
  Future<(int, Map<String, dynamic>)> upload(Map<String, Object?> fields, String filePath,
      {bool uuidIds = false}) async {
    uploads.add({...fields, 'path': filePath});
    return onUpload(fields, filePath);
  }
}

const serverTime = '2026-10-14T06:40:00+00:00';

Map<String, dynamic> okResponse({
  Map<String, dynamic> results = const {},
  Map<String, dynamic> updates = const {},
  Map<String, dynamic>? reference,
  String time = serverTime,
}) =>
    {
      'server_time': time,
      'results': results,
      'updates': updates,
      if (reference != null) 'reference': reference,
    };

/// Echoes every pushed item back as created with sequential server ids.
Map<String, dynamic> echoCreated(Map<String, dynamic> payload, {int startId = 100}) {
  var nextId = startId;
  final results = <String, dynamic>{};
  final changes = payload['changes'] as Map<String, dynamic>;
  for (final entry in changes.entries) {
    results[entry.key] = [
      for (final item in entry.value as List)
        {
          'client_uuid': item['client_uuid'],
          'status': 'created',
          'server_id': nextId++,
          'record': {...item as Map<String, dynamic>},
        }
    ];
  }
  return okResponse(results: results);
}

Future<Database> openTestDb() async {
  sqfliteFfiInit();
  final dir = await Directory.systemTemp.createTemp('sync_test');
  return AppDatabase.open(factory: databaseFactoryFfi, path: '${dir.path}/test.db');
}

int _seq = 0;

Map<String, Object?> _sync({String? uuid, int? serverId, String status = SyncStatus.pending}) {
  final now = '2026-10-14T06:00:00.${(_seq++).toString().padLeft(6, '0')}Z';
  return {
    'client_uuid': uuid ?? newUuid(),
    'server_id': serverId,
    'sync_status': status,
    'created_at': now,
    'updated_at': now,
  };
}

Future<String> insertFarmer(Database db,
    {String? uuid, int? serverId, String status = SyncStatus.pending, String idNumber = '12345678'}) async {
  final row = {
    ..._sync(uuid: uuid, serverId: serverId, status: status),
    'first_name': 'Jane',
    'last_name': 'Wanjiku',
    'id_number': idNumber,
    'phone_number': '0712345678',
    'gender': 'F',
    'registration_latitude': -1.286389,
    'registration_longitude': 36.817223,
    'next_of_kin': '[{"name":"John","relationship":"Spouse","phone_number":"0700000000"}]',
    'bank_accounts': '[]',
  };
  await db.insert(Tables.farmers, row);
  return row['client_uuid'] as String;
}

Future<String> insertFarm(Database db,
    {required String? farmerUuid, int? farmerServerId, int? serverId, String status = SyncStatus.pending}) async {
  final row = {
    ..._sync(serverId: serverId, status: status),
    'farmer_uuid': farmerUuid,
    'farmer_server_id': farmerServerId,
    'farm_name': 'Shamba',
    'farm_size': 2.5,
    'unit_of_measure': 'ACRES',
    'location_province': 'Nakuru',
    'latitude': -1.2,
    'longitude': 36.8,
    'status': 'ACTIVE',
  };
  await db.insert(Tables.farms, row);
  return row['client_uuid'] as String;
}

Future<String> insertQuotation(Database db,
    {required String farmUuid, int? serverId, String status = SyncStatus.pending, String? policyStatus}) async {
  final row = {
    ..._sync(serverId: serverId, status: status),
    'farm_uuid': farmUuid,
    'insurance_product_id': 3,
    'sum_insured': 50000.0,
    'status': policyStatus,
  };
  await db.insert(Tables.quotations, row);
  return row['client_uuid'] as String;
}

Future<String> insertClaim(Database db,
    {required String quotationUuid, int? serverId, String status = SyncStatus.pending}) async {
  final row = {
    ..._sync(serverId: serverId, status: status),
    'quotation_uuid': quotationUuid,
    'estimated_loss_amount': 20000.0,
    'loss_details': '{"cause":"Drought","description":"Dry spell"}',
    'status': serverId == null ? null : 'OPEN',
  };
  await db.insert(Tables.claims, row);
  return row['client_uuid'] as String;
}

Future<Map<String, Object?>> rowOf(Database db, String table, String uuid) async =>
    (await db.query(table, where: 'client_uuid = ?', whereArgs: [uuid])).single;
