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
  // Bucket onde as imagens geradas pelas edições são salvas
  static const String editsBucket = 'flux-imagens';
  // Bucket para imagens de entrada (upload antes de processar)
  static const String editInputsBucket = 'edit-inputs';
  // Catálogo (admin): capas de categorias e thumbnails de modelos (mesmo bucket)
  static const String thumbnailBucket = 'thumbnail';
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
