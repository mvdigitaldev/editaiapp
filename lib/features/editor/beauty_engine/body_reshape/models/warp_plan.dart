import 'dart:ui';

import 'body_adjustment.dart';
import 'body_reshape_request.dart';
import '../occlusion/occlusion_policy.dart';

/// Motivo explícito de redução/recusa por capacidade ausente.
class CapabilityGateDecision {
  final String parameter;
  final BodyAdjustmentType type;
  final CapabilityGateAction action;
  final String reason;
  final double intensityScale;

  const CapabilityGateDecision({
    required this.parameter,
    required this.type,
    required this.action,
    required this.reason,
    this.intensityScale = 1,
  }) : assert(intensityScale >= 0 && intensityScale <= 1);

  bool get wasRejected => action == CapabilityGateAction.rejected;
  bool get wasReduced => action == CapabilityGateAction.reduced;
}

enum CapabilityGateAction {
  allowed,
  reduced,
  rejected,
}

/// Plano semântico normalizado, anterior à geração da malha e do campo.
class WarpPlan {
  final Size imageSize;
  final List<BodyAdjustment> adjustments;
  final WarpQualityProfile qualityProfile;
  final Set<String> ignoredParameters;
  final List<CapabilityGateDecision> capabilityDecisions;
  final List<OcclusionDecision> occlusionDecisions;

  const WarpPlan({
    required this.imageSize,
    required this.adjustments,
    required this.qualityProfile,
    this.ignoredParameters = const {},
    this.capabilityDecisions = const [],
    this.occlusionDecisions = const [],
  });

  bool get isIdentity =>
      adjustments.every((adjustment) => !adjustment.isActive);

  bool get hasCapabilityGates => capabilityDecisions.isNotEmpty;

  bool get hasOcclusionGates => occlusionDecisions.isNotEmpty;

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

  WarpPlan copyWith({
    Size? imageSize,
    List<BodyAdjustment>? adjustments,
    WarpQualityProfile? qualityProfile,
    Set<String>? ignoredParameters,
    List<CapabilityGateDecision>? capabilityDecisions,
    List<OcclusionDecision>? occlusionDecisions,
  }) {
    return WarpPlan(
      imageSize: imageSize ?? this.imageSize,
      adjustments: adjustments ?? this.adjustments,
      qualityProfile: qualityProfile ?? this.qualityProfile,
      ignoredParameters: ignoredParameters ?? this.ignoredParameters,
      capabilityDecisions: capabilityDecisions ?? this.capabilityDecisions,
      occlusionDecisions: occlusionDecisions ?? this.occlusionDecisions,
    );
  }
}
