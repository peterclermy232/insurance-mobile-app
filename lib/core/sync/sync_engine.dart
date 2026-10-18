import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../db/meta_store.dart';
import '../network/api_exceptions.dart';
import '../utils/formatters.dart';
import '../utils/logger.dart';
import 'entity_mappers.dart';
import 'sync_transport.dart';

enum SyncPhase { preparing, contactingServer, applying, uploadingPhotos, done }

/// Outcome of one sync run, for the UI.
class SyncReport {
  SyncReport({this.error});

  /// Set when the run failed before the server response was applied. Local
  /// data is untouched in that case.
  final Object? error;

  bool get ok => error == null;

  DateTime? serverTime;
  int sent = 0;
  int saved = 0;
  int duplicates = 0;
  int locked = 0;
  int waitingForParent = 0;
  int rejected = 0;
  int downloaded = 0;
  int photosUploaded = 0;
  int photosWaiting = 0;
  int photosFailed = 0;
  Object? photoError;
  final List<String> notices = [];

  String get summary {
    if (!ok) return error is ApiException ? (error as ApiException).message : 'Sync failed.';
    final parts = <String>[];
    if (sent == 0 && downloaded == 0) parts.add('Everything is up to date');
    if (saved > 0) parts.add('$saved uploaded');
    if (downloaded > 0) parts.add('$downloaded downloaded');
    if (duplicates > 0) parts.add('$duplicates linked to existing farmers');
    if (rejected > 0) parts.add('$rejected need attention');
    if (waitingForParent > 0) parts.add('$waitingForParent waiting for a linked record');
    if (locked > 0) parts.add('$locked replaced by the office copy');
    if (photosUploaded > 0) parts.add('$photosUploaded photos uploaded');
    if (photoError != null) parts.add('photos will upload next time');
    return parts.join(', ');
  }
}

/// The single offline sync implementation.
///
/// 1. Collect rows whose sync_status is pending / pending_parent and send them
///    to POST /sync/ in one request (parents first, referenced by uuid until
///    they have a server id).
/// 2. Apply the response in ONE transaction: per-item results, `updates`,
///    `reference`, then persist `last_sync = server_time`. If anything fails,
///    nothing is applied and last_sync is unchanged; re-sending is safe since
///    the server upserts by client_uuid.
/// 3. Upload pending photos whose owning record now has a server id.
///
/// Concurrent calls join the run already in progress.
class SyncEngine {
  SyncEngine({required this.db, required this.transport});

  final Database db;
  final SyncTransport transport;

  Future<SyncReport>? _running;

  bool get isRunning => _running != null;

  Future<SyncReport> sync({bool fullDownload = false, void Function(SyncPhase phase)? onPhase}) {
    final running = _running;
    if (running != null) return running;
    final future = _run(fullDownload, onPhase ?? (_) {});
    _running = future;
    return future.whenComplete(() => _running = null);
  }

  Future<SyncReport> _run(bool fullDownload, void Function(SyncPhase) onPhase) async {
    onPhase(SyncPhase.preparing);
    final Map<String, dynamic> payload;
    final Map<String, Map<String, String>> sentVersions;
    final bool uuidIds;
    try {
      uuidIds = await _useUuidIds();
      final lastSync = await MetaStore.get(db, MetaKeys.lastSync);
      final forceFull = await MetaStore.get(db, MetaKeys.forceFullDownload) == '1';
      final built = await buildPayload(lastSync: (fullDownload || forceFull) ? null : lastSync);
      payload = built.$1;
      sentVersions = built.$2;
    } catch (e, st) {
      Log.e('Could not prepare sync', error: e, stackTrace: st, tag: 'sync');
      return SyncReport(error: e);
    }

    onPhase(SyncPhase.contactingServer);
    final Map<String, dynamic> response;
    try {
      response = await transport.sync(payload, uuidIds: uuidIds);
    } catch (e) {
      Log.d('Sync request failed: $e', tag: 'sync');
      if (e is ServerException && (e.statusCode ?? 0) >= 500) {
        Log.d('Server response: ${e.data}', tag: 'sync');
        Log.d('Request payload: ${jsonEncode(payload)}', tag: 'sync');
      }
      return SyncReport(error: e);
    }

    onPhase(SyncPhase.applying);
    final report = SyncReport();
    report.sent = sentVersions.values.fold(0, (sum, m) => sum + m.length);
    try {
      await db.transaction((txn) => applyResponse(txn, response, sentVersions, report));
    } catch (e, st) {
      Log.e('Could not apply sync response', error: e, stackTrace: st, tag: 'sync');
      return SyncReport(error: const ServerException('Unexpected response from the server.'));
    }

    onPhase(SyncPhase.uploadingPhotos);
    await uploadPendingPhotos(report, uuidIds: uuidIds);
    onPhase(SyncPhase.done);
    return report;
  }

