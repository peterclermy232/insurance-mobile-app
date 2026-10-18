import 'dart:async';

import 'package:dio/dio.dart';

import '../auth/token_store.dart';
import '../config/app_config.dart';
import '../utils/logger.dart';
import 'api_exceptions.dart';

/// HTTP client for the backend.
///
/// Authenticated calls attach the access token; on HTTP 401 the token is
/// refreshed once (POST /auth/token/refresh/) and the call is retried once.
/// If the refresh fails, [AuthRequiredException] is thrown. Local data is
/// never touched here.
class ApiClient {
  ApiClient({
    required this.tokens,
    String baseUrl = AppConfig.apiBaseUrl,
    Dio? dio,
  }) : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: AppConfig.connectTimeout,
              receiveTimeout: AppConfig.syncTimeout,
              sendTimeout: AppConfig.syncTimeout,
              headers: {'Accept': 'application/json'},
            )) {
    if (dio != null && dio.options.baseUrl.isEmpty) dio.options.baseUrl = baseUrl;
  }

  final TokenStore tokens;
  final Dio _dio;
  Completer<String>? _refreshing;

  Dio get dio => _dio;

  // ------------------------------------------------------------------ auth

  /// POST /auth/login/ -> {token, refresh, user}. Does not store anything;
  /// the caller decides whether the user may use the app.
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/login/',
        data: {'username': username, 'password': password},
        options: Options(receiveTimeout: AppConfig.authTimeout),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 400) {
        throw ServerException(_errorMessage(e.response?.data) ?? 'Incorrect username or password.',
            statusCode: status);
      }
      if (status == 403) {
        throw ForbiddenException(_errorMessage(e.response?.data) ?? 'This account is inactive.');
      }
      throw _map(e);
    }
  }

  /// Exchanges the refresh token for a new access token. Concurrent callers
  /// share one request.
  Future<String> refreshAccessToken() {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight.future;
    final completer = _refreshing = Completer<String>();
    () async {
      try {
        final refresh = await tokens.readRefreshToken();
        if (refresh == null || refresh.isEmpty) throw const AuthRequiredException();
        final response = await _dio.post<Map<String, dynamic>>(
          '/auth/token/refresh/',
          data: {'refresh': refresh},
          options: Options(receiveTimeout: AppConfig.authTimeout),
        );
        final token = response.data?['token'] as String?;
        if (token == null) throw const AuthRequiredException();
        await tokens.saveTokens(access: token, refresh: response.data?['refresh'] as String?);
        completer.complete(token);
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        completer.completeError(
            (status == 401 || status == 400) ? const AuthRequiredException() : _map(e));
      } catch (e) {
        completer.completeError(e is ApiException ? e : const AuthRequiredException());
      } finally {
        _refreshing = null;
      }
    }();
    return completer.future;
  }

  // ------------------------------------------------------------------ sync

  Future<Map<String, dynamic>> postSync(Map<String, dynamic> payload, {bool uuidIds = false}) async {
    final response = await _authed<Map<String, dynamic>>((options) => _dio.post(
          '/sync/',
          data: payload,
          options: options.copyWith(
            contentType: Headers.jsonContentType,
            headers: {...?options.headers, ..._idFormat(uuidIds)},
          ),
        ));
    final data = response.data;
    if (data == null) throw const ServerException('Empty response from server.');
    return data;
  }

  /// Multipart POST /upload/. Returns the status code and body; HTTP 409
  /// (pending_parent) and 4xx validation errors are returned, not thrown.
  Future<(int, Map<String, dynamic>)> uploadPhoto(Map<String, Object?> fields, String filePath,
      {String? fileName, bool uuidIds = false}) async {
    final response = await _authed<Map<String, dynamic>>((options) async {
      final form = FormData.fromMap({
        for (final e in fields.entries)
          if (e.value != null) e.key: e.value.toString(),
        'file': await MultipartFile.fromFile(filePath,
            filename: fileName, contentType: _imageType(filePath)),
      });
      return _dio.post('/upload/',
          data: form,
          options: options.copyWith(
            headers: {...?options.headers, ..._idFormat(uuidIds)},
            validateStatus: (s) => s != null && s < 500 && s != 401 && s != 403,
          ));
    });
    return (response.statusCode ?? 0, response.data ?? const <String, dynamic>{});
  }

  // --------------------------------------------------------------- helpers

  Future<Response<T>> _authed<T>(Future<Response<T>> Function(Options options) call) async {
    var token = await tokens.readAccessToken();
    token ??= await refreshAccessToken();
    try {
      return await call(_bearer(token));
    } on DioException catch (e) {
      if (e.response?.statusCode != 401) throw _map(e);
      Log.d('Access token rejected, refreshing', tag: 'api');
      final fresh = await refreshAccessToken();
      try {
        return await call(_bearer(fresh));
      } on DioException catch (e2) {
        if (e2.response?.statusCode == 401) throw const AuthRequiredException();
        throw _map(e2);
      }
    }
  }

  /// Asks the server for public UUIDs instead of sequential record ids.
  static Map<String, String> _idFormat(bool uuidIds) => {'X-Id-Format': uuidIds ? 'uuid' : 'numeric'};

  Options _bearer(String token) => Options(headers: {'Authorization': 'Bearer $token'});

  static DioMediaType _imageType(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ? DioMediaType('image', 'png') : DioMediaType('image', 'jpeg');
  }

  ApiException _map(DioException e) {
    final response = e.response;
    if (response == null) {
      Log.d('Network error: ${e.type} ${e.message}', tag: 'api');
      return switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout =>
          const NetworkException('The server took too long to respond. Try again shortly.'),
        _ => const NetworkException(),
      };
    }
    final status = response.statusCode ?? 0;
    if (status == 401) return const AuthRequiredException();
    if (status == 403) {
      return ForbiddenException(_errorMessage(response.data) ?? 'Your account is not allowed to sync.');
    }
    if (status >= 500) {
      return ServerException('The server had a problem ($status). Try again later.',
          statusCode: status, data: response.data);
    }
    return ServerException(_errorMessage(response.data) ?? 'Request failed ($status).',
        statusCode: status, data: response.data);
  }

  static String? _errorMessage(Object? data) {
    if (data is Map) {
      for (final key in const ['error', 'detail', 'message']) {
        final value = data[key];
        if (value is String && value.isNotEmpty) return value;
      }
    }
    return null;
  }
}
