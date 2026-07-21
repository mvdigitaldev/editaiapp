import 'native_image_buffer.dart';

/// Landmark individual retornado pelo nativo.
class NativeFaceLandmark {
  final int index;
  final double x;
  final double y;
  final double z;
  final double visibility;

  const NativeFaceLandmark({
    required this.index,
    required this.x,
    required this.y,
    required this.z,
    required this.visibility,
  });
}

/// Resultado nativo face landmarker.
class FaceLandmarkerNativeResult {
  final List<NativeFaceLandmark> landmarks;
  final double confidence;
  final double bboxLeft;
  final double bboxTop;
  final double bboxRight;
  final double bboxBottom;

  const FaceLandmarkerNativeResult({
    required this.landmarks,
    required this.confidence,
    required this.bboxLeft,
    required this.bboxTop,
    required this.bboxRight,
    required this.bboxBottom,
  });
}

/// Landmark corporal retornado pelo nativo.
class NativePoseLandmark {
  final int index;
  final double x;
  final double y;
  final double z;
  final double visibility;

  const NativePoseLandmark({
    required this.index,
    required this.x,
    required this.y,
    required this.z,
    required this.visibility,
  });
}

/// Resultado nativo pose landmarker.
class PoseLandmarkerNativeResult {
  final List<NativePoseLandmark> landmarks;
  final double bboxLeft;
  final double bboxTop;
  final double bboxRight;
  final double bboxBottom;

  const PoseLandmarkerNativeResult({
    required this.landmarks,
    required this.bboxLeft,
    required this.bboxTop,
    required this.bboxRight,
    required this.bboxBottom,
  });
}

/// Bindings MediaPipe — implementação via MethodChannel.
abstract class BeautyMediapipeBindings {
  Future<void> initialize({
    required String faceModelPath,
    String? poseModelPath,
  });

  Future<FaceLandmarkerNativeResult?> detectFace(NativeImageBuffer buffer);

  Future<PoseLandmarkerNativeResult?> detectPose(NativeImageBuffer buffer);

  void dispose();
}
