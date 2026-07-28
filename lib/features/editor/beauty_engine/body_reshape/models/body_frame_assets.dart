import 'dart:ui';

import 'body_joint.dart';

/// Dados semânticos de uma pessoa necessários para planejar a deformação.
///
/// Matte, partes e mapas de oclusão serão adicionados pelos providers sem
/// alterar o contrato de landmarks usado pelas estratégias corporais.
class BodyFrameAssets {
  final Map<BodyJoint, BodyLandmark> landmarks;
  final Rect boundingBox;
  final bool isPartial;
  final String providerId;
  final double confidence;

  const BodyFrameAssets({
    required this.landmarks,
    required this.boundingBox,
    required this.providerId,
    this.isPartial = false,
    this.confidence = 1,
  }) : assert(confidence >= 0 && confidence <= 1);

  BodyLandmark? landmark(BodyJoint joint) => landmarks[joint];

  bool containsAll(Iterable<BodyJoint> joints) {
    return joints.every(landmarks.containsKey);
  }

  double confidenceFor(Iterable<BodyJoint> joints) {
    var total = 0.0;
    var count = 0;
    for (final joint in joints) {
      final point = landmarks[joint];
      if (point == null) {
        return 0;
      }
      total += point.confidence;
      count++;
    }
    return count == 0 ? confidence : total / count;
  }
}
