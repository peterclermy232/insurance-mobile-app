import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../db/meta_store.dart';
import '../network/api_client.dart';
import '../network/api_exceptions.dart';
import 'token_store.dart';
import 'user_session.dart';

enum AuthStatus { loading, signedOut, signedIn }

class LoginRefused implements Exception {
  const LoginRefused(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Sign-in state.
///
/// Offline first: once an officer has signed in on this device, the app opens
/// from the stored profile even if the tokens have expired. Only syncing needs
/// valid tokens; when refresh fails [needsReauth] turns on and the UI shows a
/// non-blocking "Sign in again to sync" banner.
class AuthController extends ChangeNotifier {
  AuthController({required this.api, required this.tokens, required this.db});

  final ApiClient api;
  final TokenStore tokens;
  final Database db;

  AuthStatus _status = AuthStatus.loading;
  UserSession? _session;
  bool _needsReauth = false;

  AuthStatus get status => _status;
  UserSession? get session => _session;
  bool get needsReauth => _needsReauth;
  bool get isSignedIn => _status == AuthStatus.signedIn;

  Future<void> init() async {
    final user = await tokens.readUser();
    final session = user == null ? null : UserSession.fromJson(user);
    if (session != null && session.isFieldOfficer) {
      _session = session;
      _status = AuthStatus.signedIn;
      _needsReauth = await tokens.readRefreshToken() == null;
    } else {
      _status = AuthStatus.signedOut;
    }
    notifyListeners();
  }

  /// Throws [LoginRefused] or [ApiException] with a message for the officer.
  Future<void> login(String username, String password) async {
    final response = await api.login(username.trim(), password);
    final token = response['token'] as String?;
    final user = response['user'];
    if (token == null || user is! Map) {
      throw const ServerException('Unexpected answer from the server. Try again.');
    }
    final session = UserSession.fromJson(user.cast<String, dynamic>());
    if (!session.isFieldOfficer) {
      throw const LoginRefused(
          'This app is for field officers (agents, assessors and managers). '
          'Please use the web portal with this account.');
    }
    await _claimDevice(session);

    await tokens.saveTokens(access: token, refresh: response['refresh'] as String?);
    await tokens.saveUser(user.cast<String, dynamic>());
    _session = session;
    _needsReauth = false;
    _status = AuthStatus.signedIn;
    notifyListeners();
  }

  /// Local data belongs to the officer who captured it. Another officer may
  /// only take over the device once everything has been synced.
  Future<void> _claimDevice(UserSession session) async {
    final owner = await MetaStore.get(db, MetaKeys.ownerUserId);
    if (owner == null || owner == '${session.userId}') {
      await MetaStore.set(db, MetaKeys.ownerUserId, '${session.userId}');
      await MetaStore.set(db, MetaKeys.ownerName, session.name);
      return;
    }
    if (await unsyncedCount() > 0) {
      final ownerName = await MetaStore.get(db, MetaKeys.ownerName) ?? 'another officer';
      throw LoginRefused('This device has records captured by $ownerName that are not synced yet. '
          'They must sign in and sync before someone else can use this device.');
    }
    await db.transaction((txn) async {
      for (final table in [...Tables.entities, Tables.media, Tables.reference, Tables.adminUnits, Tables.meta]) {
        await txn.delete(table);
      }
      await MetaStore.set(txn, MetaKeys.ownerUserId, '${session.userId}');
      await MetaStore.set(txn, MetaKeys.ownerName, session.name);
    });
  }

  Future<int> unsyncedCount() async {
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

  void markReauthRequired() {
    if (_needsReauth) return;
    _needsReauth = true;
    notifyListeners();
  }

  /// Signs out. Local records stay on the device and sync after the next sign-in.
  Future<void> logout() async {
    await tokens.clearTokens();
    await tokens.clearUser();
    _session = null;
    _needsReauth = false;
    _status = AuthStatus.signedOut;
    notifyListeners();
  }
}
