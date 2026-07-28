import '../models/body_params.dart';

/// Migração de body params para o schema Sprint 12 (versão 3).
///
/// Presets antigos (v1/v2) sem campos novos permanecem válidos — defaults 0.
abstract final class BeautyPresetBodyMigration {
  /// Versão do schema de body após Sprint 12.
  static const currentBodySchemaVersion = 3;

  static ({Map<String, dynamic> bodyJson, int version}) migrate({
    required Map<String, dynamic> bodyJson,
    required int presetVersion,
  }) {
    // BodyParams.fromJson preenche campos Sprint 12 ausentes com 0.
    // Presets v1/v2 continuam válidos sem reescrever o número de versão.
    final body = BodyParams.fromJson(bodyJson);
    return (bodyJson: body.toJson(), version: presetVersion);
  }

  /// Normaliza um preset já desserializado (ex.: após sync remoto).
  static BodyParams normalizeBody(BodyParams body) =>
      BodyParams.fromJson(body.toJson());
}
