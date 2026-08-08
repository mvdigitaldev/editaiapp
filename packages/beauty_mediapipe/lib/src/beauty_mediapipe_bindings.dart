import 'dart:typed_data';

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

/// Máscara de pessoa (1 canal uint8, 0–255) do Image Segmenter.
class PersonMaskNativeResult {
  final Uint8List bytes;
  final int width;
  final int height;

  const PersonMaskNativeResult({
    required this.bytes,
    required this.width,
    required this.height,
  });
}

/// Máscara de categorias por pixel do segmenter multiclass — um byte com o
/// índice da classe (background/hair/body-skin/face-skin/clothes/others).
class FacePartsNativeResult {
  final Uint8List classes;
  final int width;
  final int height;

  const FacePartsNativeResult({
    required this.classes,
    required this.width,
    required this.height,
  });
}

/// Máscara categórica BiSeNet 19 classes na resolução da foto (R8 por pixel).
class FaceParsingNativeResult {
  final Uint8List classes;
  final int width;
  final int height;

  const FaceParsingNativeResult({
    required this.classes,
    required this.width,
    required this.height,
  });
}

/// Bindings MediaPipe — implementação via MethodChannel.
abstract class BeautyMediapipeBindings {
  Future<void> initialize({
    required String faceModelPath,
    String? poseModelPath,
    String? segmenterModelPath,
    String? facePartsModelPath,
  });

  Future<FaceLandmarkerNativeResult?> detectFace(NativeImageBuffer buffer);

  /// Até 5 rostos — ordenados do maior para o menor bbox no Dart.
  Future<List<FaceLandmarkerNativeResult>> detectFaces(NativeImageBuffer buffer);

  Future<PoseLandmarkerNativeResult?> detectPose(NativeImageBuffer buffer);

  Future<PersonMaskNativeResult?> detectPersonMask(NativeImageBuffer buffer);

  Future<FacePartsNativeResult?> detectFaceParts(NativeImageBuffer buffer);

  /// BiSeNet 19 classes — retorna `null` até o modelo estar no asset (Sprint 4).
  Future<FaceParsingNativeResult?> detectFaceParsing(NativeImageBuffer buffer);

  void dispose();
}
