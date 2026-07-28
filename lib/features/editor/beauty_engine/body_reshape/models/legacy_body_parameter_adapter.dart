import 'body_adjustment.dart';
import 'body_region.dart';
import 'body_reshape_request.dart';
import 'warp_plan.dart';

/// Traduz parâmetros de presets/UI para o domínio semântico do motor V2.
///
/// Cada spec declara região, limite, direção, peso implícito e política de
/// oclusão — contrato exigido pela Sprint 12.
class LegacyBodyParameterAdapter {
  const LegacyBodyParameterAdapter();

  static const supportedParameterKeys = <String>[
    'waist_slim',
    'hip',
    'body_slim',
    'leg_length',
    'leg_slim',
    'arm_slim',
    'neck_slim',
    'shoulder_width',
    'chest_expand',
    'belly_reduce',
    'butt_expand',
    'height',
    'shoulder_reduce',
    'arm_upper_slim',
    'arm_forearm_slim',
    'leg_thigh_slim',
    'leg_calf_slim',
  ];

  static const _specifications = <_AdjustmentSpec>[
    _AdjustmentSpec(
      type: BodyAdjustmentType.waistSlim,
      parameter: 'waist_slim',
      regions: {BodyRegion.waist},
      direction: BodyAdjustmentDirection.inward,
      maxIntensity: 0.85,
      influence: 0.7,
    ),
    _AdjustmentSpec(
      type: BodyAdjustmentType.hipExpand,
      parameter: 'hip',
      regions: {BodyRegion.hip},
      direction: BodyAdjustmentDirection.outward,
      maxIntensity: 0.8,
      influence: 0.7,
    ),
    _AdjustmentSpec(
      type: BodyAdjustmentType.torsoSlim,
      parameter: 'body_slim',
      regions: {BodyRegion.torso},
      direction: BodyAdjustmentDirection.inward,
      maxIntensity: 0.8,
      influence: 0.8,
    ),
    _AdjustmentSpec(
      type: BodyAdjustmentType.legLength,
      parameter: 'leg_length',
      regions: {
        BodyRegion.leftThigh,
        BodyRegion.rightThigh,
        BodyRegion.leftCalf,
        BodyRegion.rightCalf,
      },
      direction: BodyAdjustmentDirection.verticalStretch,
      maxIntensity: 0.75,
      influence: 0.85,
      occlusionPolicy: BodyOcclusionPolicy.rejectAdjustment,
    ),
    _AdjustmentSpec(
      type: BodyAdjustmentType.legSlim,
      parameter: 'leg_slim',
      regions: {
        BodyRegion.leftThigh,
        BodyRegion.rightThigh,
        BodyRegion.leftCalf,
        BodyRegion.rightCalf,
      },
      direction: BodyAdjustmentDirection.inward,
      maxIntensity: 0.8,
      influence: 0.65,
    ),
    _AdjustmentSpec(
      type: BodyAdjustmentType.armSlim,
      parameter: 'arm_slim',
      regions: {
        BodyRegion.leftArm,
        BodyRegion.rightArm,
        BodyRegion.leftForearm,
        BodyRegion.rightForearm,
      },
      direction: BodyAdjustmentDirection.inward,
      maxIntensity: 0.75,
      influence: 0.55,
    ),
    _AdjustmentSpec(
      type: BodyAdjustmentType.neckSlim,
      parameter: 'neck_slim',
      regions: {BodyRegion.neck},
      direction: BodyAdjustmentDirection.inward,
      maxIntensity: 0.65,
      influence: 0.45,
    ),
    _AdjustmentSpec(
      type: BodyAdjustmentType.shoulderExpand,
      parameter: 'shoulder_width',
      regions: {BodyRegion.shoulders},
      direction: BodyAdjustmentDirection.horizontalExpand,
      maxIntensity: 0.75,
      influence: 0.65,
    ),
    _AdjustmentSpec(
      type: BodyAdjustmentType.chestExpand,
      parameter: 'chest_expand',
      regions: {BodyRegion.chest},
      direction: BodyAdjustmentDirection.outward,
      maxIntensity: 0.75,
      influence: 0.65,
    ),
    _AdjustmentSpec(
      type: BodyAdjustmentType.bellyReduce,
      parameter: 'belly_reduce',
      regions: {BodyRegion.waist, BodyRegion.torso},
      direction: BodyAdjustmentDirection.inward,
      maxIntensity: 0.8,
      influence: 0.7,
    ),
    _AdjustmentSpec(
      type: BodyAdjustmentType.buttExpand,
      parameter: 'butt_expand',
      regions: {BodyRegion.butt},
      direction: BodyAdjustmentDirection.outward,
      maxIntensity: 0.75,
      influence: 0.65,
    ),
    _AdjustmentSpec(
      type: BodyAdjustmentType.height,
      parameter: 'height',
      regions: {
        BodyRegion.torso,
        BodyRegion.chest,
        BodyRegion.waist,
        BodyRegion.shoulders,
        BodyRegion.neck,
      },
      direction: BodyAdjustmentDirection.verticalStretch,
      maxIntensity: 0.7,
      influence: 0.8,
      occlusionPolicy: BodyOcclusionPolicy.rejectAdjustment,
    ),
    _AdjustmentSpec(
      type: BodyAdjustmentType.shoulderReduce,
      parameter: 'shoulder_reduce',
      regions: {BodyRegion.shoulders},
      direction: BodyAdjustmentDirection.horizontalContract,
      maxIntensity: 0.7,
      influence: 0.6,
    ),
    _AdjustmentSpec(
      type: BodyAdjustmentType.armSlim,
      parameter: 'arm_upper_slim',
      regions: {BodyRegion.leftArm, BodyRegion.rightArm},
      direction: BodyAdjustmentDirection.inward,
      maxIntensity: 0.75,
      influence: 0.55,
    ),
    _AdjustmentSpec(
      type: BodyAdjustmentType.armSlim,
      parameter: 'arm_forearm_slim',
      regions: {BodyRegion.leftForearm, BodyRegion.rightForearm},
      direction: BodyAdjustmentDirection.inward,
      maxIntensity: 0.7,
      influence: 0.5,
    ),
    _AdjustmentSpec(
      type: BodyAdjustmentType.legSlim,
      parameter: 'leg_thigh_slim',
      regions: {BodyRegion.leftThigh, BodyRegion.rightThigh},
      direction: BodyAdjustmentDirection.inward,
      maxIntensity: 0.8,
      influence: 0.65,
    ),
    _AdjustmentSpec(
      type: BodyAdjustmentType.legSlim,
      parameter: 'leg_calf_slim',
      regions: {BodyRegion.leftCalf, BodyRegion.rightCalf},
      direction: BodyAdjustmentDirection.inward,
      maxIntensity: 0.75,
      influence: 0.6,
    ),
  ];

