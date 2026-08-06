class BanubaConfig {
  const BanubaConfig._();

  /// Fallback compilado para versões antigas e indisponibilidade do Supabase.
  static const buildTimeLicenseToken = String.fromEnvironment(
    'BANUBA_LICENSE_TOKEN',
  );

  static bool isConfigured(String token) => token.trim().isNotEmpty;
}
