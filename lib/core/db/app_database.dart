import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../utils/logger.dart';
import 'meta_store.dart';

/// Row-level sync states stored in `sync_status`.
class SyncStatus {
  SyncStatus._();

  /// Captured or edited on the device, not yet accepted by the server.
  static const pending = 'pending';

  /// Server copy and local copy match.
  static const synced = 'synced';

  /// Server rejected the record; `sync_error` holds the reason. Not re-sent
  /// until the officer edits it or taps retry.
  static const error = 'error';

  /// Parent record is not on the server yet; re-sent on the next sync.
  static const pendingParent = 'pending_parent';

  /// States that are pushed on the next sync.
  static const pushable = [pending, pendingParent];

  /// States that represent local data the server does not have yet.
  static const unsynced = [pending, pendingParent, error];
}

class Tables {
  Tables._();
  static const farmers = 'farmers';
  static const farms = 'farms';
  static const quotations = 'quotations';
  static const claims = 'claims';
  static const inspections = 'inspections';
  static const media = 'media';
  static const reference = 'reference_data';
  static const adminUnits = 'admin_units';
  static const meta = 'sync_meta';

  /// Syncable entity tables, parents first (same order the server uses).
  static const entities = [farmers, farms, quotations, claims, inspections];
}

/// Opens the local SQLite database and owns its schema.
class AppDatabase {
  AppDatabase._();

  static const fileName = 'insurance_app.db';

  /// v1/v2 were the pre-release schema (broken on fresh installs).
  static const version = 11;

