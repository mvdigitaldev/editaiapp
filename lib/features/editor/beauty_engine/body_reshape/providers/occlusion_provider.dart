import '../../models/image_source.dart';
import '../models/occlusion_map.dart';
import 'vision_capabilities.dart';

/// Mapa de oclusão (mão/braço/cabelo à frente).
abstract class OcclusionProvider {
  String get id;

  VisionCapabilities get capabilities;

  Future<OcclusionMap?> detect(ImageSource source);
}
