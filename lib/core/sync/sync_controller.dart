import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../auth/auth_controller.dart';
import '../config/app_config.dart';
import '../db/app_database.dart';
import '../db/meta_store.dart';
import '../db/syncable.dart';
import '../network/api_exceptions.dart';
import '../network/connectivity_service.dart';
import 'sync_engine.dart';

/// UI-facing sync state: triggers (manual, connectivity restored, after
/// login), progress text, last sync time and pending counts.
class SyncController extends ChangeNotifier {
  SyncController({
    required this.engine,
    required this.db,
    required this.auth,
    required this.connectivity,
    required this.changes,
  });

  final SyncEngine engine;
  final Database db;
  final AuthController auth;
  final ConnectivityService connectivity;
  final DataChanges changes;

  StreamSubscription<void>? _restoredSub;
  Timer? _slowTimer;
  bool _disposed = false;

  bool _syncing = false;
  String? _progress;
  DateTime? _lastSync;
  int _pending = 0;
  int _attention = 0;
  int _pendingPhotos = 0;
  SyncReport? _lastReport;

  bool get isSyncing => _syncing;
  String? get progress => _progress;
  DateTime? get lastSync => _lastSync;

  /// Records waiting to upload (pending + waiting for a linked record).
  int get pendingCount => _pending;

  /// Records the server rejected; the officer must fix them.
  int get attentionCount => _attention;
  int get pendingPhotos => _pendingPhotos;
  SyncReport? get lastReport => _lastReport;

  void start() {
    _restoredSub = connectivity.onRestored.listen((_) {
      if (auth.isSignedIn && !auth.needsReauth) syncNow(trigger: 'connectivity');
    });
    changes.addListener(_onLocalChange);
    refreshCounts();
  }

  void _onLocalChange() {
    if (!_syncing) refreshCounts();
  }

  Future<void> refreshCounts() async {
    final last = await MetaStore.get(db, MetaKeys.lastSync);
    _lastSync = last == null ? null : DateTime.tryParse(last);
    var pending = 0;
    var attention = 0;
    for (final table in Tables.entities) {
      final rows = await db.rawQuery(
          'SELECT sync_status, COUNT(*) AS c FROM $table WHERE sync_status != ? GROUP BY sync_status',
          [SyncStatus.synced]);
      for (final r in rows) {
        final count = (r['c'] as int?) ?? 0;
        if (r['sync_status'] == SyncStatus.error) {
          attention += count;
        } else {
          pending += count;
        }
      }
    }
    final photos = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM ${Tables.media} WHERE sync_status = ?', [SyncStatus.pending]);
    _pending = pending;
    _attention = attention;
    _pendingPhotos = (photos.first['c'] as int?) ?? 0;
    _notify();
  }

  /// Runs a sync. Concurrent calls join the run in progress. Returns null
  /// when sync isn't possible (signed out).
  Future<SyncReport?> syncNow({bool fullDownload = false, String trigger = 'manual'}) async {
    if (!auth.isSignedIn) return null;
    _syncing = true;
    _progress = 'Preparing records...';
    _notify();

    final report = await engine.sync(fullDownload: fullDownload, onPhase: _onPhase);

    _slowTimer?.cancel();
    _syncing = false;
    _progress = null;
    _lastReport = report;
    final error = report.error;
    if (error is AuthRequiredException) auth.markReauthRequired();
    await refreshCounts();
    changes.bump();
    return report;
  }

  void _onPhase(SyncPhase phase) {
    _slowTimer?.cancel();
    switch (phase) {
      case SyncPhase.preparing:
        _progress = 'Preparing records...';
      case SyncPhase.contactingServer:
        _progress = 'Contacting server...';
        _slowTimer = Timer(AppConfig.slowServerHint, () {
          _progress = 'Waking up the server. This can take up to a minute...';
          _notify();
        });
      case SyncPhase.applying:
        _progress = 'Saving downloaded records...';
      case SyncPhase.uploadingPhotos:
        _progress = 'Uploading photos...';
      case SyncPhase.done:
        _progress = 'Finishing...';
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _restoredSub?.cancel();
    _slowTimer?.cancel();
    changes.removeListener(_onLocalChange);
    super.dispose();
  }
}