  /// Whether to ask the server for public UUIDs.
  ///
  /// Installs from before public ids hold numeric server ids, and mixing them
  /// with UUIDs would duplicate office records. They keep syncing with numbers
  /// until nothing is waiting to upload, then drop their downloaded copy (all of
  /// it is on the server) and download everything again with UUIDs. Records
  /// captured on the device keep their client_uuid, so photos stay linked.
  Future<bool> _useUuidIds() async {
    final format = await MetaStore.get(db, MetaKeys.idFormat);
    if (format == 'uuid') return true;
    if (format == null && !await _hasServerIds()) {
      await MetaStore.set(db, MetaKeys.idFormat, 'uuid');
      return true;
    }
    if (await _unsyncedCount() > 0) return false;
    await db.transaction((txn) async {
      for (final table in [...Tables.entities, Tables.reference]) {
        await txn.delete(table);
      }
      await MetaStore.set(txn, MetaKeys.forceFullDownload, '1');
      await MetaStore.set(txn, MetaKeys.idFormat, 'uuid');
    });
    Log.d('Switched to public UUIDs; downloading everything again', tag: 'sync');
    return true;
  }

  Future<bool> _hasServerIds() async {
    for (final table in Tables.entities) {
      final rows = await db.query(table, columns: ['id'], where: 'server_id IS NOT NULL', limit: 1);
      if (rows.isNotEmpty) return true;
    }
    return false;
  }

  Future<int> _unsyncedCount() async {
    var total = 0;
    final marks = List.filled(SyncStatus.unsynced.length, '?').join(',');
    for (final table in Tables.entities) {
      final r = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM $table WHERE sync_status IN ($marks)', SyncStatus.unsynced);
      total += (r.first['c'] as int?) ?? 0;
    }
    final photos = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM ${Tables.media} WHERE sync_status = ?', [SyncStatus.pending]);
    return total + ((photos.first['c'] as int?) ?? 0);
  }

  // ------------------------------------------------------------ payload

  /// Returns the request body and, per entity, client_uuid -> updated_at of
  /// every row sent (to detect edits made while the request was in flight).
  Future<(Map<String, dynamic>, Map<String, Map<String, String>>)> buildPayload(
      {String? lastSync}) async {
    final changes = <String, List<Map<String, dynamic>>>{};
    final versions = <String, Map<String, String>>{};
    for (final table in Tables.entities) {
      final rows = await db.query(table,
          where: 'sync_status IN (?, ?)', whereArgs: SyncStatus.pushable, orderBy: 'id');
      final items = <Map<String, dynamic>>[];
      final sent = <String, String>{};
      for (final row in rows) {
        // Records downloaded from the office without a device uuid can't be
        // updated through /sync/ (the server upserts by client_uuid only).
        if (row['server_id'] != null && row['uuid_on_server'] == 0) continue;
        items.add(await EntityMappers.toPayload(db, table, row));
        sent[row['client_uuid'] as String] = row['updated_at'] as String;
      }
      if (items.isNotEmpty) changes[table] = items;
      versions[table] = sent;
    }
    return (
      <String, dynamic>{'last_sync': lastSync, 'include_reference': true, 'changes': changes},
      versions,
    );
  }

