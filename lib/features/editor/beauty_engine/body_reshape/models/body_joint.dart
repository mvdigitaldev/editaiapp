import 'dart:ui';

/// Articulações corporais semânticas, independentes do índice do provider.
enum BodyJoint {
  nose,
  leftEyeInner,
  leftEye,
  leftEyeOuter,
  rightEyeInner,
  rightEye,
  rightEyeOuter,
  leftEar,
  rightEar,
  leftMouth,
  rightMouth,
  leftShoulder,
  rightShoulder,
  leftElbow,
  rightElbow,
  leftWrist,
  rightWrist,
  leftPinky,
  rightPinky,
  leftIndex,
  rightIndex,
  leftThumb,
  rightThumb,
  leftHip,
  rightHip,
  leftKnee,
  rightKnee,
  leftAnkle,
  rightAnkle,
  leftHeel,
  rightHeel,
  leftFootIndex,
  rightFootIndex,
}

/// Ponto corporal normalizado entregue por qualquer [BodyMeshProvider].
class BodyLandmark {
  final BodyJoint joint;
  final Offset normalized;
  final double confidence;
  final double? depth;

  const BodyLandmark({
    required this.joint,
    required this.normalized,
    this.confidence = 1,
    this.depth,
  }) : assert(confidence >= 0 && confidence <= 1);
}
