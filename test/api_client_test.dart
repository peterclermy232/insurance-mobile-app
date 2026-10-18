import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insurance_mobile/core/auth/auth_controller.dart';
import 'package:insurance_mobile/core/auth/token_store.dart';
import 'package:insurance_mobile/core/db/app_database.dart';
import 'package:insurance_mobile/core/network/api_client.dart';
import 'package:insurance_mobile/core/network/api_exceptions.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fakes.dart';

/// Fake HTTP layer for Dio: answers each request with [handler].
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final (int, Object?) Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final (status, body) = handler(options);
    if (status == 0) {
      throw DioException.connectionError(requestOptions: options, reason: 'offline');
    }
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late MemoryTokenStore tokens;

  ApiClient client(FakeAdapter adapter) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'))..httpClientAdapter = adapter;
    return ApiClient(tokens: tokens, dio: dio);
  }

  setUp(() {
    tokens = MemoryTokenStore()
      ..access = 'old'
      ..refresh = 'r1';
  });

  test('refreshes on 401 and retries once with the new token', () async {
    final adapter = FakeAdapter((o) {
      if (o.path == '/auth/token/refresh/') return (200, {'token': 'new'});
      final auth = o.headers['Authorization'];
      return auth == 'Bearer new' ? (200, {'server_time': 't'}) : (401, {'detail': 'expired'});
    });
    final result = await client(adapter).postSync({'changes': {}});
    expect(result['server_time'], 't');
    expect(tokens.access, 'new');
    expect(adapter.requests.map((r) => r.path), ['/sync/', '/auth/token/refresh/', '/sync/']);
  });

  test('failed refresh raises AuthRequiredException and does not loop', () async {
    final adapter = FakeAdapter((o) {
      if (o.path == '/auth/token/refresh/') return (401, {'error': 'Invalid or expired refresh token'});
      return (401, {'detail': 'expired'});
    });
    await expectLater(client(adapter).postSync({}), throwsA(isA<AuthRequiredException>()));
    expect(adapter.requests, hasLength(2));
  });

  test('second 401 after refresh is reported as auth required', () async {
    final adapter = FakeAdapter((o) =>
        o.path == '/auth/token/refresh/' ? (200, {'token': 'new'}) : (401, {'detail': 'nope'}));
    await expectLater(client(adapter).postSync({}), throwsA(isA<AuthRequiredException>()));
    expect(adapter.requests, hasLength(3));
  });

  test('offline maps to NetworkException; 403 to ForbiddenException', () async {
    await expectLater(client(FakeAdapter((o) => (0, null))).postSync({}), throwsA(isA<NetworkException>()));
    await expectLater(
        client(FakeAdapter((o) => (403, {'detail': 'Your role is not allowed to sync field data.'}))).postSync({}),
        throwsA(isA<ForbiddenException>()));
  });

  group('AuthController', () {
    late Database db;
    setUp(() async => db = await openTestDb());
    tearDown(() async => db.close());

    Map<String, dynamic> loginBody(String role, {int id = 7}) => {
          'token': 'a',
          'refresh': 'r',
          'user': {'user_id': id, 'user_name': 'Jane', 'user_email': 'j@x', 'user_role': role, 'organisation': 1},
        };

    test('refuses non field roles with a friendly message', () async {
      final api = client(FakeAdapter((o) => (200, loginBody('CUSTOMER'))));
      final auth = AuthController(api: api, tokens: MemoryTokenStore(), db: db);
      await expectLater(
        auth.login('c@x', 'pw'),
        throwsA(isA<LoginRefused>().having((e) => e.message, 'message', contains('for field officers'))),
      );
      expect(auth.isSignedIn, isFalse);
    });

    test('opens offline from the stored profile even without valid tokens', () async {
      final store = MemoryTokenStore()
        ..user = {'user_id': 7, 'user_name': 'Jane', 'user_role': 'AGENT'}
        ..access = 'expired';
      final auth = AuthController(api: client(FakeAdapter((o) => (0, null))), tokens: store, db: db);
      await auth.init();
      expect(auth.isSignedIn, isTrue);
      expect(auth.needsReauth, isTrue, reason: 'no refresh token -> banner, not a lock screen');
    });

    test('another officer cannot take over a device with unsynced records', () async {
      final store = MemoryTokenStore();
      final first = AuthController(api: client(FakeAdapter((o) => (200, loginBody('AGENT', id: 1)))), tokens: store, db: db);
      await first.login('a', 'pw');
      await insertFarmer(db);
      await first.logout();

      final second = AuthController(api: client(FakeAdapter((o) => (200, loginBody('AGENT', id: 2)))), tokens: store, db: db);
      await expectLater(second.login('b', 'pw'), throwsA(isA<LoginRefused>()));
      expect(await db.query(Tables.farmers), hasLength(1), reason: 'local data is never wiped silently');
    });
  });
}
