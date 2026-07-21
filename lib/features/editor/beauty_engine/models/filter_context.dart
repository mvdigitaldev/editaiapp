import '../filters/beauty_filter.dart';
import '../rendering/gpu_renderer.dart';
import '../rendering/texture_handle.dart';
import '../warp/warp_engine.dart';
import 'face_mesh_result.dart';
import 'pose_result.dart';
import 'tri_mesh.dart';

/// Contexto passado a cada [BeautyFilter] durante o pipeline.
class FilterContext {
  final FaceMeshResult? face;
  final PoseResult? pose;
  final TriMesh? mesh;
  final WarpEngine warpEngine;
  final GPURenderer renderer;
  final TextureHandle inputTexture;
  final Map<String, double> parameters;

  const FilterContext({
    this.face,
    this.pose,
    this.mesh,
    required this.warpEngine,
    required this.renderer,
    required this.inputTexture,
    this.parameters = const {},
  });
}
