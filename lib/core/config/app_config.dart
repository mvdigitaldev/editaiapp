class AppConfig {
  // Supabase Configuration
  // TODO: Adicionar variáveis de ambiente
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  // App Configuration
  static const String appName = 'Editai';
  static const String appVersion = '1.0.0';

  // Storage Configuration
  static const String photosBucket = 'photos';
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
