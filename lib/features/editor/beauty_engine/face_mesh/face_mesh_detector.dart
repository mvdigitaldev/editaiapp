import '../models/face_mesh_result.dart';
import '../models/image_source.dart';

/// Detecção facial — sem dependência de UI.
abstract class FaceMeshDetector {
  /// Maior rosto detectado (compatibilidade com pipeline single-face).
  Future<FaceMeshResult?> detect(ImageSource source);

  /// Até [MultiFaceDetection.maxFaces] rostos na foto.
  Future<List<FaceMeshResult>> detectAll(ImageSource source);
}