  // ------------------------------------------------------------ response

  Future<void> applyResponse(Transaction txn, Map<String, dynamic> response,
      Map<String, Map<String, String>> sentVersions, SyncReport report) async {
    final serverTime = response['server_time'] as String?;
    if (serverTime == null) throw const FormatException('server_time missing');

    final results = (response['results'] as Map?) ?? const {};
    final updates = (response['updates'] as Map?) ?? const {};
    final unresolved = <String, Set<String>>{}; // table -> server ids we need the server copy of

    for (final table in Tables.entities) {
      final items = (results[table] as List?) ?? const [];
      for (final item in items.whereType<Map>()) {
        await _applyResult(txn, table, item.cast<String, dynamic>(), sentVersions[table] ?? const {},
            report, unresolved);
      }
    }

    for (final table in Tables.entities) {
      final records = (updates[table] as List?) ?? const [];
      final idKey = EntityMappers.serverIdKey[table]!;
      for (final record in records.whereType<Map>()) {
        final r = record.cast<String, dynamic>();
        unresolved[table]?.remove(toServerId(r[idKey]));
        if (await _applyUpdate(txn, table, r)) report.downloaded++;
      }
    }
    await EntityMappers.relinkParents(txn);

    final reference = response['reference'];
    if (reference is Map) await _applyReference(txn, reference.cast<String, dynamic>());

    final needsRefresh = unresolved.values.any((ids) => ids.isNotEmpty);
    await MetaStore.set(txn, MetaKeys.forceFullDownload, needsRefresh ? '1' : null);
    await MetaStore.set(txn, MetaKeys.lastSync, serverTime);
    report.serverTime = DateTime.tryParse(serverTime);
  }

  Future<void> _applyResult(Transaction txn, String table, Map<String, dynamic> item,
      Map<String, String> sent, SyncReport report, Map<String, Set<String>> unresolved) async {
    final uuid = item['client_uuid'] as String?;
    if (uuid == null) return;
    final rows = await txn.query(table, where: 'client_uuid = ?', whereArgs: [uuid], limit: 1);
    if (rows.isEmpty) return;
    final row = rows.first;
    // The officer edited the record while this sync was running: keep the
    // newer local edit pending so it goes up next time.
    final editedSince = sent[uuid] != null && sent[uuid] != row['updated_at'];
    final serverId = toServerId(item['server_id']);
    const where = 'client_uuid = ?';

    switch (item['status']) {
      case 'created':
      case 'updated':
        report.saved++;
        final record = item['record'];
        final values = <String, Object?>{
          if (serverId != null) 'server_id': serverId,
          'uuid_on_server': 1,
        };
        if (editedSince) {
          values['sync_status'] = SyncStatus.pending;
        } else {
          if (record is Map) {
            values.addAll(await EntityMappers.fromServer(txn, table, record.cast<String, dynamic>()));
          }
          values['sync_status'] = SyncStatus.synced;
          values['sync_error'] = null;
        }
        await txn.update(table, values, where: where, whereArgs: [uuid]);

      case 'duplicate':
        report.duplicates++;
        final name = table == Tables.farmers
            ? '${row['first_name']} ${row['last_name']} (ID ${row['id_number']})'
            : 'A record';
        final notice = 'Already registered at the office. This farmer was linked to the '
            'existing record #$serverId instead of creating a new one.';
        report.notices.add('$name is already registered and has been linked to the existing farmer.');
        await txn.update(
            table,
            {
              'server_id': serverId,
              'uuid_on_server': 0,
              'sync_status': SyncStatus.synced,
              'sync_error': null,
              if (table == Tables.farmers) 'notice': notice,
            },
            where: where,
            whereArgs: [uuid]);
        if (serverId != null) (unresolved[table] ??= {}).add(serverId);

      case 'locked':
        report.locked++;
        await txn.update(
            table,
            {
              if (serverId != null) 'server_id': serverId,
              'uuid_on_server': 1,
              'sync_status': SyncStatus.synced,
              'sync_error': null,
            },
            where: where,
            whereArgs: [uuid]);
        report.notices.add('A ${EntityMappers.singular[table]} was already processed by the office; '
            'your changes were replaced by the office copy.');
        if (serverId != null) (unresolved[table] ??= {}).add(serverId);

      case 'pending_parent':
        report.waitingForParent++;
        await txn.update(
            table,
            {
              'sync_status': SyncStatus.pendingParent,
              'sync_error': formatServerErrors(item['errors']),
            },
            where: where,
            whereArgs: [uuid]);

      default: // 'error' and anything unknown
        report.rejected++;
        await txn.update(
            table,
            {
              'sync_status': editedSince ? SyncStatus.pending : SyncStatus.error,
              'sync_error': formatServerErrors(item['errors']),
            },
            where: where,
            whereArgs: [uuid]);
    }
  }

