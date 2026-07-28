import 'dart:typed_data';
import 'dart:ui';

import '../../models/warp_field.dart';
import '../maps/influence_map.dart';
import '../models/body_adjustment.dart';
import '../models/body_frame_assets.dart';
import '../models/body_part_segmentation.dart';
import '../models/warp_plan.dart';
import 'occlusion_map.dart';
import 'occlusion_policy.dart';

/// Resultado da avaliação de oclusão sobre um [WarpPlan].
class OcclusionEvaluation {
  final WarpPlan plan;
  final List<OcclusionDecision> decisions;
  final OcclusionField? field;
  final bool usedInsufficientEvidenceFallback;

  const OcclusionEvaluation({
    required this.plan,
    required this.decisions,
    this.field,
    this.usedInsufficientEvidenceFallback = false,
  });

  bool get hasReductions =>
      decisions.any((d) => d.wasReduced || d.wasRejected);
}

/// Aplica [OcclusionPolicy] ao plano e protege mapas/campos.
class OcclusionEngine {
  const OcclusionEngine({
    this.policy = const OcclusionPolicy(),
  });

  final OcclusionPolicy policy;

  /// Avalia oclusão com evidência dos assets (mapa e/ou partes).
  OcclusionEvaluation evaluate({
    required WarpPlan plan,
    required BodyFrameAssets assets,
    OcclusionField? occlusionField,
  }) {
    final field = occlusionField ??
        (assets.occlusionMap == null
            ? null
            : OcclusionField.fromMap(assets.occlusionMap!));

    final hasParts = assets.partSegmentation != null &&
        !assets.partSegmentation!.isEmpty;
    final hasOcclusion = field != null && !field.isEmpty;
    final insufficient = !hasParts && !hasOcclusion;

    if (insufficient) {
      return _applyInsufficientEvidence(plan);
    }

    final kept = <BodyAdjustment>[];
    final ignored = <String>{...plan.ignoredParameters};
    final decisions = <OcclusionDecision>[];

    for (final adjustment in plan.adjustments) {
      if (!adjustment.isActive) {
        kept.add(adjustment);
        continue;
      }

      final sensitive = policy.sensitiveOccluders(adjustment.type);
      final roi = policy.regionOfInterest(adjustment.regions);
      var overlap = field?.overlapRatioInNormalizedRect(roi) ?? 0.0;
      var present = field == null
          ? <OccluderKind>{}
          : field.presentKinds.intersection(sensitive);

      if (hasParts) {
        final partsOverlap = _partsOverlapRatio(assets, roi, sensitive);
        if (partsOverlap > overlap) {
          overlap = partsOverlap;
        }
        final partKinds = _partsKindsInRoi(assets, roi, sensitive);
        if (present.isEmpty && partKinds.isNotEmpty) {
          present = partKinds;
        } else {
          present = {...present, ...partKinds};
        }
      }

      if (overlap < policy.reduceOverlap || present.isEmpty) {
        kept.add(adjustment);
        decisions.add(
          OcclusionDecision(
            parameter: adjustment.sourceParameter,
            type: adjustment.type,
            action: OcclusionAction.allowed,
            reason: policy.reasonFor(
              action: OcclusionAction.allowed,
              occluders: present,
              insufficientEvidence: false,
            ),
            overlapRatio: overlap,
            occluders: present,
          ),
        );
        continue;
      }

      final decision = _decide(
        adjustment: adjustment,
        overlap: overlap,
        occluders: present,
      );
      _commitDecision(
        decision: decision,
        adjustment: adjustment,
        kept: kept,
        ignored: ignored,
        decisions: decisions,
      );
    }

    return OcclusionEvaluation(
      plan: plan.copyWith(
        adjustments: kept,
        ignoredParameters: ignored,
        occlusionDecisions: decisions,
      ),
      decisions: decisions,
      field: field,
    );
  }

  WarpPlan applyToPlan({
    required WarpPlan plan,
    required BodyFrameAssets assets,
    OcclusionField? occlusionField,
  }) {
    return evaluate(
      plan: plan,
      assets: assets,
      occlusionField: occlusionField,
    ).plan;
  }

  /// Zera influência onde há oclusor (preserva oclusor no remap).
  InfluenceMap protectInfluence({
    required InfluenceMap influence,
    required OcclusionField occlusion,
  }) {
    if (influence.isEmpty || occlusion.isEmpty) {
      return influence;
    }
    final values = Float32List.fromList(influence.values);
    for (var y = 0; y < influence.height; y++) {
      final ny = influence.height == 1 ? 0.5 : y / (influence.height - 1);
      for (var x = 0; x < influence.width; x++) {
        final nx = influence.width == 1 ? 0.5 : x / (influence.width - 1);
        final idx = y * influence.width + x;
        final occ = occlusion.sampleNormalized(nx, ny);
        values[idx] = (values[idx] * (1.0 - occ)).clamp(0.0, 1.0);
      }
    }
    var maxValue = 0.0;
    for (final v in values) {
      if (v > maxValue) maxValue = v;
    }
    return InfluenceMap(
      values: values,
      width: influence.width,
      height: influence.height,
      imageSize: influence.imageSize,
      regions: influence.regions,
      confidence: influence.confidence,
      maxValue: maxValue,
    );
  }

