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

  /// Escala aplicada por oclusão (1 = sem redução).
  final double occlusionScale;

  /// Motivo explícito quando a oclusão reduziu/limitou o ajuste.
  final String? occlusionReason;

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
    this.occlusionScale = 1,
    this.occlusionReason,
  })  : assert(intensity >= 0 && intensity <= 1),
        assert(maxIntensity >= 0 && maxIntensity <= 1),
        assert(weight >= 0),
        assert(influence >= 0 && influence <= 1),
        assert(minimumConfidence >= 0 && minimumConfidence <= 1),
        assert(occlusionScale >= 0 && occlusionScale <= 1);

  double get effectiveIntensity {
    final limited = intensity < maxIntensity ? intensity : maxIntensity;
    return limited * weight;
  }

  bool get isActive => effectiveIntensity > 0;

  bool get wasOcclusionLimited =>
      occlusionReason != null || occlusionScale < 0.999;

  BodyAdjustment copyWith({
    BodyAdjustmentType? type,
    Set<BodyRegion>? regions,
    double? intensity,
    double? maxIntensity,
    double? weight,
    BodyAdjustmentDirection? direction,
    double? influence,
    double? minimumConfidence,
    BodyOcclusionPolicy? occlusionPolicy,
    String? sourceParameter,
    double? occlusionScale,
    String? occlusionReason,
  }) {
    return BodyAdjustment(
      type: type ?? this.type,
      regions: regions ?? this.regions,
      intensity: intensity ?? this.intensity,
      maxIntensity: maxIntensity ?? this.maxIntensity,
      weight: weight ?? this.weight,
      direction: direction ?? this.direction,
      influence: influence ?? this.influence,
      minimumConfidence: minimumConfidence ?? this.minimumConfidence,
      occlusionPolicy: occlusionPolicy ?? this.occlusionPolicy,
      sourceParameter: sourceParameter ?? this.sourceParameter,
      occlusionScale: occlusionScale ?? this.occlusionScale,
      occlusionReason: occlusionReason ?? this.occlusionReason,
    );
  }
}
