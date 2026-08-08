import 'package:beauty_mediapipe/beauty_mediapipe.dart';

/// Inicialização única dos modelos Face + Pose + Segmenter no plugin nativo.
class MediapipeInitCoordinator {
  MediapipeInitCoordinator({
    required BeautyMediapipeBindings bindings,
    required Future<String> Function() resolveFaceModelPath,
    required Future<String> Function() resolvePoseModelPath,
    Future<String> Function()? resolveSegmenterModelPath,
    Future<String> Function()? resolveFacePartsModelPath,
  })  : _bindings = bindings,
        _resolveFaceModelPath = resolveFaceModelPath,
        _resolvePoseModelPath = resolvePoseModelPath,
        _resolveSegmenterModelPath = resolveSegmenterModelPath,
        _resolveFacePartsModelPath = resolveFacePartsModelPath;

  final BeautyMediapipeBindings _bindings;
  final Future<String> Function() _resolveFaceModelPath;
  final Future<String> Function() _resolvePoseModelPath;
  final Future<String> Function()? _resolveSegmenterModelPath;
  final Future<String> Function()? _resolveFacePartsModelPath;

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
      final segmenterPath = _resolveSegmenterModelPath == null
          ? null
          : await _resolveSegmenterModelPath!();
      // O modelo multiclass é opcional: se o asset não estiver no bundle, a
      // pele usa a máscara geométrica dos landmarks.
      String? facePartsPath;
      if (_resolveFacePartsModelPath != null) {
        try {
          facePartsPath = await _resolveFacePartsModelPath!();
        } catch (_) {
          facePartsPath = null;
        }
      }
      await _bindings.initialize(
        faceModelPath: facePath,
        poseModelPath: posePath,
        segmenterModelPath: segmenterPath,
        facePartsModelPath: facePartsPath,
      );
      _initialized = true;
    } catch (_) {
      _initFuture = null;
      rethrow;
    }
  }
}
