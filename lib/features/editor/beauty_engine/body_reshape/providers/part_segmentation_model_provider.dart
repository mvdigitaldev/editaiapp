import '../../models/image_source.dart';
import '../models/body_part_segmentation.dart';
import 'body_part_segmentation_provider.dart';
import 'vision_capabilities.dart';

/// Adapter para qualquer modelo nativo/remoto de segmentação por partes.
///
/// O Sprint 14 não fixa um SDK ou modelo antes do benchmark de qualidade,
/// licença e latência. A função [detectParts] é o único ponto de integração.
class PartSegmentationModelProvider implements BodyPartSegmentationProvider {
  const PartSegmentationModelProvider({
    required this.detectParts,
    this.id = 'part_segmentation_model',
  });

  final Future<BodyPartSegmentation?> Function(ImageSource source) detectParts;

  @override
  final String id;

  @override
  VisionCapabilities get capabilities =>
      const VisionCapabilities(bodyPartSegmentation: true, multiPerson: true);

  @override
  Future<BodyPartSegmentation?> detect(ImageSource source) async {
    final result = await detectParts(source);
    if (result == null ||
        result.isEmpty ||
        result.labels.length != result.width * result.height) {
      return null;
    }
    return result;
  }
}
