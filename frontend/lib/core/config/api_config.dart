class ApiConfig {
  ApiConfig._();

  // Override with --dart-define=API_BASE_URL=http://<host>:5000 when needed.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:5000',
  );
}