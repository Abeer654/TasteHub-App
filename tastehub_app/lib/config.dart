// ============================================================
//  config.dart - build-time application settings
// ============================================================

class AppConfig {
  const AppConfig._();

  /// Base URL of the TasteHub C++ server.
  ///
  /// The default works when the app runs on the same computer as the
  /// server. Override it for a phone or another machine:
  ///
  ///   flutter run -d linux --dart-define=API_BASE_URL=http://127.0.0.1:8080
  ///   flutter build apk --debug --dart-define=API_BASE_URL=http://100.x.y.z:8080
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8080',
  );
}
