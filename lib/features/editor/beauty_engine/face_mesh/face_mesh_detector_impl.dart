import 'package:beauty_mediapipe/beauty_mediapipe.dart';

import '../models/face_mesh_result.dart';
import '../models/image_source.dart';
import '../models/multi_face_detection.dart';
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
    final faces = await detectAll(source);
    return MultiFaceDetection.primaryFace(faces);
  }

  @override
  Future<List<FaceMeshResult>> detectAll(ImageSource source) async {
    try {
      await _coordinator.ensureInitialized();
    } catch (_) {
      return const [];
    }

    final buffer = NativeImageBuffer(
      bytes: source.bytes,
      width: source.width,
      height: source.height,
      rotation: source.rotation,
    );

    List<FaceLandmarkerNativeResult> natives;
    try {
      natives = await _bindings.detectFaces(buffer);
    } catch (_) {
      final single = await _bindings.detectFace(buffer);
      natives = single == null ? const [] : [single];
    }
    final faces = <FaceMeshResult>[];
    for (final native in natives) {
      final mapped = FaceLandmarkMapper.toFaceMeshResult(native);
      if (mapped != null) {
        faces.add(mapped);
      }
    }
    if (faces.isEmpty) {
      return const [];
    }
    faces.sort(
      (a, b) => (b.boundingBox.width * b.boundingBox.height)
          .compareTo(a.boundingBox.width * a.boundingBox.height),
    );
    return faces;
  }
}
