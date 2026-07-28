import 'dart:ui';

import '../models/body_adjustment.dart';
import '../models/body_region.dart';
import 'occlusion_map.dart';

/// Decisão explícita de oclusão (nunca silenciosa).
class OcclusionDecision {
  final String parameter;
  final BodyAdjustmentType type;
  final OcclusionAction action;
  final String reason;
  final double intensityScale;
  final double overlapRatio;
  final Set<OccluderKind> occluders;

  const OcclusionDecision({
    required this.parameter,
    required this.type,
    required this.action,
    required this.reason,
    this.intensityScale = 1,
    this.overlapRatio = 0,
    this.occluders = const {},
  }) : assert(intensityScale >= 0 && intensityScale <= 1);

  bool get wasRejected => action == OcclusionAction.rejected;
  bool get wasReduced => action == OcclusionAction.reduced;
  bool get wasAllowed => action == OcclusionAction.allowed;
}

enum OcclusionAction {
  allowed,
  reduced,
  rejected,
}

/// Regras conservadoras: quais oclusores afetam quais ajustes.
class OcclusionPolicy {
  const OcclusionPolicy({
    this.reduceScale = 0.4,
    this.rejectOverlap = 0.45,
    this.reduceOverlap = 0.12,
    this.insufficientEvidenceScale = 0.55,
  })  : assert(reduceScale >= 0 && reduceScale <= 1),
        assert(rejectOverlap >= 0 && rejectOverlap <= 1),
        assert(reduceOverlap >= 0 && reduceOverlap <= 1),
        assert(insufficientEvidenceScale >= 0 && insufficientEvidenceScale <= 1);

  /// Escala quando há overlap parcial com oclusor.
  final double reduceScale;

  /// Overlap acima disso → rejeita (se política permitir).
  final double rejectOverlap;

  /// Overlap acima disso → reduz intensidade.
  final double reduceOverlap;

  /// Escala quando a evidência de oclusão/partes é insuficiente.
  final double insufficientEvidenceScale;

  /// Oclusores relevantes para um tipo de ajuste.
  Set<OccluderKind> sensitiveOccluders(BodyAdjustmentType type) {
    return switch (type) {
      BodyAdjustmentType.waistSlim ||
      BodyAdjustmentType.torsoSlim ||
      BodyAdjustmentType.bellyReduce ||
      BodyAdjustmentType.hipExpand ||
      BodyAdjustmentType.buttExpand ||
      BodyAdjustmentType.chestExpand =>
        {
          OccluderKind.leftHand,
          OccluderKind.rightHand,
          OccluderKind.leftArm,
          OccluderKind.rightArm,
          OccluderKind.foregroundObject,
        },
      BodyAdjustmentType.shoulderExpand ||
      BodyAdjustmentType.shoulderReduce ||
      BodyAdjustmentType.neckSlim =>
        {
          OccluderKind.hair,
          OccluderKind.leftHand,
          OccluderKind.rightHand,
          OccluderKind.foregroundObject,
        },
      BodyAdjustmentType.armSlim => {
          OccluderKind.leftHand,
          OccluderKind.rightHand,
          OccluderKind.foregroundObject,
        },
      BodyAdjustmentType.legSlim || BodyAdjustmentType.legLength => {
          OccluderKind.foregroundObject,
          OccluderKind.leftHand,
          OccluderKind.rightHand,
        },
      BodyAdjustmentType.height => {
          OccluderKind.foregroundObject,
        },
    };
  }

  /// ROI normalizada aproximada da região alvo do ajuste.
  Rect regionOfInterest(Set<BodyRegion> regions) {
    var top = 1.0;
    var bottom = 0.0;
    var left = 1.0;
    var right = 0.0;

    void addBand(double t, double b, double l, double r) {
      if (t < top) top = t;
      if (b > bottom) bottom = b;
      if (l < left) left = l;
      if (r > right) right = r;
    }

    for (final region in regions) {
      switch (region) {
        case BodyRegion.neck:
          addBand(0.08, 0.22, 0.32, 0.68);
        case BodyRegion.shoulders:
          addBand(0.16, 0.30, 0.22, 0.78);
        case BodyRegion.chest:
          addBand(0.22, 0.40, 0.30, 0.70);
        case BodyRegion.waist:
          addBand(0.34, 0.52, 0.30, 0.70);
        case BodyRegion.torso:
          addBand(0.20, 0.55, 0.28, 0.72);
        case BodyRegion.hip:
          addBand(0.46, 0.62, 0.30, 0.70);
        case BodyRegion.butt:
          addBand(0.55, 0.72, 0.30, 0.70);
        case BodyRegion.leftArm || BodyRegion.leftForearm:
          addBand(0.18, 0.55, 0.08, 0.40);
        case BodyRegion.rightArm || BodyRegion.rightForearm:
          addBand(0.18, 0.55, 0.60, 0.92);
        case BodyRegion.leftThigh || BodyRegion.leftCalf:
          addBand(0.48, 0.95, 0.28, 0.50);
        case BodyRegion.rightThigh || BodyRegion.rightCalf:
          addBand(0.48, 0.95, 0.50, 0.72);
      }
    }

    if (right <= left || bottom <= top) {
      return const Rect.fromLTRB(0.25, 0.2, 0.75, 0.7);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  String reasonFor({
    required OcclusionAction action,
    required Set<OccluderKind> occluders,
    required bool insufficientEvidence,
  }) {
    if (insufficientEvidence) {
      return 'occlusion_evidence_insufficient';
    }
    if (occluders.isEmpty) {
      return action == OcclusionAction.allowed
          ? 'no_occluder_overlap'
          : 'occlusion_policy';
    }
    final label = occluders.map((k) => k.name).join('+');
    return switch (action) {
      OcclusionAction.rejected => 'occluder_blocks_$label',
      OcclusionAction.reduced => 'occluder_reduces_$label',
      OcclusionAction.allowed => 'occluder_observed_$label',
    };
  }
}
