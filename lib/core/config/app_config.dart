import 'supabase_config.dart';

class AppConfig {
  // Supabase: dart-define tem prioridade; fallback para config local (supabase_config.dart)
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: SupabaseConfig.url,
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: SupabaseConfig.anonKey,
  );

  // App Configuration
  static const String appName = 'Editai';
  static const String appVersion = '1.0.0';

  // Storage Configuration
  static const String photosBucket = 'photos';
  static const String avatarsBucket = 'avatars';
  static const int maxFileSizeBytes = 50 * 1024 * 1024; // 50MB
  static const List<String> allowedImageTypes = ['image/jpeg', 'image/png', 'image/webp'];

  // Pagination
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;

  // Rate Limiting
  static const int maxUploadsPerMinute = 10;
  static const int maxConcurrentJobsFree = 5;
  static const int maxConcurrentJobsPremium = 10;
}