  /// Upserts a server record. Returns true when local data changed.
  Future<bool> _applyUpdate(Transaction txn, String table, Map<String, dynamic> record) async {
    final serverId = toServerId(record[EntityMappers.serverIdKey[table]]);
    if (serverId == null) return false;
    final remoteUuid = record['client_uuid'] as String?;

    Map<String, Object?>? row;
    if (remoteUuid != null) {
      final rows = await txn.query(table, where: 'client_uuid = ?', whereArgs: [remoteUuid], limit: 1);
      if (rows.isNotEmpty) row = rows.first;
    }
    if (row == null) {
      final rows = await txn.query(table, where: 'server_id = ?', whereArgs: [serverId], limit: 1);
      if (rows.isNotEmpty) row = rows.first;
    }

    final values = await EntityMappers.fromServer(txn, table, record);
    values['server_id'] = serverId;

    if (row == null) {
      final now = nowIso();
      await txn.insert(table, {
        ...values,
        'client_uuid': remoteUuid ?? newUuid(),
        'uuid_on_server': remoteUuid != null ? 1 : 0,
        'sync_status': SyncStatus.synced,
        'created_at': now,
        'updated_at': now,
      });
      return true;
    }

    final localUuid = row['client_uuid'] as String;
    if (SyncStatus.unsynced.contains(row['sync_status'])) {
      // Never overwrite local edits that haven't reached the server.
      if (row['server_id'] == null) {
        await txn.update(table, {'server_id': serverId},
            where: 'client_uuid = ?', whereArgs: [localUuid]);
      }
      return false;
    }

    if (remoteUuid != null && remoteUuid != localUuid) {
      await EntityMappers.rekey(txn, table, localUuid, remoteUuid);
      values['uuid_on_server'] = 1;
    }
    // Keep local-only fields; drop parent links the lookup couldn't resolve.
    values.removeWhere((key, value) => value == null && key.endsWith('_uuid'));
    await txn.update(table, values, where: 'client_uuid = ?', whereArgs: [remoteUuid ?? localUuid]);
    return true;
  }

