import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Small key/value table for sync bookkeeping.
class MetaKeys {
  MetaKeys._();
  static const lastSync = 'last_sync';
  static const forceFullDownload = 'force_full_download';
  /// 'uuid' once local server ids are the server's public UUIDs; 'numeric' on
  /// installs that still hold the old sequential ids (see SyncEngine._useUuidIds).
  static const idFormat = 'id_format';
  static const ownerUserId = 'owner_user_id';
  static const ownerName = 'owner_name';
}

class MetaStore {
  MetaStore._();

  static Future<String?> get(DatabaseExecutor db, String key) async {
    final rows = await db.query(Tables.meta, where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  static Future<void> set(DatabaseExecutor db, String key, String? value) async {
    if (value == null) {
      await db.delete(Tables.meta, where: 'key = ?', whereArgs: [key]);
    } else {
      await db.insert(Tables.meta, {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
}