  /// Specs públicas para UI/testes (região, limite, direção, oclusão).
  static List<BodyControlSpec> get controlSpecs => [
        for (final spec in _specifications) spec.toPublicSpec(),
      ];

  static BodyControlSpec? specFor(String parameter) {
    for (final spec in _specifications) {
      if (spec.parameter == parameter) {
        return spec.toPublicSpec();
      }
    }
    return null;
  }

  /// Keys sem filtro MLS legado — exigem deformação de malha V2.
  static const v2MeshParameterKeys = <String>{
    'chest_expand',
    'belly_reduce',
    'butt_expand',
    'height',
    'shoulder_reduce',
    'arm_upper_slim',
    'arm_forearm_slim',
    'leg_thigh_slim',
    'leg_calf_slim',
  };

  static bool requiresV2Mesh(Map<String, double> parameters) {
    for (final key in v2MeshParameterKeys) {
      if (readParameter(parameters, key) > 0) {
        return true;
      }
    }
    return false;
  }

  WarpPlan buildPlan(BodyReshapeRequest request) {
    final adjustments = <BodyAdjustment>[];
    for (final specification in _specifications) {
      final intensity = readParameter(
        request.parameters,
        specification.parameter,
      );
      if (intensity <= 0) {
        continue;
      }
      adjustments.add(specification.toAdjustment(intensity));
    }

    return WarpPlan(
      imageSize: request.imageSize,
      adjustments: adjustments,
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

class _AdjustmentSpec {
  final BodyAdjustmentType type;
  final String parameter;
  final Set<BodyRegion> regions;
  final BodyAdjustmentDirection direction;
  final double maxIntensity;
  final double influence;
  final BodyOcclusionPolicy occlusionPolicy;

  const _AdjustmentSpec({
    required this.type,
    required this.parameter,
    required this.regions,
    required this.direction,
    required this.maxIntensity,
    required this.influence,
    this.occlusionPolicy = BodyOcclusionPolicy.preserveOccluder,
  });

  BodyControlSpec toPublicSpec() => BodyControlSpec(
        type: type,
        parameter: parameter,
        regions: regions,
        direction: direction,
        maxIntensity: maxIntensity,
        influence: influence,
        occlusionPolicy: occlusionPolicy,
      );

  BodyAdjustment toAdjustment(double intensity) {
    return BodyAdjustment(
      type: type,
      regions: regions,
      intensity: intensity,
      maxIntensity: maxIntensity,
      weight: 1,
      direction: direction,
      influence: influence,
      minimumConfidence: 0.5,
      occlusionPolicy: occlusionPolicy,
      sourceParameter: parameter,
    );
  }
}
