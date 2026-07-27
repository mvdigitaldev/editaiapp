import 'package:beauty_mediapipe/beauty_mediapipe.dart';

import '../di/mediapipe_init_coordinator.dart';
import '../models/image_source.dart';
import 'person_mask.dart';

/// Implementação MediaPipe Image Segmenter via plugin nativo.
class PersonMaskDetectorImpl implements PersonMaskDetector {
  PersonMaskDetectorImpl({
    required BeautyMediapipeBindings bindings,
    required MediapipeInitCoordinator coordinator,
  })  : _bindings = bindings,
        _coordinator = coordinator;

  final BeautyMediapipeBindings _bindings;
  final MediapipeInitCoordinator _coordinator;

  @override
  Future<PersonMask?> detect(ImageSource source) async {
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

    final native = await _bindings.detectPersonMask(buffer);
    if (native == null) {
      return null;
    }

    return PersonMask(
      bytes: native.bytes,
      width: native.width,
      height: native.height,
    );
  }
}
