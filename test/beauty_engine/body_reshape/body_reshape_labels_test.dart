import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_adjustment.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_reshape_request.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/legacy_body_parameter_adapter.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/warp_plan.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/occlusion/occlusion_policy.dart';
import 'package:editaiapp/features/editor/beauty_engine/l10n/body_reshape_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('limitationHint reports occlusion and capability gates', () {
    final plan = WarpPlan(
      imageSize: const Size(100, 200),
      adjustments: const [
        BodyAdjustment(
          type: BodyAdjustmentType.waistSlim,
          regions: {},
          intensity: 0.5,
          maxIntensity: 0.85,
          weight: 1,
          direction: BodyAdjustmentDirection.inward,
          influence: 0.7,
          minimumConfidence: 0.5,
          occlusionPolicy: BodyOcclusionPolicy.reduceIntensity,
          sourceParameter: 'waist_slim',
          occlusionScale: 0.4,
          occlusionReason: 'arm overlap',
        ),
      ],
      qualityProfile: WarpQualityProfile.preview,
      occlusionDecisions: const [
        OcclusionDecision(
          parameter: 'chest_expand',
          type: BodyAdjustmentType.chestExpand,
          action: OcclusionAction.rejected,
          reason: 'hand',
        ),
      ],
      capabilityDecisions: const [
        CapabilityGateDecision(
          parameter: 'height',
          type: BodyAdjustmentType.height,
          action: CapabilityGateAction.reduced,
          reason: 'partial pose',
          intensityScale: 0.5,
        ),
      ],
    );

    expect(
      BodyReshapeLabels.limitationHint(
        parameterKey: 'chest_expand',
        plan: plan,
      ),
      BodyReshapeLabels.rejectedByOcclusion,
    );
    expect(
      BodyReshapeLabels.limitationHint(
        parameterKey: 'height',
        plan: plan,
      ),
      BodyReshapeLabels.limitedByCapability,
    );
    expect(
      BodyReshapeLabels.limitationHint(
        parameterKey: 'waist_slim',
        plan: plan,
      ),
      BodyReshapeLabels.limitedByOcclusion,
    );
    expect(
      BodyReshapeLabels.controlLimitHint('height'),
      contains('bloqueia'),
    );
  });

  test('every supported key has a Portuguese label', () {
    for (final key in LegacyBodyParameterAdapter.supportedParameterKeys) {
      expect(
        BodyReshapeLabels.parameterLabel(key),
        isNot(equals(key)),
        reason: key,
      );
    }
  });
}
