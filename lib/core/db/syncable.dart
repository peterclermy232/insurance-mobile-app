import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../utils/formatters.dart';
import 'app_database.dart';

/// Sync state common to every syncable record, for badges and edit rules.
class SyncInfo {
  const SyncInfo({
    required this.status,
    this.error,
    this.serverId,
    this.uuidOnServer = true,
  });

  factory SyncInfo.fromRow(Map<String, Object?> row) => SyncInfo(
        status: row['sync_status'] as String? ?? SyncStatus.pending,
        error: row['sync_error'] as String?,
        serverId: toServerId(row['server_id']),
        uuidOnServer: (row['uuid_on_server'] as int? ?? 1) == 1,
      );

  final String status;
  final String? error;
  final String? serverId;
  final bool uuidOnServer;

  bool get isSynced => status == SyncStatus.synced;
  bool get needsAttention => status == SyncStatus.error;
  bool get waitingForParent => status == SyncStatus.pendingParent;

  /// Office-created records (no device uuid) can't be updated through sync.
  bool get canEditFromDevice => serverId == null || uuidOnServer;
}

/// Bumped on every local write and after each sync so screens reload.
class DataChanges extends ChangeNotifier {
  int _version = 0;
  int get version => _version;

  void bump() {
    _version++;
    notifyListeners();
  }
}

/// Shared helpers for repositories of syncable tables.
abstract class SyncableRepository {
  SyncableRepository(this.db, this.changes);

  final Database db;
  final DataChanges changes;

  /// Inserts a new device record as pending; returns its client_uuid.
  Future<String> insertNew(String table, Map<String, Object?> values) async {
    final now = nowIso();
    final uuid = newUuid();
    await db.insert(table, {
      ...values,
      'client_uuid': uuid,
      'uuid_on_server': 1,
      'sync_status': SyncStatus.pending,
      'created_at': now,
      'updated_at': now,
    });
    changes.bump();
    return uuid;
  }

  /// Saves an edit and re-queues the record for upload.
  Future<void> updateLocal(String table, String uuid, Map<String, Object?> values) async {
    await db.update(
      table,
      {...values, 'sync_status': SyncStatus.pending, 'sync_error': null, 'updated_at': nowIso()},
      where: 'client_uuid = ?',
      whereArgs: [uuid],
    );
    changes.bump();
  }

  /// Re-queues a record the server rejected, without changes.
  Future<void> retry(String table, String uuid) => updateLocal(table, uuid, const {});
}
