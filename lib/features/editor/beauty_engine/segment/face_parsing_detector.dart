import 'package:beauty_mediapipe/beauty_mediapipe.dart';

import '../di/mediapipe_init_coordinator.dart';
import '../models/face_mesh_result.dart';
import '../models/image_source.dart';
import 'face_parts_detector.dart';
import 'face_parts_segmentation.dart';
import 'face_parsing_mapper.dart';
import 'face_parsing_result.dart';
import 'parsing_fallback_policy.dart';

/// Detecta face parsing 19 classes (BiSeNet ou mapper multiclass + landmarks).
abstract class FaceParsingDetector {
  Future<FaceParsingResult?> detect({
    required ImageSource source,
    FaceMeshResult? face,
    FacePartsSegmentation? parts,
  });
}

/// Implementação com BiSeNet nativo (quando disponível) + fallback mapper.
class FaceParsingDetectorImpl implements FaceParsingDetector {
  FaceParsingDetectorImpl({
    required BeautyMediapipeBindings bindings,
    required MediapipeInitCoordinator coordinator,
    FacePartsDetector? facePartsDetector,
  })  : _bindings = bindings,
        _coordinator = coordinator,
        _facePartsDetector = facePartsDetector;

  final BeautyMediapipeBindings _bindings;
  final MediapipeInitCoordinator _coordinator;
  final FacePartsDetector? _facePartsDetector;

  @override
  Future<FaceParsingResult?> detect({
    required ImageSource source,
    FaceMeshResult? face,
    FacePartsSegmentation? parts,
  }) async {
    if (face == null) return null;

    try {
      await _coordinator.ensureInitialized();
    } catch (_) {
      return _mapFallback(source: source, face: face, parts: parts);
    }

    final native = await _bindings.detectFaceParsing(
      NativeImageBuffer(
        bytes: source.bytes,
        width: source.width,
        height: source.height,
        rotation: source.rotation,
      ),
    );

    if (native != null &&
        native.classes.length == source.width * source.height) {
      return FaceParsingResult(
        classes: native.classes,
        width: source.width,
        height: source.height,
        source: FaceParsingSource.bisenet,
        confidence: 1,
      );
    }

    final resolvedParts = parts ?? await _facePartsDetector?.detect(source);
    return _mapFallback(source: source, face: face, parts: resolvedParts);
  }

  FaceParsingResult _mapFallback({
    required ImageSource source,
    required FaceMeshResult face,
    FacePartsSegmentation? parts,
  }) {
    return FaceParsingMapper.build(
      width: source.width,
      height: source.height,
      parts: parts,
      face: face,
    );
  }
}

/// Mapper puro — sem bridge nativo (desktop/web/testes).
class FaceParsingDetectorStub implements FaceParsingDetector {
  const FaceParsingDetectorStub();

  @override
  Future<FaceParsingResult?> detect({
    required ImageSource source,
    FaceMeshResult? face,
    FacePartsSegmentation? parts,
  }) async {
    if (face == null) return null;
    return FaceParsingMapper.build(
      width: source.width,
      height: source.height,
      parts: parts,
      face: face,
    );
  }
}
