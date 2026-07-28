import '../models/body_adjustment.dart';
import '../models/warp_plan.dart';
import 'vision_capabilities.dart';

/// Aplica políticas explícitas quando o provider não oferece oclusão/partes.
///
/// Sem fallback silencioso: toda redução ou recusa gera [CapabilityGateDecision].
class VisionCapabilityGate {
  const VisionCapabilityGate({
    this.missingOcclusionScale = 0.55,
  }) : assert(missingOcclusionScale >= 0 && missingOcclusionScale <= 1);

  /// Escala aplicada a ajustes `preserveOccluder` sem mapa de oclusão.
  final double missingOcclusionScale;

  WarpPlan apply({
    required WarpPlan plan,
    required VisionCapabilities capabilities,
  }) {
    if (!capabilities.poseLandmarks) {
      final decisions = plan.adjustments
          .map(
            (adjustment) => CapabilityGateDecision(
              parameter: adjustment.sourceParameter,
              type: adjustment.type,
              action: CapabilityGateAction.rejected,
              reason: 'pose_landmarks_unavailable',
            ),
          )
          .toList(growable: false);

      return plan.copyWith(
        adjustments: const [],
        ignoredParameters: {
          ...plan.ignoredParameters,
          for (final decision in decisions) decision.parameter,
        },
        capabilityDecisions: [
          ...plan.capabilityDecisions,
          ...decisions,
        ],
      );
    }

    final kept = <BodyAdjustment>[];
    final ignored = <String>{...plan.ignoredParameters};
    final decisions = <CapabilityGateDecision>[...plan.capabilityDecisions];

    for (final adjustment in plan.adjustments) {
      final needsPartsOrOcclusion =
          !capabilities.bodyPartSegmentation && !capabilities.occlusionMap;

      if (!needsPartsOrOcclusion) {
        kept.add(adjustment);
        decisions.add(
          CapabilityGateDecision(
            parameter: adjustment.sourceParameter,
            type: adjustment.type,
            action: CapabilityGateAction.allowed,
            reason: 'capabilities_sufficient',
          ),
        );
        continue;
      }

      switch (adjustment.occlusionPolicy) {
        case BodyOcclusionPolicy.rejectAdjustment:
          ignored.add(adjustment.sourceParameter);
          decisions.add(
            CapabilityGateDecision(
              parameter: adjustment.sourceParameter,
              type: adjustment.type,
              action: CapabilityGateAction.rejected,
              reason: 'occlusion_or_parts_unavailable',
            ),
          );
        case BodyOcclusionPolicy.preserveOccluder:
        case BodyOcclusionPolicy.reduceIntensity:
          final scaled = adjustment.copyWith(
            weight: adjustment.weight * missingOcclusionScale,
          );
          kept.add(scaled);
          decisions.add(
            CapabilityGateDecision(
              parameter: adjustment.sourceParameter,
              type: adjustment.type,
              action: CapabilityGateAction.reduced,
              reason: 'occlusion_or_parts_unavailable',
              intensityScale: missingOcclusionScale,
            ),
          );
      }
    }

    return plan.copyWith(
      adjustments: kept,
      ignoredParameters: ignored,
      capabilityDecisions: decisions,
    );
  }
}
