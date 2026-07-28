import '../models/image_source.dart';
import '../models/pose_result.dart';

/// Detecção corporal legada (índices MediaPipe) — sem dependência de UI.
///
/// O Body Reshape V2 consome [BodyMeshProvider], que adapta este detector
/// (ou outro SDK) para joints semânticos sem acoplar o Warp Engine.
abstract class PoseDetector {
  Future<PoseResult?> detect(ImageSource source);
}
