import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../db/syncable.dart';

class LocalPhoto {
  const LocalPhoto({
    required this.uuid,
    required this.path,
    required this.status,
    this.remoteUrl,
    this.error,
    this.latitude,
    this.longitude,
    this.takenAt,
  });

  factory LocalPhoto.fromRow(Map<String, Object?> r) => LocalPhoto(
        uuid: r['client_uuid'] as String,
        path: r['file_path'] as String,
        status: r['sync_status'] as String,
        remoteUrl: r['remote_url'] as String?,
        error: r['sync_error'] as String?,
        latitude: (r['latitude'] as num?)?.toDouble(),
        longitude: (r['longitude'] as num?)?.toDouble(),
        takenAt: DateTime.tryParse(r['taken_at'] as String? ?? ''),
      );

  final String uuid;
  final String path;
  final String status;
  final String? remoteUrl;
  final String? error;
  final double? latitude;
  final double? longitude;
  final DateTime? takenAt;

  bool get existsLocally => File(path).existsSync();
}

/// A photo the officer just took, not yet saved to the queue.
class CapturedPhoto {
  const CapturedPhoto({required this.path, this.latitude, this.longitude, this.caption});
  final String path;
  final double? latitude;
  final double? longitude;
  final String? caption;
}

/// Photo upload queue (`media` table).
class MediaRepository {
  MediaRepository(this.db, this.changes);

  final Database db;
  final DataChanges changes;

  Future<List<LocalPhoto>> forEntity(String entityUuid) async {
    final rows = await db.query(Tables.media,
        where: 'entity_uuid = ?', whereArgs: [entityUuid], orderBy: 'id');
    return rows.map(LocalPhoto.fromRow).toList();
  }

  Future<void> add(String entityType, String entityUuid, CapturedPhoto photo) async {
    final now = nowIso();
    await db.insert(Tables.media, {
      'client_uuid': newUuid(),
      'entity_type': entityType,
      'entity_uuid': entityUuid,
      'file_path': photo.path,
      'caption': photo.caption,
      'latitude': photo.latitude,
      'longitude': photo.longitude,
      'taken_at': now,
      'sync_status': SyncStatus.pending,
      'updated_at': now,
    });
    changes.bump();
  }

  /// Farmer profile photo: one queued photo per farmer; a retake replaces a
  /// photo that hasn't been uploaded yet.
  Future<void> setProfilePhoto(String farmerUuid, CapturedPhoto photo) async {
    await db.delete(Tables.media,
        where: 'entity_uuid = ? AND entity_type = ? AND sync_status != ?',
        whereArgs: [farmerUuid, 'farmer', SyncStatus.synced]);
    await add('farmer', farmerUuid, photo);
  }

  /// Removes a photo that hasn't been uploaded yet.
  Future<void> removePending(String photoUuid) async {
    await db.delete(Tables.media,
        where: 'client_uuid = ? AND sync_status != ?', whereArgs: [photoUuid, SyncStatus.synced]);
    changes.bump();
  }

  Future<int> pendingCount() async {
    final r = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM ${Tables.media} WHERE sync_status = ?', [SyncStatus.pending]);
    return (r.first['c'] as int?) ?? 0;
  }
}
