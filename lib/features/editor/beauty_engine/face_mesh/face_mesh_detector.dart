import '../models/face_mesh_result.dart';
import '../models/image_source.dart';

/// Detecção facial — sem dependência de UI.
abstract class FaceMeshDetector {
  Future<FaceMeshResult?> detect(ImageSource source);
}
