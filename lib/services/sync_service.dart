import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/database/app_database.dart';
import '../core/network/api_client.dart';


/// SyncService handles bidirectional synchronization between local SQLite and backend
///
/// Features:
/// - Upload pending local changes to server
/// - Download server updates to local database
/// - Conflict resolution (server wins by default)
/// - Timestamp-based sync tracking
class SyncService {
  final ApiClient _api;
  final AppDatabase _db;
  final SharedPreferences _prefs;

  SyncService(this._api, this._db, this._prefs);

  /// Main sync method - synchronizes all entities
  Future<SyncResult> syncAll() async {
    try {
      print('🔄 Starting sync...');

      // Check if we're online
      if (!await _api.isOnline()) {
        print('📵 No internet connection');
        return SyncResult(
          success: false,
          error: 'No internet connection',
        );
      }

      // 1. Get last sync timestamp
      final lastSync = _prefs.getString('last_sync_timestamp');
      print('📅 Last sync: ${lastSync ?? "Never"}');

      // 2. Gather pending uploads
      final pendingData = await _gatherPendingData();
      final totalPending = _countPendingItems(pendingData);
      print('📤 Pending data: $totalPending items');

      // 3. Call sync endpoint
      final response = await _api.post('/sync/', data: {
        'last_sync_timestamp': lastSync,
        'pending_data': pendingData,
      });

      print(' Sync response received');

      // 4. Process upload results
      final uploadResults = response['upload_results'] as Map<String, dynamic>?;
      if (uploadResults != null) {
        await _markUploadsComplete(uploadResults);
      }

      // 5. Apply server updates
      final serverUpdates = response['server_updates'] as Map<String, dynamic>?;
      if (serverUpdates != null) {
        await _applyServerUpdates(serverUpdates);
      }

      // 6. Handle conflicts
      final conflicts = response['conflicts'] as List? ?? [];
      if (conflicts.isNotEmpty) {
        await _resolveConflicts(conflicts);
      }

      // 7. Save new sync timestamp
      final syncTimestamp = response['sync_timestamp'] ??
          response['timestamp'] ??
          DateTime.now().toIso8601String();
      await _prefs.setString('last_sync_timestamp', syncTimestamp);

      print(' Sync completed successfully');

      return SyncResult(
        success: true,
        uploaded: uploadResults != null ? _countUploaded(uploadResults) : 0,
        downloaded: serverUpdates != null ? _countDownloaded(serverUpdates) : 0,
        conflicts: conflicts.length,
      );
    } catch (e) {
      print(' Sync failed: $e');
      return SyncResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Gather all pending data from local database
  Future<Map<String, dynamic>> _gatherPendingData() async {
    final db = await _db.database;

    return {
      'farmers': await db.query(
        'farmers',
        where: 'sync_status = ?',
        whereArgs: ['pending'],
      ),
      'farms': await db.query(
        'farms',
        where: 'sync_status = ? OR synced = ?',
        whereArgs: ['pending', 0],
      ),
      'quotations': await db.query(
        'quotations',
        where: 'sync_status = ? OR synced = ?',
        whereArgs: ['pending', 0],
      ),
      'claims': await db.query(
        'claims',
        where: 'sync_status = ?',
        whereArgs: ['pending'],
      ),
    };
  }

  /// Count total pending items
  int _countPendingItems(Map<String, dynamic> pendingData) {
    int total = 0;
    for (final items in pendingData.values) {
      if (items is List) {
        total += items.length;
      }
    }
    return total;
  }

  /// Mark successfully uploaded items as synced
  Future<void> _markUploadsComplete(Map<String, dynamic> results) async {
    final db = await _db.database;

    // Mark farmers as synced
    final farmersCreated = results['farmers']?['created'] as int? ?? 0;
    final farmersUpdated = results['farmers']?['updated'] as int? ?? 0;
    if (farmersCreated > 0 || farmersUpdated > 0) {
      await db.update(
        'farmers',
        {'sync_status': 'synced', 'synced': 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'sync_status = ?',
        whereArgs: ['pending'],
      );
      print(' Marked $farmersCreated farmers as synced');
    }

    // Mark farms as synced
    final farmsCreated = results['farms']?['created'] as int? ?? 0;
    final farmsUpdated = results['farms']?['updated'] as int? ?? 0;
    if (farmsCreated > 0 || farmsUpdated > 0) {
      await db.update(
        'farms',
        {'sync_status': 'synced', 'synced': 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'sync_status = ? OR synced = ?',
        whereArgs: ['pending', 0],
      );
      print(' Marked $farmsCreated farms as synced');
    }

    // Mark quotations as synced
    final quotsCreated = results['quotations']?['created'] as int? ?? 0;
    final quotsUpdated = results['quotations']?['updated'] as int? ?? 0;
    if (quotsCreated > 0 || quotsUpdated > 0) {
      await db.update(
        'quotations',
        {'sync_status': 'synced', 'synced': 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'sync_status = ? OR synced = ?',
        whereArgs: ['pending', 0],
      );
      print(' Marked $quotsCreated quotations as synced');
    }

    // Mark claims as synced
    final claimsCreated = results['claims']?['created'] as int? ?? 0;
    final claimsUpdated = results['claims']?['updated'] as int? ?? 0;
    if (claimsCreated > 0 || claimsUpdated > 0) {
      await db.update(
        'claims',
        {'sync_status': 'synced', 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'sync_status = ?',
        whereArgs: ['pending'],
      );
      print(' Marked $claimsCreated claims as synced');
    }
  }

  /// Apply updates received from server
  Future<void> _applyServerUpdates(Map<String, dynamic> updates) async {
    final db = await _db.database;

    // Insert/update farmers from server
    final farmers = updates['farmers'] as List? ?? [];
    for (final farmer in farmers) {
      await db.insert(
        'farmers',
        {
          ...farmer as Map<String, dynamic>,
          'sync_status': 'synced',
          'synced': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    if (farmers.isNotEmpty) {
      print('⬇️ Downloaded ${farmers.length} farmers');
    }

    // Insert/update farms from server
    final farms = updates['farms'] as List? ?? [];
    for (final farm in farms) {
      await db.insert(
        'farms',
        {
          ...farm as Map<String, dynamic>,
          'sync_status': 'synced',
          'synced': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    if (farms.isNotEmpty) {
      print('⬇️ Downloaded ${farms.length} farms');
    }

    // Insert/update quotations from server
    final quotations = updates['quotations'] as List? ?? [];
    for (final quot in quotations) {
      await db.insert(
        'quotations',
        {
          ...quot as Map<String, dynamic>,
          'sync_status': 'synced',
          'synced': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    if (quotations.isNotEmpty) {
      print('⬇️ Downloaded ${quotations.length} quotations');
    }

    // Insert/update claims from server
    final claims = updates['claims'] as List? ?? [];
    for (final claim in claims) {
      await db.insert(
        'claims',
        {
          ...claim as Map<String, dynamic>,
          'sync_status': 'synced',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    if (claims.isNotEmpty) {
      print('⬇️ Downloaded ${claims.length} claims');
    }
  }

  /// Resolve conflicts (server wins by default)
  Future<void> _resolveConflicts(List conflicts) async {
    final db = await _db.database;

    for (final conflict in conflicts) {
      print('⚠️ Conflict detected: ${conflict['type']} #${conflict['id']}');
      print('   Resolution: server_wins (default)');

      // Apply server version
      final serverVersion = conflict['server_version'] as Map<String, dynamic>;
      final tableName = '${conflict['type']}s';

      await db.update(
        tableName,
        {
          ...serverVersion,
          'sync_status': 'synced',
          'synced': 1,
        },
        where: 'id = ?',
        whereArgs: [conflict['id']],
      );
    }
  }

  /// Count uploaded items
  int _countUploaded(Map<String, dynamic> results) {
    int total = 0;
    for (final entity in results.values) {
      if (entity is Map) {
        total += (entity['created'] as int? ?? 0);
        total += (entity['updated'] as int? ?? 0);
      }
    }
    return total;
  }

  /// Count downloaded items
  int _countDownloaded(Map<String, dynamic> updates) {
    int total = 0;
    for (final items in updates.values) {
      if (items is List) {
        total += items.length;
      }
    }
    return total;
  }

  /// Sync specific entity type
  Future<SyncResult> syncEntity(String entityType) async {
    try {
      print('🔄 Syncing $entityType...');

      final db = await _db.database;
      final pendingItems = await db.query(
        entityType,
        where: 'sync_status = ?',
        whereArgs: ['pending'],
      );

      if (pendingItems.isEmpty) {
        print(' No pending $entityType to sync');
        return SyncResult(success: true);
      }

      // Upload to server
      final response = await _api.post('/sync/', data: {
        'entity_type': entityType,
        'items': pendingItems,
      });

      // Mark as synced
      for (var item in pendingItems) {
        await db.update(
          entityType,
          {'sync_status': 'synced'},
          where: 'id = ?',
          whereArgs: [item['id']],
        );
      }

      print(' Synced ${pendingItems.length} $entityType');
      return SyncResult(success: true, uploaded: pendingItems.length);
    } catch (e) {
      print(' Failed to sync $entityType: $e');
      return SyncResult(success: false, error: e.toString());
    }
  }

  /// Get last sync timestamp
  Future<String?> getLastSyncTimestamp() async {
    return _prefs.getString('last_sync_timestamp');
  }

  /// Clear sync timestamp (force full sync on next attempt)
  Future<void> clearSyncTimestamp() async {
    await _prefs.remove('last_sync_timestamp');
  }
}

/// Result of a sync operation
class SyncResult {
  final bool success;
  final int uploaded;
  final int downloaded;
  final int conflicts;
  final String? error;

  SyncResult({
    required this.success,
    this.uploaded = 0,
    this.downloaded = 0,
    this.conflicts = 0,
    this.error,
  });

  @override
  String toString() {
    if (!success) {
      return 'SyncResult(failed: $error)';
    }
    return 'SyncResult(uploaded: $uploaded, downloaded: $downloaded, conflicts: $conflicts)';
  }
}