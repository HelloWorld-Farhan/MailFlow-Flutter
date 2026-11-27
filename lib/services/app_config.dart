import 'package:shared_preferences/shared_preferences.dart';

/// Dynamic runtime configuration loaded from `--dart-define` / `--dart-define-from-file`
/// or local SharedPreferences overrides. Zero URLs or secrets are hardcoded.
class AppConfig {
  static const String _envSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _envSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String _envBackendApiUrl = String.fromEnvironment('BACKEND_API_URL');
  static const String _envBackendApiSecret = String.fromEnvironment('BACKEND_API_SECRET');
  static const String _envGoogleWebClientId = String.fromEnvironment('GOOGLE_OAUTH_WEB_CLIENT_ID');

  static const String _kSupabaseUrl = 'cfg_supabase_url';
  static const String _kSupabaseAnonKey = 'cfg_supabase_anon_key';
  static const String _kBackendApiUrl = 'cfg_backend_api_url';
  static const String _kBackendApiSecret = 'cfg_backend_api_secret';
  static const String _kGoogleWebClientId = 'cfg_google_web_client_id';

  static String supabaseUrl = _envSupabaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  static String supabaseAnonKey = _envSupabaseAnonKey.trim();
  static String backendApiUrl = _envBackendApiUrl.trim().replaceAll(RegExp(r'/+$'), '');
  static String backendApiSecret = _envBackendApiSecret.trim();
  static String googleWebClientId = _envGoogleWebClientId.trim();

  static bool get isBackendEnabled =>
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty &&
      backendApiUrl.isNotEmpty &&
      backendApiSecret.isNotEmpty;

  /// Loads compile-time config and applies any non-empty SharedPreferences overrides.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    supabaseUrl = _pick(prefs.getString(_kSupabaseUrl), _envSupabaseUrl, stripSlash: true);
    supabaseAnonKey = _pick(prefs.getString(_kSupabaseAnonKey), _envSupabaseAnonKey);
    backendApiUrl = _pick(prefs.getString(_kBackendApiUrl), _envBackendApiUrl, stripSlash: true);
    backendApiSecret = _pick(prefs.getString(_kBackendApiSecret), _envBackendApiSecret);
    googleWebClientId = _pick(prefs.getString(_kGoogleWebClientId), _envGoogleWebClientId);
  }

  /// Persists runtime overrides in SharedPreferences and updates active config in memory.
  static Future<void> saveOverrides({
    required String supabaseUrlValue,
    required String supabaseAnonKeyValue,
    required String backendApiUrlValue,
    required String backendApiSecretValue,
    required String googleWebClientIdValue,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSupabaseUrl, supabaseUrlValue.trim().replaceAll(RegExp(r'/+$'), ''));
    await prefs.setString(_kSupabaseAnonKey, supabaseAnonKeyValue.trim());
    await prefs.setString(_kBackendApiUrl, backendApiUrlValue.trim().replaceAll(RegExp(r'/+$'), ''));
    await prefs.setString(_kBackendApiSecret, backendApiSecretValue.trim());
    await prefs.setString(_kGoogleWebClientId, googleWebClientIdValue.trim());
    await load();
  }

  static String _pick(String? overrideVal, String envVal, {bool stripSlash = false}) {
    final chosen = (overrideVal != null && overrideVal.trim().isNotEmpty)
        ? overrideVal.trim()
        : envVal.trim();
    return stripSlash ? chosen.replaceAll(RegExp(r'/+$'), '') : chosen;
  }
}
