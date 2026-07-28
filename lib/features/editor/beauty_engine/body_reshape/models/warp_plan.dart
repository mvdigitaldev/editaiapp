import 'dart:ui';

import 'body_adjustment.dart';
import 'body_reshape_request.dart';

/// Plano semântico normalizado, anterior à geração da malha e do campo.
class WarpPlan {
  final Size imageSize;
  final List<BodyAdjustment> adjustments;
  final WarpQualityProfile qualityProfile;
  final Set<String> ignoredParameters;

  const WarpPlan({
    required this.imageSize,
    required this.adjustments,
    required this.qualityProfile,
    this.ignoredParameters = const {},
  });

  bool get isIdentity =>
      adjustments.every((adjustment) => !adjustment.isActive);

  double get maxIntensity {
    var maximum = 0.0;
    for (final adjustment in adjustments) {
      if (adjustment.effectiveIntensity > maximum) {
        maximum = adjustment.effectiveIntensity;
      }
    }
    return maximum;
  }

  BodyAdjustment? adjustmentOfType(BodyAdjustmentType type) {
    for (final adjustment in adjustments) {
      if (adjustment.type == type) {
        return adjustment;
      }
    }
    return null;
  }
}
