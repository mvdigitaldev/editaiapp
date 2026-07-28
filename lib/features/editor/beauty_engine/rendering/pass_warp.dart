import '../body_reshape/maps/influence_map.dart';
import '../body_reshape/protection/rigidity_map.dart';
import '../body_reshape/rendering/fragment_program_warp_backend.dart';
import '../body_reshape/rendering/render_plan.dart';
import '../models/warp_field.dart';
import '../warp/warp_cpu_remap.dart';
import 'render_pass.dart';
import 'render_target.dart';
import 'texture_handle.dart';

/// Pass 1: warp remap (MLS / Body Reshape field).
///
/// Preferência: [FragmentProgramWarpBackend] (GPU). Fallback: [WarpCpuRemap]
/// com anti-ghosting + rigidity (Sprint 11).
class PassWarp implements RenderPass {
  const PassWarp({
    WarpCpuRemap? remapper,
    FragmentProgramWarpBackend? warpBackend,
    bool preferGpu = true,
  })  : _remapper = remapper,
        _warpBackend = warpBackend,
        _preferGpu = preferGpu;

  final WarpCpuRemap? _remapper;
  final FragmentProgramWarpBackend? _warpBackend;
  final bool _preferGpu;

  @override
  String get shaderName => RenderShaders.warpRemap;

  @override
  Future<TextureHandle> execute(RenderPassContext context) async {
    final field = context.uniforms['warpField'] as WarpField?;
    final source = context.store.get(context.input.id);
    if (source == null) {
      return context.input;
    }

    if (field == null || field.isIdentity) {
      return context.pool.acquireCopy(context.input);
    }

    final influence = context.uniforms['influenceMap'] as InfluenceMap?;
    final protection = context.uniforms['protectionMap'] as RigidityMap? ??
        field.rigidityMap;
    final forceCpu = context.uniforms['forceCpu'] == true || !_preferGpu;
    final fastMode = context.uniforms['fastMode'] == true;
    final antiGhosting = context.uniforms['antiGhosting'] != false;

    if (!forceCpu) {
      final backend = _warpBackend ?? FragmentProgramWarpBackend.shared;
      final planUniform = context.uniforms['renderPlan'] as RenderPlan?;
      final warped = planUniform != null
          ? await backend.applyPlan(
              rgba: source.rgba,
              width: source.width,
              height: source.height,
              plan: planUniform,
            )
          : await backend.apply(
              rgba: source.rgba,
              width: source.width,
              height: source.height,
              field: field,
              influenceMap: influence,
              protectionMap: protection,
            );
      if (warped != null) {
        final entry = context.store.create(
          rgba: warped,
          width: source.width,
          height: source.height,
        );
        return context.store.toHandle(entry);
      }
    }

    final remapper = (_remapper ?? WarpCpuRemap(fastMode: fastMode)).copyWith(
      antiGhosting: antiGhosting,
      rigidityMap: protection,
      fastMode: fastMode,
    );
    final warped = remapper.apply(
      rgba: source.rgba,
      width: source.width,
      height: source.height,
      field: field,
    );

    final entry = context.store.create(
      rgba: warped,
      width: source.width,
      height: source.height,
    );
    return context.store.toHandle(entry);
  }
}
