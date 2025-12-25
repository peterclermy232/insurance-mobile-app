import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ApiClient {
  static final ApiClient instance = ApiClient._init();
  late Dio _dio;
  final _storage = const FlutterSecureStorage();

  static const String baseUrl = 'https://web-production-39ac0.up.railway.app/api/v1';

  ApiClient._init() {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        print('🌐 API Request: ${options.method} ${options.baseUrl}${options.path}');
        return handler.next(options);
      },
      onResponse: (response, handler) {
        print('✅ API Response: ${response.statusCode} ${response.requestOptions.path}');
        return handler.next(response);
      },
      onError: (error, handler) {
        print('❌ API Error: ${error.message}');
        return handler.next(error);
      },
    ));
  }

  /// ===== NETWORK CHECK =====
  Future<bool> isOnline() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  /// ===== AUTH =====
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await _dio.post('/auth/login/', data: {
        'username': email,
        'password': password,
      });

      if (response.data['token'] != null) {
        await _storage.write(key: 'auth_token', value: response.data['token']);
        await _storage.write(
            key: 'user_id', value: response.data['user']['user_id'].toString());
        await _storage.write(key: 'user_name', value: response.data['user']['user_name']);
        await _storage.write(
            key: 'organisation_id', value: response.data['user']['organisation'].toString());
      }

      return response.data;
    } catch (e) {
      throw Exception('Login failed: $e');
    }
  }

  Future<void> logout() async {
    await _storage.deleteAll();
  }

  Future<String?> getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  Future<String?> getOrganisationId() async {
    return await _storage.read(key: 'organisation_id');
  }

  /// ===== ORGANISATIONS =====
  Future<List<dynamic>> getOrganisations() async {
    try {
      final response = await _dio.get('/organisations/');

      // Handle both array and paginated responses
      if (response.data is List) {
        return response.data;
      } else if (response.data is Map && response.data['results'] != null) {
        return response.data['results'];
      } else {
        return [];
      }
    } catch (e) {
      print('❌ Failed to fetch organisations: $e');
      throw Exception('Failed to fetch organisations: $e');
    }
  }

  /// ===== FARMERS =====
  Future<List<dynamic>> getFarmers() async {
    final response = await _dio.get('/farmers/');
    return response.data is List ? response.data : (response.data['results'] ?? []);
  }

  Future<Map<String, dynamic>> createFarmer(Map<String, dynamic> data) async {
    final response = await _dio.post('/farmers/', data: data);
    return response.data;
  }

  Future<Map<String, dynamic>> updateFarmer(int id, Map<String, dynamic> data) async {
    final response = await _dio.patch('/farmers/$id/', data: data);
    return response.data;
  }

  /// ===== CLAIMS =====
  Future<List<dynamic>> getClaims() async {
    final response = await _dio.get('/claims/');
    return response.data is List ? response.data : (response.data['results'] ?? []);
  }

  Future<Map<String, dynamic>> createClaim(Map<String, dynamic> data) async {
    final response = await _dio.post('/claims/', data: data);
    return response.data;
  }

  Future<Map<String, dynamic>> updateClaim(int id, Map<String, dynamic> data) async {
    final response = await _dio.patch('/claims/$id/', data: data);
    return response.data;
  }

  /// ===== IMAGE UPLOAD =====
  Future<String> uploadImage(String filePath, String fieldName) async {
    FormData formData = FormData.fromMap({
      fieldName: await MultipartFile.fromFile(filePath),
    });

    final response = await _dio.post('/upload/', data: formData);
    return response.data['url'];
  }

  /// ===== TEST CONNECTION =====
  Future<bool> testConnection() async {
    try {
      final response = await _dio.get('/countries/');
      print('✅ Connection successful! Status: ${response.statusCode}');
      return true;
    } catch (e) {
      print('❌ Connection failed: $e');
      return false;
    }
  }
  /// ===== GENERIC HTTP METHODS =====

  Future<Map<String, dynamic>> post(
      String path, {
        Map<String, dynamic>? data,
      }) async {
    final response = await _dio.post(path, data: data);
    return _normalizeResponse(response.data);
  }

  Future<Map<String, dynamic>> get(
      String path, {
        Map<String, dynamic>? queryParameters,
      }) async {
    final response = await _dio.get(path, queryParameters: queryParameters);
    return _normalizeResponse(response.data);
  }

  Future<Map<String, dynamic>> patch(
      String path, {
        Map<String, dynamic>? data,
      }) async {
    final response = await _dio.patch(path, data: data);
    return _normalizeResponse(response.data);
  }

  Future<void> delete(String path) async {
    await _dio.delete(path);
  }

  /// Normalize API response (handles list or map)
  Map<String, dynamic> _normalizeResponse(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    return {'results': data};
  }


}