  static Future<Database> open({DatabaseFactory? factory, String? path}) async {
    final dbFactory = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await dbFactory.getDatabasesPath(), fileName);
    return dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = OFF'),
        onCreate: (db, _) => createSchema(db),
        onUpgrade: _onUpgrade,
        onDowngrade: (db, oldVersion, newVersion) async {
          await _dropAll(db);
          await createSchema(db);
        },
      ),
    );
  }

  /// Columns every syncable table carries.
  static const _syncColumns = '''
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    client_uuid TEXT NOT NULL UNIQUE,
    server_id INTEGER,
    uuid_on_server INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'pending',
    sync_error TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    server_updated_at TEXT
  ''';

  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ${Tables.farmers} (
        $_syncColumns,
        first_name TEXT NOT NULL,
        last_name TEXT NOT NULL,
        id_number TEXT NOT NULL,
        phone_number TEXT NOT NULL,
        email TEXT,
        gender TEXT,
        date_of_birth TEXT,
        farmer_category TEXT,
        registration_latitude REAL,
        registration_longitude REAL,
        registration_accuracy REAL,
        photo_url TEXT,
        next_of_kin TEXT NOT NULL DEFAULT '[]',
        bank_accounts TEXT NOT NULL DEFAULT '[]',
        status TEXT,
        notice TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE ${Tables.farms} (
        $_syncColumns,
        farmer_uuid TEXT,
        farmer_server_id INTEGER,
        farm_name TEXT NOT NULL,
        farm_size REAL,
        unit_of_measure TEXT,
        location_province TEXT,
        location_district TEXT,
        location_sector TEXT,
        administrative_unit_id INTEGER,
        location_unit_id INTEGER,
        village TEXT,
        clan TEXT,
        latitude REAL,
        longitude REAL,
        gps_accuracy REAL,
        status TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE ${Tables.quotations} (
        $_syncColumns,
        farm_uuid TEXT,
        farm_server_id INTEGER,
        farmer_server_id INTEGER,
        insurance_product_id INTEGER,
        product_name TEXT,
        sum_insured REAL,
        premium_amount REAL,
        estimated_premium REAL,
        policy_number TEXT,
        status TEXT,
        quotation_date TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE ${Tables.claims} (
        $_syncColumns,
        quotation_uuid TEXT,
        quotation_server_id INTEGER,
        farmer_server_id INTEGER,
        claim_number TEXT,
        estimated_loss_amount REAL,
        approved_amount REAL,
        status TEXT,
        loss_details TEXT NOT NULL DEFAULT '{}',
        claim_date TEXT,
        assessor_name TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE ${Tables.inspections} (
        $_syncColumns,
        farm_uuid TEXT,
        farm_server_id INTEGER,
        inspection_type TEXT NOT NULL,
        status TEXT,
        scheduled_date TEXT,
        scheduled_time TEXT,
        completed_at TEXT,
        check_in_latitude REAL,
        check_in_longitude REAL,
        check_in_time TEXT,
        check_out_latitude REAL,
        check_out_longitude REAL,
        check_out_time TEXT,
        findings TEXT NOT NULL DEFAULT '{}',
        recommendations TEXT,
        inspector_name TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE ${Tables.media} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_uuid TEXT NOT NULL UNIQUE,
        entity_type TEXT NOT NULL,
        entity_uuid TEXT NOT NULL,
        file_path TEXT NOT NULL,
        caption TEXT,
        latitude REAL,
        longitude REAL,
        taken_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        sync_error TEXT,
        remote_url TEXT,
        attempts INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE ${Tables.reference} (
        kind TEXT NOT NULL,
        server_id INTEGER NOT NULL,
        data TEXT NOT NULL,
        PRIMARY KEY (kind, server_id)
      )
    ''');
    await db.execute('CREATE TABLE ${Tables.meta} (key TEXT PRIMARY KEY, value TEXT)');
    await _createAdminUnits(db);
    // A new database has no server ids yet, so it starts with public UUIDs
    await db.insert(Tables.meta, {'key': MetaKeys.idFormat, 'value': 'uuid'});

    for (final table in Tables.entities) {
      await db.execute('CREATE INDEX idx_${table}_server_id ON $table (server_id)');
      await db.execute('CREATE INDEX idx_${table}_sync ON $table (sync_status)');
    }
    await db.execute('CREATE INDEX idx_farms_farmer ON ${Tables.farms} (farmer_uuid)');
    await db.execute('CREATE INDEX idx_quotations_farm ON ${Tables.quotations} (farm_uuid)');
    await db.execute('CREATE INDEX idx_claims_quotation ON ${Tables.claims} (quotation_uuid)');
    await db.execute('CREATE INDEX idx_inspections_farm ON ${Tables.inspections} (farm_uuid)');
    await db.execute('CREATE INDEX idx_media_entity ON ${Tables.media} (entity_uuid)');
  }

  /// The pre-release schema (v1/v2) can't be upgraded in place. Unsynced
  /// farmers are carried over; everything else is re-downloaded on next sync.
  /// Country -> county -> ... -> sub-location tree, downloaded as reference data.
  static Future<void> _createAdminUnits(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ${Tables.adminUnits} (
        unit_id INTEGER PRIMARY KEY,
        parent_id INTEGER,
        level TEXT NOT NULL,
        name TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_admin_units_parent ON ${Tables.adminUnits} (parent_id)');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 10) return _upgradeFromPreRelease(db);
    if (oldVersion < 11) {
      await db.execute('ALTER TABLE ${Tables.farms} ADD COLUMN administrative_unit_id INTEGER');
      await db.execute('ALTER TABLE ${Tables.farms} ADD COLUMN location_unit_id INTEGER');
      await db.execute('ALTER TABLE ${Tables.farms} ADD COLUMN village TEXT');
      await db.execute('ALTER TABLE ${Tables.farms} ADD COLUMN clan TEXT');
      await _createAdminUnits(db);
      // The server only sends the location tree on a full download
      await db.insert(Tables.meta, {'key': MetaKeys.forceFullDownload, 'value': '1'},
          conflictAlgorithm: ConflictAlgorithm.replace);
      // Existing data holds numeric server ids; the sync engine moves it to UUIDs
      await db.insert(Tables.meta, {'key': MetaKeys.idFormat, 'value': 'numeric'},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  static Future<void> _upgradeFromPreRelease(Database db) async {
    List<Map<String, Object?>> oldFarmers = const [];
    try {
      final columns = (await db.rawQuery('PRAGMA table_info(farmers)'))
          .map((c) => c['name'] as String)
          .toSet();
      if (columns.containsAll({'first_name', 'last_name', 'id_number', 'phone_number'})) {
        final unsynced = columns.contains('server_id') ? 'WHERE server_id IS NULL' : '';
        oldFarmers = await db.rawQuery('SELECT * FROM farmers $unsynced');
      }
    } catch (e) {
      Log.d('Old farmers table not readable, starting fresh: $e', tag: 'db');
    }

    await _dropAll(db);
    await createSchema(db);

    final now = DateTime.now().toUtc().toIso8601String();
    for (final old in oldFarmers) {
      try {
        await db.insert(Tables.farmers, {
          'client_uuid': const Uuid().v4(),
          'uuid_on_server': 1,
          'sync_status': SyncStatus.pending,
          'created_at': now,
          'updated_at': now,
          'first_name': old['first_name'],
          'last_name': old['last_name'],
          'id_number': old['id_number'],
          'phone_number': old['phone_number'],
          'email': old['email'],
          'gender': old['gender'],
          'date_of_birth': _legacyDate(old['date_of_birth']),
          'registration_latitude': old['registration_latitude'],
          'registration_longitude': old['registration_longitude'],
        });
      } catch (e) {
        Log.d('Skipped a legacy farmer row: $e', tag: 'db');
      }
    }
  }

  static String? _legacyDate(Object? value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value).toIso8601String().substring(0, 10);
    }
    if (value is String && value.length >= 10) return value.substring(0, 10);
    return null;
  }

  static Future<void> _dropAll(Database db) async {
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' "
        "AND name != 'android_metadata'");
    for (final t in tables) {
      await db.execute('DROP TABLE IF EXISTS "${t['name']}"');
    }
  }
}

String nowIso() => DateTime.now().toUtc().toIso8601String();

String newUuid() => const Uuid().v4();
