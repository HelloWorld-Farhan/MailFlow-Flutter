/// Built-in Cloudflare & Supabase client configuration (still supports `--dart-define` overrides).
class AppConfig {
  static const String _defaultSupabaseUrl = 'https://jmkpjvvknttpxzmkhien.supabase.co';
  static const String _defaultSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Impta3BqdnZrbnR0cHh6bWtoaWVuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTU3NzMxMDAsImV4cCI6MjExMTM0OTEwMH0.IQefhHUFqZffdioTKAtSZzpgiylA1IPGjGaJ7yDcx1M';
  static const String _defaultBackendApiUrl = 'https://mailflow-backend.propnexai-support.workers.dev';
  static const String _defaultBackendApiSecret = 'AocVOSTfNkU0qiUs4TM6DtCqBNgEL0KgzbueZXvDP/8=';
  static const String _defaultGoogleWebClientId =
      '787471915530-sg4ul6fm6s1paqabljmksi9c61cf4c77.apps.googleusercontent.com';

  static const String _envSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _envSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String _envBackendApiUrl = String.fromEnvironment('BACKEND_API_URL');
  static const String _envBackendApiSecret = String.fromEnvironment('BACKEND_API_SECRET');
  static const String _envGoogleWebClientId = String.fromEnvironment('GOOGLE_OAUTH_WEB_CLIENT_ID');

  static String supabaseUrl = _pick(_envSupabaseUrl, _defaultSupabaseUrl, stripSlash: true);
  static String supabaseAnonKey = _pick(_envSupabaseAnonKey, _defaultSupabaseAnonKey);
  static String backendApiUrl = _pick(_envBackendApiUrl, _defaultBackendApiUrl, stripSlash: true);
  static String backendApiSecret = _pick(_envBackendApiSecret, _defaultBackendApiSecret);
  static String googleWebClientId = _pick(_envGoogleWebClientId, _defaultGoogleWebClientId);

  static bool get isBackendEnabled => true;

  static Future<void> load() async {
    supabaseUrl = _pick(_envSupabaseUrl, _defaultSupabaseUrl, stripSlash: true);
    supabaseAnonKey = _pick(_envSupabaseAnonKey, _defaultSupabaseAnonKey);
    backendApiUrl = _pick(_envBackendApiUrl, _defaultBackendApiUrl, stripSlash: true);
    backendApiSecret = _pick(_envBackendApiSecret, _defaultBackendApiSecret);
    googleWebClientId = _pick(_envGoogleWebClientId, _defaultGoogleWebClientId);
  }

  static String _pick(String envVal, String fallbackVal, {bool stripSlash = false}) {
    final chosen = envVal.trim().isNotEmpty ? envVal.trim() : fallbackVal.trim();
    return stripSlash ? chosen.replaceAll(RegExp(r'/+$'), '') : chosen;
  }
}