  /// Reduz deslocamento do campo sob oclusores.
  WarpField protectField({
    required WarpField field,
    required OcclusionField occlusion,
  }) {
    if (field.isIdentity || occlusion.isEmpty) {
      return field;
    }
    final outDisp = Float32List(field.displacement.length);
    final outMask = Float32List(field.mask.length);
    final gridW = field.gridWidth;
    final gridH = field.gridHeight;
    final invW = field.imageSize.width > 0 ? 1.0 / field.imageSize.width : 0.0;
    final invH =
        field.imageSize.height > 0 ? 1.0 / field.imageSize.height : 0.0;

    for (var gy = 0; gy < gridH; gy++) {
      for (var gx = 0; gx < gridW; gx++) {
        final idx = gy * gridW + gx;
        final nx = (gx / (gridW <= 1 ? 1 : gridW - 1)) *
            field.imageSize.width *
            invW;
        final ny = (gy / (gridH <= 1 ? 1 : gridH - 1)) *
            field.imageSize.height *
            invH;
        final soft = 1.0 - occlusion.sampleNormalized(nx, ny);
        outDisp[idx * 2] = field.displacement[idx * 2] * soft;
        outDisp[idx * 2 + 1] = field.displacement[idx * 2 + 1] * soft;
        outMask[idx] = field.mask[idx] * soft;
      }
    }

    return field.copyWith(displacement: outDisp, mask: outMask);
  }

  OcclusionEvaluation _applyInsufficientEvidence(WarpPlan plan) {
    final kept = <BodyAdjustment>[];
    final ignored = <String>{...plan.ignoredParameters};
    final decisions = <OcclusionDecision>[];

    for (final adjustment in plan.adjustments) {
      switch (adjustment.occlusionPolicy) {
        case BodyOcclusionPolicy.rejectAdjustment:
          ignored.add(adjustment.sourceParameter);
          decisions.add(
            OcclusionDecision(
              parameter: adjustment.sourceParameter,
              type: adjustment.type,
              action: OcclusionAction.rejected,
              reason: policy.reasonFor(
                action: OcclusionAction.rejected,
                occluders: const {},
                insufficientEvidence: true,
              ),
              intensityScale: 0,
            ),
          );
        case BodyOcclusionPolicy.preserveOccluder:
        case BodyOcclusionPolicy.reduceIntensity:
          final scale = policy.insufficientEvidenceScale;
          kept.add(
            adjustment.copyWith(
              weight: adjustment.weight * scale,
              occlusionReason: 'occlusion_evidence_insufficient',
              occlusionScale: scale,
            ),
          );
          decisions.add(
            OcclusionDecision(
              parameter: adjustment.sourceParameter,
              type: adjustment.type,
              action: OcclusionAction.reduced,
              reason: policy.reasonFor(
                action: OcclusionAction.reduced,
                occluders: const {},
                insufficientEvidence: true,
              ),
              intensityScale: scale,
            ),
          );
      }
    }

    return OcclusionEvaluation(
      plan: plan.copyWith(
        adjustments: kept,
        ignoredParameters: ignored,
        occlusionDecisions: decisions,
      ),
      decisions: decisions,
      usedInsufficientEvidenceFallback: true,
    );
  }

  OcclusionDecision _decide({
    required BodyAdjustment adjustment,
    required double overlap,
    required Set<OccluderKind> occluders,
  }) {
    final shouldReject = overlap >= policy.rejectOverlap &&
        (adjustment.occlusionPolicy == BodyOcclusionPolicy.rejectAdjustment ||
            adjustment.occlusionPolicy == BodyOcclusionPolicy.preserveOccluder);

    if (shouldReject) {
      return OcclusionDecision(
        parameter: adjustment.sourceParameter,
        type: adjustment.type,
        action: OcclusionAction.rejected,
        reason: policy.reasonFor(
          action: OcclusionAction.rejected,
          occluders: occluders,
          insufficientEvidence: false,
        ),
        intensityScale: 0,
        overlapRatio: overlap,
        occluders: occluders,
      );
    }

    if (overlap >= policy.reduceOverlap) {
      final scale = (policy.reduceScale *
              (1.0 -
                  (overlap - policy.reduceOverlap).clamp(0.0, 1.0) * 0.5))
          .clamp(0.1, policy.reduceScale);
      return OcclusionDecision(
        parameter: adjustment.sourceParameter,
        type: adjustment.type,
        action: OcclusionAction.reduced,
        reason: policy.reasonFor(
          action: OcclusionAction.reduced,
          occluders: occluders,
          insufficientEvidence: false,
        ),
        intensityScale: scale,
        overlapRatio: overlap,
        occluders: occluders,
      );
    }

    return OcclusionDecision(
      parameter: adjustment.sourceParameter,
      type: adjustment.type,
      action: OcclusionAction.allowed,
      reason: policy.reasonFor(
        action: OcclusionAction.allowed,
        occluders: occluders,
        insufficientEvidence: false,
      ),
      overlapRatio: overlap,
      occluders: occluders,
    );
  }

