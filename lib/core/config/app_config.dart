/// Build-time configuration.
///
/// Point the app at another server with:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
class AppConfig {
  AppConfig._();

  static const String appName = 'Crop Insurance Field';

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://crop-insurance-api-46ql.onrender.com/api/v1',
  );

  /// The hosted server sleeps when idle and can take ~50s to wake up, so
  /// network calls get generous timeouts.
  static const Duration connectTimeout = Duration(seconds: 60);
  static const Duration syncTimeout = Duration(seconds: 90);
  static const Duration authTimeout = Duration(seconds: 75);

  /// After this long without a response the UI explains the server is waking up.
  static const Duration slowServerHint = Duration(seconds: 6);

  /// Roles allowed to use the field app.
  static const Set<String> fieldRoles = {'AGENT', 'ASSESSOR', 'MANAGER'};
}
