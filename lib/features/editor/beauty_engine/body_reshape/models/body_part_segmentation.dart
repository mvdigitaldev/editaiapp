import 'dart:typed_data';

import 'body_region.dart';

/// Classes de partes corporais para segmentação futura.
enum BodyPartLabel {
  torso,
  waist,
  chest,
  hip,
  butt,
  leftArm,
  rightArm,
  leftForearm,
  rightForearm,
  leftThigh,
  rightThigh,
  leftCalf,
  rightCalf,
  neck,
  shoulders,
  leftHand,
  rightHand,
  hair,
  face,
  unknown,
}

/// Mapa de segmentos por parte (Sprint 2: contrato; Sprint 14: modelo real).
class BodyPartSegmentation {
  final Uint8List labels;
  final int width;
  final int height;
  final Map<BodyPartLabel, double> confidences;
  final String providerId;

  const BodyPartSegmentation({
    required this.labels,
    required this.width,
    required this.height,
    required this.providerId,
    this.confidences = const {},
  });

  bool get isEmpty => labels.isEmpty || width <= 0 || height <= 0;

  BodyRegion? regionForLabel(BodyPartLabel label) {
    return switch (label) {
      BodyPartLabel.torso => BodyRegion.torso,
      BodyPartLabel.waist => BodyRegion.waist,
      BodyPartLabel.chest => BodyRegion.chest,
      BodyPartLabel.hip => BodyRegion.hip,
      BodyPartLabel.butt => BodyRegion.butt,
      BodyPartLabel.leftArm => BodyRegion.leftArm,
      BodyPartLabel.rightArm => BodyRegion.rightArm,
      BodyPartLabel.leftForearm => BodyRegion.leftForearm,
      BodyPartLabel.rightForearm => BodyRegion.rightForearm,
      BodyPartLabel.leftThigh => BodyRegion.leftThigh,
      BodyPartLabel.rightThigh => BodyRegion.rightThigh,
      BodyPartLabel.leftCalf => BodyRegion.leftCalf,
      BodyPartLabel.rightCalf => BodyRegion.rightCalf,
      BodyPartLabel.neck => BodyRegion.neck,
      BodyPartLabel.shoulders => BodyRegion.shoulders,
      _ => null,
    };
  }
}