  void _commitDecision({
    required OcclusionDecision decision,
    required BodyAdjustment adjustment,
    required List<BodyAdjustment> kept,
    required Set<String> ignored,
    required List<OcclusionDecision> decisions,
  }) {
    decisions.add(decision);
    if (decision.wasRejected) {
      ignored.add(adjustment.sourceParameter);
      return;
    }
    if (decision.wasReduced) {
      kept.add(
        adjustment.copyWith(
          weight: adjustment.weight * decision.intensityScale,
          occlusionReason: decision.reason,
          occlusionScale: decision.intensityScale,
        ),
      );
      return;
    }
    kept.add(adjustment);
  }

  double _partsOverlapRatio(
    BodyFrameAssets assets,
    Rect roi,
    Set<OccluderKind> sensitive,
  ) {
    final parts = assets.partSegmentation;
    if (parts == null || parts.isEmpty) {
      return 0;
    }
    final targetLabels = _labelsForKinds(sensitive);
    if (targetLabels.isEmpty) {
      return 0;
    }
    final w = parts.width;
    final h = parts.height;
    final x0 = (roi.left.clamp(0.0, 1.0) * (w - 1)).floor();
    final y0 = (roi.top.clamp(0.0, 1.0) * (h - 1)).floor();
    final x1 = (roi.right.clamp(0.0, 1.0) * (w - 1)).ceil();
    final y1 = (roi.bottom.clamp(0.0, 1.0) * (h - 1)).ceil();
    var hits = 0;
    var total = 0;
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        total++;
        final code = parts.labels[y * w + x];
        if (code >= 0 &&
            code < BodyPartLabel.values.length &&
            targetLabels.contains(BodyPartLabel.values[code])) {
          hits++;
        }
      }
    }
    return total == 0 ? 0 : hits / total;
  }

  Set<OccluderKind> _partsKindsInRoi(
    BodyFrameAssets assets,
    Rect roi,
    Set<OccluderKind> sensitive,
  ) {
    final parts = assets.partSegmentation;
    if (parts == null || parts.isEmpty) {
      return {};
    }
    final found = <OccluderKind>{};
    final w = parts.width;
    final h = parts.height;
    final x0 = (roi.left.clamp(0.0, 1.0) * (w - 1)).floor();
    final y0 = (roi.top.clamp(0.0, 1.0) * (h - 1)).floor();
    final x1 = (roi.right.clamp(0.0, 1.0) * (w - 1)).ceil();
    final y1 = (roi.bottom.clamp(0.0, 1.0) * (h - 1)).ceil();
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final code = parts.labels[y * w + x];
        if (code < 0 || code >= BodyPartLabel.values.length) {
          continue;
        }
        final kind = _kindForLabel(BodyPartLabel.values[code]);
        if (kind != null && sensitive.contains(kind)) {
          found.add(kind);
        }
      }
    }
    return found;
  }

  Set<BodyPartLabel> _labelsForKinds(Set<OccluderKind> kinds) {
    final labels = <BodyPartLabel>{};
    for (final kind in kinds) {
      switch (kind) {
        case OccluderKind.leftHand:
          labels.add(BodyPartLabel.leftHand);
        case OccluderKind.rightHand:
          labels.add(BodyPartLabel.rightHand);
        case OccluderKind.leftArm:
          labels
            ..add(BodyPartLabel.leftArm)
            ..add(BodyPartLabel.leftForearm);
        case OccluderKind.rightArm:
          labels
            ..add(BodyPartLabel.rightArm)
            ..add(BodyPartLabel.rightForearm);
        case OccluderKind.hair:
          labels.add(BodyPartLabel.hair);
        case OccluderKind.foregroundObject:
        case OccluderKind.unknown:
          break;
      }
    }
    return labels;
  }

  OccluderKind? _kindForLabel(BodyPartLabel label) {
    return switch (label) {
      BodyPartLabel.leftHand => OccluderKind.leftHand,
      BodyPartLabel.rightHand => OccluderKind.rightHand,
      BodyPartLabel.leftArm || BodyPartLabel.leftForearm => OccluderKind.leftArm,
      BodyPartLabel.rightArm ||
      BodyPartLabel.rightForearm =>
        OccluderKind.rightArm,
      BodyPartLabel.hair => OccluderKind.hair,
      _ => null,
    };
  }
}
