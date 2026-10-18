/// Errors surfaced by the network layer, in terms the UI can explain.
sealed class ApiException implements Exception {
  const ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// No connection, DNS failure, timeout: try again later.
class NetworkException extends ApiException {
  const NetworkException([super.message = 'Could not reach the server. Check your connection.']);
}

/// Tokens are missing or the refresh token was rejected: sign in again.
class AuthRequiredException extends ApiException {
  const AuthRequiredException([super.message = 'Sign in again to sync.']);
}

/// Authenticated but not allowed (e.g. role cannot sync).
class ForbiddenException extends ApiException {
  const ForbiddenException([super.message = 'Your account is not allowed to do this.']);
}

/// Any other non-2xx answer.
class ServerException extends ApiException {
  const ServerException(super.message, {this.statusCode, this.data});
  final int? statusCode;
  final Object? data;
}
