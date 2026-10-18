import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/logger.dart';

/// Where access/refresh tokens and the signed-in officer's profile live.
abstract class TokenStore {
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<void> saveTokens({required String access, String? refresh});
  Future<void> clearTokens();

  Future<Map<String, dynamic>?> readUser();
  Future<void> saveUser(Map<String, dynamic> user);
  Future<void> clearUser();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              // The data protection keychain needs a signed build with the
              // keychain-access-groups entitlement; the legacy keychain does not.
              mOptions: MacOsOptions(useDataProtectionKeyChain: false),
            );

  final FlutterSecureStorage _storage;

  static const _access = 'auth_token';
  static const _refresh = 'refresh_token';
  static const _user = 'user_profile';

  @override
  Future<String?> readAccessToken() => _storage.read(key: _access);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refresh);

  @override
  Future<void> saveTokens({required String access, String? refresh}) async {
    await _storage.write(key: _access, value: access);
    if (refresh != null) await _storage.write(key: _refresh, value: refresh);
  }

  @override
  Future<void> clearTokens() async {
    await _delete(_access);
    await _delete(_refresh);
  }

  @override
  Future<Map<String, dynamic>?> readUser() async {
    final raw = await _storage.read(key: _user);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveUser(Map<String, dynamic> user) =>
      _storage.write(key: _user, value: jsonEncode(user));

  @override
  Future<void> clearUser() => _delete(_user);

  /// macOS debug builds are re-signed on every build, and the keychain then
  /// refuses to delete items an earlier build wrote (-25244). Signing out
  /// must still work, so such failures are logged, not thrown.
  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key: key);
    } on PlatformException catch (e) {
      Log.e('Could not delete $key from secure storage', error: e, tag: 'auth');
    }
  }
}

/// In-memory store for tests and scripts.
class MemoryTokenStore implements TokenStore {
  String? access;
  String? refresh;
  Map<String, dynamic>? user;

  @override
  Future<String?> readAccessToken() async => access;

  @override
  Future<String?> readRefreshToken() async => refresh;

  @override
  Future<void> saveTokens({required String access, String? refresh}) async {
    this.access = access;
    if (refresh != null) this.refresh = refresh;
  }

  @override
  Future<void> clearTokens() async {
    access = null;
    refresh = null;
  }

  @override
  Future<Map<String, dynamic>?> readUser() async => user;

  @override
  Future<void> saveUser(Map<String, dynamic> user) async => this.user = user;

  @override
  Future<void> clearUser() async => user = null;
}
