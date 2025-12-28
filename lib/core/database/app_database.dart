import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';

class AppDatabase {
  static final AppDatabase instance = AppDatabase._init();
  static Database? _database;

  AppDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('insurance_app.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2, // Incremented for migration
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  /// Migration handler - adds missing columns to existing database
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print('🔄 Upgrading database from v$oldVersion to v$newVersion');

    if (oldVersion < 2) {
      // Add missing latitude & longitude to farmers
      try {
        await db.execute('ALTER TABLE farmers ADD COLUMN registration_latitude REAL');
        await db.execute('ALTER TABLE farmers ADD COLUMN registration_longitude REAL');
        print('Added latitude & longitude columns to farmers table');
      } catch (e) {
        print('Latitude/Longitude columns might already exist: $e');
      }

      // Add date_of_birth to farmers
      try {
        await db.execute('ALTER TABLE farmers ADD COLUMN date_of_birth INTEGER');
        print('Added date_of_birth column to farmers table');
      } catch (e) {
        print('Column date_of_birth might already exist: $e');
      }

      // Add columns to claims table
      try {
        await db.execute('ALTER TABLE claims ADD COLUMN photos TEXT');
        await db.execute('ALTER TABLE claims ADD COLUMN registration_latitude REAL');
        await db.execute('ALTER TABLE claims ADD COLUMN registration_latitude REAL');
        await db.execute('ALTER TABLE claims ADD COLUMN assessor_notes TEXT');
        await db.execute("ALTER TABLE claims ADD COLUMN status TEXT DEFAULT 'OPEN'");
        print('Updated claims table with new columns');
      } catch (e) {
        print('Some columns might already exist in claims: $e');
      }
    }
  }

  /// Create all tables
  Future<void> _createDB(Database db, int version) async {
    print('📦 Creating database tables...');

    // Farmers table
    await db.execute('''
      CREATE TABLE farmers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        first_name TEXT NOT NULL,
        last_name TEXT NOT NULL,
        id_number TEXT NOT NULL,
        phone_number TEXT NOT NULL,
        email TEXT,
        gender TEXT,
        date_of_birth INTEGER,
        organisation_id INTEGER NOT NULL,
        country_id INTEGER,
        status TEXT DEFAULT 'ACTIVE',
        synced INTEGER DEFAULT 0,
        registration_latitude REAL,
        registration_longitude REAL,
        photo_path TEXT,
        server_id INTEGER,
        sync_status TEXT DEFAULT 'pending',
        created_at INTEGER,
        updated_at INTEGER
      )
    ''');
    print('Created farmers table');

    // Claims table
    await db.execute('''
      CREATE TABLE claims (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        farmer_id INTEGER NOT NULL,
        server_id INTEGER,
        claim_number TEXT,
        quotation_id INTEGER NOT NULL,
        estimated_loss_amount REAL NOT NULL,
        assessor_notes TEXT,
        loss_details TEXT,
        photos TEXT,
        registration_latitude REAL,
        registration_latitude REAL,
        sync_status TEXT DEFAULT 'pending',
        status TEXT DEFAULT 'OPEN',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (farmer_id) REFERENCES farmers(id)
      )
    ''');
    print('Created claims table');

    // Farms table
    await db.execute('''
      CREATE TABLE farms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        farmer_id INTEGER NOT NULL,
        server_id INTEGER,
        farm_name TEXT NOT NULL,
        location TEXT,
        registration_latitude REAL,
        registration_latitude REAL,
        size_acres REAL,
        crop_type TEXT,
        sync_status TEXT DEFAULT 'pending',
        synced INTEGER DEFAULT 0,
        created_at INTEGER,
        updated_at INTEGER,
        FOREIGN KEY (farmer_id) REFERENCES farmers(id)
      )
    ''');
    print(' Created farms table');

    // Quotations table
    await db.execute('''
      CREATE TABLE quotations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        farmer_id INTEGER NOT NULL,
        farm_id INTEGER,
        server_id INTEGER,
        premium_amount REAL NOT NULL,
        sum_insured REAL NOT NULL,
        coverage_period_start INTEGER,
        coverage_period_end INTEGER,
        status TEXT DEFAULT 'DRAFT',
        sync_status TEXT DEFAULT 'pending',
        synced INTEGER DEFAULT 0,
        created_at INTEGER,
        updated_at INTEGER,
        FOREIGN KEY (farmer_id) REFERENCES farmers(id),
        FOREIGN KEY (farm_id) REFERENCES farms(id)
      )
    ''');
    print('Created quotations table');

    // Sync queue table
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_id INTEGER NOT NULL,
        operation TEXT NOT NULL,
        priority INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    print('Created sync_queue table');

    // Media queue table
    await db.execute('''
      CREATE TABLE media_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id INTEGER NOT NULL,
        sync_status TEXT DEFAULT 'pending',
        created_at INTEGER NOT NULL
      )
    ''');
    print('Created media_queue table');

    print('All tables created successfully!');
  }

  /// Close database
  Future<void> close() async {
    final db = await instance.database;
    await db.close();
  }

  /// Delete database (for testing/reset)
  Future<void> deleteDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'insurance_app.db');
    await databaseFactory.deleteDatabase(path);
    _database = null;
    print('🗑️ Database deleted');
  }

  /// Check if database needs upgrade
  Future<bool> needsUpgrade() async {
    final db = await database;
    final currentVersion = await db.getVersion();
    return currentVersion < 2;
  }

  /// Get database info
  Future<Map<String, dynamic>> getDatabaseInfo() async {
    final db = await database;
    final version = await db.getVersion();
    final path = db.path;

    // Get table info
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
    );

    return {
      'version': version,
      'path': path,
      'tables': tables.map((t) => t['name']).toList(),
    };
  }

  /// Get farmers count
  Future<int> getFarmersCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM farmers');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get claims count
  Future<int> getClaimsCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM claims');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get pending sync count
  Future<int> getPendingSyncCount() async {
    final db = await database;

    final farmersCount = Sqflite.firstIntValue(
        await db.rawQuery(
            "SELECT COUNT(*) as count FROM farmers WHERE sync_status = 'pending'"
        )
    ) ?? 0;

    final claimsCount = Sqflite.firstIntValue(
        await db.rawQuery(
            "SELECT COUNT(*) as count FROM claims WHERE sync_status = 'pending'"
        )
    ) ?? 0;

    return farmersCount + claimsCount;
  }
}
