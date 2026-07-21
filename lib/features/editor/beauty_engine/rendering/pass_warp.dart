import '../models/warp_field.dart';
import '../warp/warp_cpu_remap.dart';
import 'render_pass.dart';
import 'render_target.dart';
import 'texture_handle.dart';

/// Pass 1: warp remap (MLS field).
class PassWarp implements RenderPass {
  const PassWarp({WarpCpuRemap? remapper}) : _remapper = remapper ?? const WarpCpuRemap();

  final WarpCpuRemap _remapper;

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

    final warped = _remapper.apply(
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