  Future<void> _applyReference(Transaction txn, Map<String, dynamic> reference) async {
    final units = reference['administrative_units'];
    if (units is List) await _applyAdminUnits(txn, units);
    for (final entry in reference.entries) {
      final idKey = EntityMappers.referenceIdKey[entry.key];
      final items = entry.value;
      if (idKey == null || items is! List) continue;
      await txn.delete(Tables.reference, where: 'kind = ?', whereArgs: [entry.key]);
      for (final item in items.whereType<Map>()) {
        final id = toServerId(item[idKey]);
        if (id == null) continue;
        await txn.insert(Tables.reference, {'kind': entry.key, 'server_id': id, 'data': jsonEncode(item)},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  }

  /// Present only on a full download or after the office changed the tree;
  /// when present it replaces the local copy.
  Future<void> _applyAdminUnits(Transaction txn, List units) async {
    await txn.delete(Tables.adminUnits);
    final batch = txn.batch();
    for (final u in units.whereType<Map>()) {
      final id = toInt(u['unit_id']);
      if (id == null) continue;
      batch.insert(Tables.adminUnits, {
        'unit_id': id,
        'parent_id': toInt(u['parent']),
        'level': u['level']?.toString() ?? '',
        'name': u['name']?.toString() ?? '',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // ------------------------------------------------------------ photos

  static const _ownerTables = {
    'farmer': Tables.farmers,
    'claim': Tables.claims,
    'inspection': Tables.inspections,
  };

  Future<void> uploadPendingPhotos(SyncReport report, {bool uuidIds = false}) async {
    final pending = await db.query(Tables.media,
        where: 'sync_status = ?', whereArgs: [SyncStatus.pending], orderBy: 'id');
    for (var i = 0; i < pending.length; i++) {
      final photo = pending[i];
      final id = photo['id'];
      final ownerTable = _ownerTables[photo['entity_type']];
      final owners = ownerTable == null
          ? const <Map<String, Object?>>[]
          : await db.query(ownerTable,
              columns: ['server_id', 'uuid_on_server', 'client_uuid'],
              where: 'client_uuid = ?',
              whereArgs: [photo['entity_uuid']],
              limit: 1);
      final serverId = owners.isEmpty ? null : owners.first['server_id'];
      if (serverId == null) {
        report.photosWaiting++; // owning record not on the server yet
        continue;
      }
      final path = photo['file_path'] as String;
      if (!File(path).existsSync()) {
        report.photosFailed++;
        await _markPhoto(id, SyncStatus.error, error: 'The photo file is no longer on this device.');
        continue;
      }

      final (int, Map<String, dynamic>) answer;
      try {
        answer = await transport.upload({
          'entity_type': photo['entity_type'],
          'entity_id': serverId,
          'client_uuid': photo['client_uuid'],
          'caption': photo['caption'],
          'latitude': (photo['latitude'] as num?)?.toStringAsFixed(6),
          'longitude': (photo['longitude'] as num?)?.toStringAsFixed(6),
        }, path, uuidIds: uuidIds);
      } catch (e) {
        // Network/auth problem: stop here, the rest stays queued.
        report.photoError = e;
        report.photosWaiting += pending.length - i;
        Log.d('Photo upload stopped: $e', tag: 'sync');
        break;
      }

      final (status, body) = answer;
      if (status == 200 || status == 201) {
        report.photosUploaded++;
        final url = body['file_url'] as String?;
        await _markPhoto(id, SyncStatus.synced, remoteUrl: url);
        if (photo['entity_type'] == 'farmer' && url != null) {
          await db.update(Tables.farmers, {'photo_url': url},
              where: 'client_uuid = ?', whereArgs: [photo['entity_uuid']]);
        }
      } else if (status == 409) {
        report.photosWaiting++;
        await _markPhoto(id, SyncStatus.pending, error: 'Waiting for the record to sync.');
      } else {
        report.photosFailed++;
        await _markPhoto(id, SyncStatus.error,
            error: (body['error'] as String?) ?? 'Upload rejected ($status).');
      }
    }
  }

  Future<void> _markPhoto(Object? id, String status, {String? error, String? remoteUrl}) =>
      db.rawUpdate(
        'UPDATE ${Tables.media} SET sync_status = ?, sync_error = ?, '
        'remote_url = COALESCE(?, remote_url), attempts = attempts + 1, updated_at = ? WHERE id = ?',
        [status, error, remoteUrl, nowIso(), id],
      );
}

/// `{field: [messages]}` -> "Field: message; ..."
String formatServerErrors(Object? errors) {
  if (errors == null) return 'The server rejected this record.';
  if (errors is String) return errors;
  if (errors is List) return errors.map(formatServerErrors).join('; ');
  if (errors is Map) {
    return errors.entries.map((e) {
      final messages = e.value is List ? (e.value as List).join(' ') : '${e.value}';
      if (e.key == 'non_field_errors') return messages;
      return '${Fmt.enumLabel(e.key.toString())}: $messages';
    }).join('; ');
  }
  return errors.toString();
}
