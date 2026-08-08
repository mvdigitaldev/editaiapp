import '../models/face_mesh_result.dart';
import '../models/image_source.dart';
import '../models/multi_face_detection.dart';
import 'face_mesh_detector.dart';

/// Stub até Sprint 03 (MediaPipe FFI).
class FaceMeshDetectorStub implements FaceMeshDetector {
  const FaceMeshDetectorStub();

  @override
  Future<FaceMeshResult?> detect(ImageSource source) async {
    return null;
  }

  @override
  Future<List<FaceMeshResult>> detectAll(ImageSource source) async {
    return const [];
  }
}
