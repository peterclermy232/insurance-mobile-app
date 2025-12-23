import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class AppDatabase {
  static final AppDatabase instance = AppDatabase._init();
  static Database? _database;

  AppDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('insurance.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const intType = 'INTEGER';
    const realType = 'REAL';

    await db.execute('''
      CREATE TABLE farmers (
        id $idType,
        server_id $intType,
        organisation_id $intType,
        first_name $textType,
        last_name $textType,
        id_number $textType UNIQUE,
        phone_number $textType,
        email TEXT,
        gender TEXT,
        latitude $realType,
        longitude $realType,
        photo_path TEXT,
        sync_status TEXT DEFAULT 'pending',
        created_at $intType,
        updated_at $intType
      )
    ''');

    await db.execute('''
      CREATE TABLE farms (
        id $idType,
        server_id $intType,
        farmer_id $intType,
        farm_name $textType,
        farm_size $realType,
        unit_of_measure TEXT,
        location_province TEXT,
        location_district TEXT,
        location_sector TEXT,
        latitude $realType,
        longitude $realType,
        sync_status TEXT DEFAULT 'pending',
        created_at $intType
      )
    ''');

    await db.execute('''
      CREATE TABLE claims (
        id $idType,
        server_id $intType,
        farmer_id $intType,
        quotation_id $intType,
        claim_number TEXT UNIQUE,
        estimated_loss_amount $realType,
        loss_details TEXT,
        photos TEXT,
        assessor_notes TEXT,
        latitude $realType,
        longitude $realType,
        sync_status TEXT DEFAULT 'pending',
        created_at $intType,
        updated_at $intType
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_queue (
        id $idType,
        entity_type $textType,
        entity_id $intType,
        operation TEXT,
        priority $intType DEFAULT 5,
        retry_count $intType DEFAULT 0,
        error_message TEXT,
        created_at $intType
      )
    ''');

    await db.execute('''
      CREATE TABLE media_queue (
        id $idType,
        file_path $textType,
        entity_type TEXT,
        entity_id $intType,
        sync_status TEXT DEFAULT 'pending',
        created_at $intType
      )
    ''');
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}