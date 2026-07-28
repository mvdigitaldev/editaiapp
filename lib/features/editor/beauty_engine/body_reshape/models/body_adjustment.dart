import 'body_region.dart';

/// Operações que o motor profissional deve conseguir representar.
enum BodyAdjustmentType {
  waistSlim,
  armSlim,
  legSlim,
  hipExpand,
  chestExpand,
  legLength,
  height,
  bellyReduce,
  shoulderExpand,
  shoulderReduce,
  buttExpand,
  torsoSlim,
  neckSlim,
}

/// Direção semântica; o vetor final é calculado pela estratégia da região.
enum BodyAdjustmentDirection {
  inward,
  outward,
  verticalStretch,
  horizontalExpand,
  horizontalContract,
}

/// Comportamento quando outra parte ou objeto cobre a região ajustada.
enum BodyOcclusionPolicy {
  preserveOccluder,
  reduceIntensity,
  rejectAdjustment,
}

/// Ajuste corporal já normalizado, sem dependência de control points.
class BodyAdjustment {
  final BodyAdjustmentType type;
  final Set<BodyRegion> regions;
  final double intensity;
  final double maxIntensity;
  final double weight;
  final BodyAdjustmentDirection direction;
  final double influence;
  final double minimumConfidence;
  final BodyOcclusionPolicy occlusionPolicy;
  final String sourceParameter;

  const BodyAdjustment({
    required this.type,
    required this.regions,
    required this.intensity,
    required this.maxIntensity,
    required this.weight,
    required this.direction,
    required this.influence,
    required this.minimumConfidence,
    required this.occlusionPolicy,
    required this.sourceParameter,
  })  : assert(intensity >= 0 && intensity <= 1),
        assert(maxIntensity >= 0 && maxIntensity <= 1),
        assert(weight >= 0),
        assert(influence >= 0 && influence <= 1),
        assert(minimumConfidence >= 0 && minimumConfidence <= 1);

  double get effectiveIntensity {
    final limited = intensity < maxIntensity ? intensity : maxIntensity;
    return limited * weight;
  }

  bool get isActive => effectiveIntensity > 0;
}
