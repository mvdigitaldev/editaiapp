import 'package:beauty_mediapipe/beauty_mediapipe.dart';

import '../di/mediapipe_init_coordinator.dart';
import '../models/image_source.dart';
import '../models/pose_result.dart';
import 'pose_detector.dart';
import 'pose_landmark_mapper.dart';

/// Implementação MediaPipe via plugin nativo (Android + iOS).
class PoseDetectorImpl implements PoseDetector {
  PoseDetectorImpl({
    required BeautyMediapipeBindings bindings,
    required MediapipeInitCoordinator coordinator,
  })  : _bindings = bindings,
        _coordinator = coordinator;

  final BeautyMediapipeBindings _bindings;
  final MediapipeInitCoordinator _coordinator;

  @override
  Future<PoseResult?> detect(ImageSource source) async {
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

    final native = await _bindings.detectPose(buffer);
    if (native == null) {
      return null;
    }

    return PoseLandmarkMapper.toPoseResult(native);
  }
}
