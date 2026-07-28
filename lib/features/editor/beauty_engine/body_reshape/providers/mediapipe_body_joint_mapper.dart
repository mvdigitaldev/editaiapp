import 'dart:ui';

import '../../models/pose_result.dart';
import '../models/body_frame_assets.dart';
import '../models/body_joint.dart';
import 'vision_capabilities.dart';

/// Converte [PoseResult] legado (índices MediaPipe) em joints semânticos.
class MediaPipeBodyJointMapper {
  const MediaPipeBodyJointMapper();

  static const providerId = 'mediapipe_pose';

  /// Ordem oficial MediaPipe Pose Landmarker (33 pontos).
  static const jointByIndex = <BodyJoint>[
    BodyJoint.nose,
    BodyJoint.leftEyeInner,
    BodyJoint.leftEye,
    BodyJoint.leftEyeOuter,
    BodyJoint.rightEyeInner,
    BodyJoint.rightEye,
    BodyJoint.rightEyeOuter,
    BodyJoint.leftEar,
    BodyJoint.rightEar,
    BodyJoint.leftMouth,
    BodyJoint.rightMouth,
    BodyJoint.leftShoulder,
    BodyJoint.rightShoulder,
    BodyJoint.leftElbow,
    BodyJoint.rightElbow,
    BodyJoint.leftWrist,
    BodyJoint.rightWrist,
    BodyJoint.leftPinky,
    BodyJoint.rightPinky,
    BodyJoint.leftIndex,
    BodyJoint.rightIndex,
    BodyJoint.leftThumb,
    BodyJoint.rightThumb,
    BodyJoint.leftHip,
    BodyJoint.rightHip,
    BodyJoint.leftKnee,
    BodyJoint.rightKnee,
    BodyJoint.leftAnkle,
    BodyJoint.rightAnkle,
    BodyJoint.leftHeel,
    BodyJoint.rightHeel,
    BodyJoint.leftFootIndex,
    BodyJoint.rightFootIndex,
  ];

  static const primaryJoints = <BodyJoint>{
    BodyJoint.leftShoulder,
    BodyJoint.rightShoulder,
    BodyJoint.leftHip,
    BodyJoint.rightHip,
  };

  BodyFrameAssets? fromPoseResult(
    PoseResult pose, {
    VisionCapabilities capabilities = VisionCapabilities.mediapipePoseOnly,
  }) {
    if (pose.landmarks.length != jointByIndex.length) {
      return null;
    }

    final landmarks = <BodyJoint, BodyLandmark>{};
    for (final landmark in pose.landmarks) {
      if (landmark.index < 0 || landmark.index >= jointByIndex.length) {
        continue;
      }
      final joint = jointByIndex[landmark.index];
      landmarks[joint] = BodyLandmark(
        joint: joint,
        normalized: Offset(
          landmark.normalized.dx.clamp(0.0, 1.0),
          landmark.normalized.dy.clamp(0.0, 1.0),
        ),
        confidence: landmark.visibility.clamp(0.0, 1.0),
      );
    }

    if (!_hasVisiblePrimary(landmarks)) {
      return null;
    }

    return BodyFrameAssets(
      landmarks: landmarks,
      boundingBox: pose.boundingBox,
      isPartial: pose.isPartial,
      providerId: providerId,
      confidence: _meanConfidence(landmarks),
      capabilities: capabilities,
    );
  }

  bool _hasVisiblePrimary(Map<BodyJoint, BodyLandmark> landmarks) {
    for (final joint in primaryJoints) {
      final point = landmarks[joint];
      if (point != null && point.confidence >= 0.5) {
        return true;
      }
    }
    return false;
  }

  double _meanConfidence(Map<BodyJoint, BodyLandmark> landmarks) {
    if (landmarks.isEmpty) {
      return 0;
    }
    var total = 0.0;
    for (final point in landmarks.values) {
      total += point.confidence;
    }
    return (total / landmarks.length).clamp(0.0, 1.0);
  }
}
