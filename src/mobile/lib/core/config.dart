/// Reads the API base URL from a compile-time define:
///   flutter run --dart-define=API_BASE_URL=http://localhost:8080
/// Defaults to the Android emulator's host-loopback address, since that's
/// the most common local dev target.
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );

  /// src/web's origin, for building the checkout link shown after sending
  /// an invoice (Section 5.1). Same default-vs-emulator reasoning as above.
  static const String webBaseUrl = String.fromEnvironment(
    'WEB_BASE_URL',
    defaultValue: 'http://10.0.2.2:3001',
  );
}
