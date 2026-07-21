import 'package:beauty_mediapipe/beauty_mediapipe.dart';

/// Inicialização única dos modelos Face + Pose no plugin nativo.
class MediapipeInitCoordinator {
  MediapipeInitCoordinator({
    required BeautyMediapipeBindings bindings,
    required Future<String> Function() resolveFaceModelPath,
    required Future<String> Function() resolvePoseModelPath,
  })  : _bindings = bindings,
        _resolveFaceModelPath = resolveFaceModelPath,
        _resolvePoseModelPath = resolvePoseModelPath;

  final BeautyMediapipeBindings _bindings;
  final Future<String> Function() _resolveFaceModelPath;
  final Future<String> Function() _resolvePoseModelPath;

  bool _initialized = false;
  Future<void>? _initFuture;

  Future<void> ensureInitialized() {
    if (_initialized) {
      return Future<void>.value();
    }
    return _initFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      final facePath = await _resolveFaceModelPath();
      final posePath = await _resolvePoseModelPath();
      await _bindings.initialize(
        faceModelPath: facePath,
        poseModelPath: posePath,
      );
      _initialized = true;
    } catch (_) {
      _initFuture = null;
      rethrow;
    }
  }
}
