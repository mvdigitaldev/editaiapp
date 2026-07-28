import '../../models/image_source.dart';
import '../models/body_part_segmentation.dart';
import 'vision_capabilities.dart';

/// Segmentação por partes corporais (opcional até Sprint 14).
abstract class BodyPartSegmentationProvider {
  String get id;

  VisionCapabilities get capabilities;

  Future<BodyPartSegmentation?> detect(ImageSource source);
}
