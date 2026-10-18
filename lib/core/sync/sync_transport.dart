import '../network/api_client.dart';

/// The two calls the sync engine makes. Abstracted so tests can use a fake.
abstract class SyncTransport {
  /// POST /sync/ with the request body from the contract; returns the body.
  /// [uuidIds] asks the server for public UUIDs instead of numeric record ids.
  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload, {bool uuidIds = false});

  /// POST /upload/ (multipart). Returns (http status, body). Must throw an
  /// ApiException for network/auth failures and return 4xx answers.
  Future<(int, Map<String, dynamic>)> upload(Map<String, Object?> fields, String filePath,
      {bool uuidIds = false});
}

class ApiSyncTransport implements SyncTransport {
  ApiSyncTransport(this.api);
  final ApiClient api;

  @override
  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload, {bool uuidIds = false}) =>
      api.postSync(payload, uuidIds: uuidIds);

  @override
  Future<(int, Map<String, dynamic>)> upload(Map<String, Object?> fields, String filePath,
          {bool uuidIds = false}) =>
      api.uploadPhoto(fields, filePath, uuidIds: uuidIds);
}
