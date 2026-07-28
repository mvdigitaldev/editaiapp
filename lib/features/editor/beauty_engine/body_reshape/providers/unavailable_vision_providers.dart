import '../../models/image_source.dart';
import '../models/background_analysis.dart';
import '../models/body_frame_assets.dart';
import '../models/body_part_segmentation.dart';
import '../models/occlusion_map.dart';
import '../models/person_matte.dart';
import 'background_analysis_provider.dart';
import 'body_mesh_provider.dart';
import 'body_part_segmentation_provider.dart';
import 'occlusion_provider.dart';
import 'person_matte_provider.dart';
import 'vision_capabilities.dart';

/// Provider que declara ausência explícita de uma capacidade.
class UnavailableBodyMeshProvider implements BodyMeshProvider {
  const UnavailableBodyMeshProvider();

  @override
  String get id => 'unavailable_body_mesh';

  @override
  VisionCapabilities get capabilities => VisionCapabilities.none;

  @override
  Future<BodyFrameAssets?> detect(ImageSource source) async => null;
}

class UnavailablePersonMatteProvider implements PersonMatteProvider {
  const UnavailablePersonMatteProvider();

  @override
  String get id => 'unavailable_person_matte';

  @override
  VisionCapabilities get capabilities => VisionCapabilities.none;

  @override
  Future<PersonMatte?> detect(ImageSource source) async => null;
}

class UnavailableBodyPartSegmentationProvider
    implements BodyPartSegmentationProvider {
  const UnavailableBodyPartSegmentationProvider();

  @override
  String get id => 'unavailable_body_parts';

  @override
  VisionCapabilities get capabilities => VisionCapabilities.none;

  @override
  Future<BodyPartSegmentation?> detect(ImageSource source) async => null;
}

class UnavailableOcclusionProvider implements OcclusionProvider {
  const UnavailableOcclusionProvider();

  @override
  String get id => 'unavailable_occlusion';

  @override
  VisionCapabilities get capabilities => VisionCapabilities.none;

  @override
  Future<OcclusionMap?> detect(ImageSource source) async => null;
}

class UnavailableBackgroundAnalysisProvider
    implements BackgroundAnalysisProvider {
  const UnavailableBackgroundAnalysisProvider();

  @override
  String get id => 'unavailable_background';

  @override
  VisionCapabilities get capabilities => VisionCapabilities.none;

  @override
  Future<BackgroundAnalysis?> analyze(ImageSource source) async => null;
}
