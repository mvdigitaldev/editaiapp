import '../../models/image_source.dart';
import '../models/body_frame_assets.dart';
import 'vision_capabilities.dart';

/// Fonte de landmarks corporais semânticos para o Warp Engine.
abstract class BodyMeshProvider {
  String get id;

  VisionCapabilities get capabilities;

  Future<BodyFrameAssets?> detect(ImageSource source);
}
