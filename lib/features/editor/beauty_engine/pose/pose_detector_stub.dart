import '../models/image_source.dart';
import '../models/pose_result.dart';
import 'pose_detector.dart';

/// Stub até Sprint 04 (MediaPipe Pose FFI).
class PoseDetectorStub implements PoseDetector {
  const PoseDetectorStub();

  @override
  Future<PoseResult?> detect(ImageSource source) async {
    return null;
  }
}
