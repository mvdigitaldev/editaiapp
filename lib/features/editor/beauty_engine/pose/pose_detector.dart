import '../models/image_source.dart';
import '../models/pose_result.dart';

/// Detecção corporal — sem dependência de UI.
abstract class PoseDetector {
  Future<PoseResult?> detect(ImageSource source);
}
