import 'package:beauty_mediapipe/beauty_mediapipe.dart';

import '../models/face_mesh_result.dart';
import '../models/image_source.dart';
import 'face_landmark_mapper.dart';
import 'face_mesh_detector.dart';
import '../di/mediapipe_init_coordinator.dart';

/// Implementação MediaPipe via plugin nativo (Android + iOS).
class FaceMeshDetectorImpl implements FaceMeshDetector {
  FaceMeshDetectorImpl({
    required BeautyMediapipeBindings bindings,
    required MediapipeInitCoordinator coordinator,
  })  : _bindings = bindings,
        _coordinator = coordinator;

  final BeautyMediapipeBindings _bindings;
  final MediapipeInitCoordinator _coordinator;

  @override
  Future<FaceMeshResult?> detect(ImageSource source) async {
    try {
      await _coordinator.ensureInitialized();
    } catch (_) {
      return null;
    }

    final buffer = NativeImageBuffer(
      bytes: source.bytes,
      width: source.width,
      height: source.height,
      rotation: source.rotation,
    );

    final native = await _bindings.detectFace(buffer);
    if (native == null) {
      return null;
    }

    return FaceLandmarkMapper.toFaceMeshResult(native);
  }
}
