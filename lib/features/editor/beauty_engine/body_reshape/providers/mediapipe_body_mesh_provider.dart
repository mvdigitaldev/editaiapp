import '../../models/image_source.dart';
import '../../pose/pose_detector.dart';
import '../models/body_frame_assets.dart';
import 'body_mesh_provider.dart';
import 'mediapipe_body_joint_mapper.dart';
import 'vision_capabilities.dart';

/// Adaptador MediaPipe: [PoseDetector] legado → [BodyMeshProvider] semântico.
class MediaPipeBodyMeshProvider implements BodyMeshProvider {
  MediaPipeBodyMeshProvider({
    required PoseDetector poseDetector,
    MediaPipeBodyJointMapper mapper = const MediaPipeBodyJointMapper(),
  })  : _poseDetector = poseDetector,
        _mapper = mapper;

  final PoseDetector _poseDetector;
  final MediaPipeBodyJointMapper _mapper;

  @override
  String get id => MediaPipeBodyJointMapper.providerId;

  @override
  VisionCapabilities get capabilities => VisionCapabilities.mediapipePoseOnly;

  @override
  Future<BodyFrameAssets?> detect(ImageSource source) async {
    final pose = await _poseDetector.detect(source);
    if (pose == null) {
      return null;
    }
    return _mapper.fromPoseResult(
      pose,
      capabilities: capabilities,
    );
  }
}
