import 'body_adjustment.dart';
import 'body_region.dart';
import 'body_reshape_request.dart';
import 'warp_plan.dart';

/// Traduz parâmetros de presets/UI para o domínio semântico do motor V2.
///
/// Menu de corpo zerado (2026-10-01). Sem sliders até existirem Fields novos.
class LegacyBodyParameterAdapter {
  const LegacyBodyParameterAdapter();

  static const supportedParameterKeys = <String>[];

  static List<BodyControlSpec> get controlSpecs => const <BodyControlSpec>[];

  static BodyControlSpec? specFor(String parameter) => null;

  static const v2MeshParameterKeys = <String>{};

  static bool requiresV2Mesh(Map<String, double> parameters) => false;

  WarpPlan buildPlan(BodyReshapeRequest request) {
    return WarpPlan(
      imageSize: request.imageSize,
      adjustments: const [],
      qualityProfile: request.qualityProfile,
    );
  }

  static double readParameter(
    Map<String, double> parameters,
    String snakeCaseKey,
  ) {
    final snakeValue = parameters[snakeCaseKey];
    if (snakeValue != null) {
      return snakeValue.clamp(0.0, 1.0);
    }

    final camelValue = parameters[_toCamelCase(snakeCaseKey)];
    return (camelValue ?? 0).clamp(0.0, 1.0);
  }

  static String _toCamelCase(String snakeCase) {
    final parts = snakeCase.split('_');
    final buffer = StringBuffer(parts.first);
    for (var i = 1; i < parts.length; i++) {
      final part = parts[i];
      if (part.isEmpty) {
        continue;
      }
      buffer
        ..write(part[0].toUpperCase())
        ..write(part.substring(1));
    }
    return buffer.toString();
  }
}

/// Contrato público de um controle body (UI / migração).
class BodyControlSpec {
  final BodyAdjustmentType type;
  final String parameter;
  final Set<BodyRegion> regions;
  final BodyAdjustmentDirection direction;
  final double maxIntensity;
  final double influence;
  final BodyOcclusionPolicy occlusionPolicy;

  const BodyControlSpec({
    required this.type,
    required this.parameter,
    required this.regions,
    required this.direction,
    required this.maxIntensity,
    required this.influence,
    required this.occlusionPolicy,
  });
}
