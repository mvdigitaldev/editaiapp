import 'package:beauty_mediapipe/beauty_mediapipe.dart';

import '../di/mediapipe_init_coordinator.dart';
import '../models/image_source.dart';
import 'face_parts_segmentation.dart';

/// Detector de segmentação semântica de partes (pele/cabelo/roupa/fundo).
abstract class FacePartsDetector {
  Future<FacePartsSegmentation?> detect(ImageSource source);
}

/// Implementação MediaPipe (category mask do `selfie_multiclass_256x256`).
class FacePartsDetectorImpl implements FacePartsDetector {
  FacePartsDetectorImpl({
    required BeautyMediapipeBindings bindings,
    required MediapipeInitCoordinator coordinator,
  })  : _bindings = bindings,
        _coordinator = coordinator;

  final BeautyMediapipeBindings _bindings;
  final MediapipeInitCoordinator _coordinator;

  @override
  Future<FacePartsSegmentation?> detect(ImageSource source) async {
    try {
      await _coordinator.ensureInitialized();
    } catch (_) {
      return null;
    }

    final native = await _bindings.detectFaceParts(
      NativeImageBuffer(
        bytes: source.bytes,
        width: source.width,
        height: source.height,
        rotation: source.rotation,
      ),
    );
    if (native == null) {
      return null;
    }

    return FacePartsSegmentation(
      classes: native.classes,
      width: native.width,
      height: native.height,
    );
  }
}

/// Stub para plataformas sem MediaPipe nativo (desktop/web/testes).
class FacePartsDetectorStub implements FacePartsDetector {
  const FacePartsDetectorStub();

  @override
  Future<FacePartsSegmentation?> detect(ImageSource source) async => null;
}
