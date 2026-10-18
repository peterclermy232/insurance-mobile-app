import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:insurance_mobile/core/db/app_database.dart';
import 'package:insurance_mobile/core/db/meta_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('fresh install creates the schema', () async {
    final dir = await Directory.systemTemp.createTemp('db');
    final db = await AppDatabase.open(factory: databaseFactoryFfi, path: '${dir.path}/a.db');
    final tables = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
        .map((r) => r['name'])
        .toSet();
    expect(tables, containsAll([...Tables.entities, Tables.media, Tables.reference, Tables.meta]));
    expect(await db.getVersion(), AppDatabase.version);
    await db.close();
  });

  test('upgrade from the pre-release schema keeps unsynced farmers', () async {
    final dir = await Directory.systemTemp.createTemp('db');
    final path = '${dir.path}/old.db';
    final old = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) async {
            await db.execute('''CREATE TABLE farmers (id INTEGER PRIMARY KEY, first_name TEXT, last_name TEXT,
              id_number TEXT, phone_number TEXT, email TEXT, gender TEXT, date_of_birth INTEGER,
              organisation_id INTEGER, registration_latitude REAL, registration_longitude REAL, server_id INTEGER)''');
            await db.execute('CREATE TABLE sync_queue (id INTEGER PRIMARY KEY)');
          },
        ));
    await old.insert('farmers', {
      'first_name': 'Old', 'last_name': 'Unsynced', 'id_number': '111', 'phone_number': '0711',
      'date_of_birth': DateTime(1990, 5, 1).millisecondsSinceEpoch,
    });
    await old.insert('farmers', {'first_name': 'Old', 'last_name': 'Synced', 'id_number': '222', 'phone_number': '0722', 'server_id': 9});
    await old.close();

    final db = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
    final farmers = await db.query(Tables.farmers);
    expect(farmers, hasLength(1));
    expect(farmers.single['last_name'], 'Unsynced');
    expect(farmers.single['sync_status'], SyncStatus.pending);
    expect(farmers.single['date_of_birth'], '1990-05-01');
    expect(farmers.single['client_uuid'], isNotEmpty);
    final tables = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'")).map((r) => r['name']);
    expect(tables, isNot(contains('sync_queue')));
    await db.close();
  });

  test('upgrade from v10 keeps farms, adds location columns and forces a full download', () async {
    final dir = await Directory.systemTemp.createTemp('db');
    final path = '${dir.path}/v10.db';
    final old = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 10,
          onCreate: (db, _) async {
            await AppDatabase.createSchema(db);
            await db.execute('DROP TABLE ${Tables.adminUnits}');
            for (final column in ['administrative_unit_id', 'location_unit_id', 'village', 'clan']) {
              await db.execute('ALTER TABLE ${Tables.farms} DROP COLUMN $column');
            }
          },
        ));
    await old.insert(Tables.farms, {
      'client_uuid': 'f1', 'created_at': 'x', 'updated_at': 'x', 'farm_name': 'Shamba', 'sync_status': 'pending',
    });
    await MetaStore.set(old, MetaKeys.lastSync, '2026-10-01T00:00:00+00:00');
    await old.close();

    final db = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
    final farm = (await db.query(Tables.farms)).single;
    expect(farm['farm_name'], 'Shamba');
    expect(farm.containsKey('village'), isTrue);
    expect(farm.containsKey('location_unit_id'), isTrue);
    expect(await db.query(Tables.adminUnits), isEmpty);
    expect(await MetaStore.get(db, MetaKeys.forceFullDownload), '1');
    await db.close();
  });
}
