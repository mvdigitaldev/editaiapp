import 'dart:typed_data';

import '../models/body_part_segmentation.dart';
import '../models/occlusion_map.dart' as model;
import 'occlusion_map.dart';

/// Converte segmentação de partes em uma evidência de oclusão preservável.
///
/// Não decide profundidade nem carrega um modelo: esse contrato recebe o mapa
/// de partes de qualquer provider e protege apenas braços, mãos e cabelo.
class PartOcclusionMap {
  const PartOcclusionMap._();

  static OcclusionField fromSegmentation(
    BodyPartSegmentation segmentation, {
    double minimumConfidence = 0.5,
  }) {
    if (segmentation.isEmpty ||
        segmentation.labels.length !=
            segmentation.width * segmentation.height) {
      return OcclusionField.fromMap(
        model.OcclusionMap(
          weights: Uint8List(0),
          width: 0,
          height: 0,
          providerId: segmentation.providerId,
          confidence: 0,
        ),
        reason: 'part_segmentation_invalid',
      );
    }

    final weights = Uint8List(segmentation.labels.length);
    final codes = Uint8List(segmentation.labels.length);
    final kinds = <OccluderKind>{};
    var confidenceTotal = 0.0;
    var confidenceCount = 0;

    for (var i = 0; i < segmentation.labels.length; i++) {
      final raw = segmentation.labels[i];
      if (raw >= BodyPartLabel.values.length) {
        continue;
      }
      final label = BodyPartLabel.values[raw];
      final kind = _kindFor(label);
      if (kind == null) {
        continue;
      }
      final confidence = segmentation.confidences[label] ?? 1;
      if (confidence < minimumConfidence) {
        continue;
      }
      weights[i] = 255;
      codes[i] = OcclusionField.codeFor(kind);
      kinds.add(kind);
      confidenceTotal += confidence;
      confidenceCount++;
    }

    return OcclusionField.fromMap(
      model.OcclusionMap(
        weights: weights,
        width: segmentation.width,
        height: segmentation.height,
        providerId: '${segmentation.providerId}_parts',
        confidence:
            confidenceCount == 0 ? 0 : confidenceTotal / confidenceCount,
      ),
      kindCodes: codes,
      presentKinds: kinds,
      reason: 'part_segmentation',
    );
  }

  static OccluderKind? _kindFor(BodyPartLabel label) => switch (label) {
        BodyPartLabel.leftHand => OccluderKind.leftHand,
        BodyPartLabel.rightHand => OccluderKind.rightHand,
        BodyPartLabel.leftArm ||
        BodyPartLabel.leftForearm =>
          OccluderKind.leftArm,
        BodyPartLabel.rightArm ||
        BodyPartLabel.rightForearm =>
          OccluderKind.rightArm,
        BodyPartLabel.hair => OccluderKind.hair,
        _ => null,
      };
}
