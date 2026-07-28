import 'body_adjustment.dart';
import 'body_region.dart';
import 'body_reshape_request.dart';
import 'warp_plan.dart';

/// Traduz parâmetros de presets/UI para o domínio semântico do motor V2.
///
/// Esse adaptador não executa deformação. O pipeline legado continua sendo a
/// implementação ativa até que os módulos de malha e renderização V2 existam.
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
  ];

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
