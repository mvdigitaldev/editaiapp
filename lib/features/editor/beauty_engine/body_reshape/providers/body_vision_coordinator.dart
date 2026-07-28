import '../../models/image_source.dart';
import '../models/body_frame_assets.dart';
import 'background_analysis_provider.dart';
import 'body_mesh_provider.dart';
import 'body_part_segmentation_provider.dart';
import 'instance_selection_policy.dart';
import 'occlusion_provider.dart';
import 'person_matte_provider.dart';
import 'vision_capabilities.dart';

/// Orquestra providers de visão em um único [BodyFrameAssets].
class BodyVisionCoordinator {
  BodyVisionCoordinator({
    required this.bodyMeshProvider,
    required this.personMatteProvider,
    required this.bodyPartSegmentationProvider,
    required this.occlusionProvider,
    required this.backgroundAnalysisProvider,
    this.instanceSelectionPolicy = const InstanceSelectionPolicy(),
  });

  final BodyMeshProvider bodyMeshProvider;
  final PersonMatteProvider personMatteProvider;
  final BodyPartSegmentationProvider bodyPartSegmentationProvider;
  final OcclusionProvider occlusionProvider;
  final BackgroundAnalysisProvider backgroundAnalysisProvider;
  final InstanceSelectionPolicy instanceSelectionPolicy;

  VisionCapabilities get capabilities => bodyMeshProvider.capabilities
      .merge(personMatteProvider.capabilities)
      .merge(bodyPartSegmentationProvider.capabilities)
      .merge(occlusionProvider.capabilities)
      .merge(backgroundAnalysisProvider.capabilities);

  /// Carrega landmarks e enriquece com matte/partes/oclusão/fundo quando houver.
  Future<BodyFrameAssets?> load(ImageSource source) async {
    final mesh = await bodyMeshProvider.detect(source);
    if (mesh == null) {
      return null;
    }

    final matte = await personMatteProvider.detect(source);
    final parts = await bodyPartSegmentationProvider.detect(source);
    final occlusion = await occlusionProvider.detect(source);
    final background = await backgroundAnalysisProvider.analyze(source);

    return mesh.copyWith(
      capabilities: capabilities,
      personMatte: matte,
      partSegmentation: parts,
      occlusionMap: occlusion,
      backgroundAnalysis: background,
    );
  }

  /// Escolhe explicitamente a pessoa alvo para providers multi-pessoa.
  ///
  /// O provider MediaPipe atual entrega uma pessoa por vez; esse método mantém
  /// a política fora do Warp Engine quando um provider futuro entregar várias.
  BodyFrameAssets? selectTarget(Iterable<BodyFrameAssets> candidates) =>
      instanceSelectionPolicy.select(candidates);
}
