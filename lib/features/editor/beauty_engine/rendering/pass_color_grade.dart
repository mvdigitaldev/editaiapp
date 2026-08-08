import 'dart:typed_data';
import 'dart:ui';

import '../filters/color/color_grade_engine.dart';
import '../filters/face/skin/skin_weight_map.dart';
import '../filters/face/skin_mask_utils.dart';
import '../models/face_mesh_result.dart';
import '../models/tune_params.dart';
import '../segment/face_parts_segmentation.dart';
import 'render_pass.dart';
import 'render_target.dart';
import 'texture_handle.dart';

/// Pass de cor global (Grupo D) — grade Lightroom + vinheta + nitidez.
class PassColorGrade implements RenderPass {
  const PassColorGrade({ColorGradeEngine engine = const ColorGradeEngine()})
      : _engine = engine;

  final ColorGradeEngine _engine;

  @override
  String get shaderName => RenderShaders.colorGrade;

  @override
  Future<TextureHandle> execute(RenderPassContext context) async {
    final source = context.store.get(context.input.id);
    if (source == null) {
      return context.input;
    }

    final tune = context.uniforms['tune'] as TuneParams? ?? const TuneParams();
    if (tune.isEmpty) {
      return context.pool.acquireCopy(context.input);
    }

    Float32List? skinProtection =
        context.uniforms['skinProtection'] as Float32List?;
    if (skinProtection == null || skinProtection.isEmpty) {
      final face = context.uniforms['face'] as FaceMeshResult?;
      final imageSize = context.uniforms['imageSize'] as Size?;
      final faceParts = context.uniforms['faceParts'] as FacePartsSegmentation?;
      if (face != null && imageSize != null) {
        final map = SkinWeightMap.build(
          width: source.width,
          height: source.height,
          geometric: SkinMaskUtils.build(face, imageSize),
          segmentation: faceParts,
        );
        skinProtection = Float32List(map.weights.length);
        for (var i = 0; i < map.weights.length; i++) {
          skinProtection[i] = map.weights[i] / 255.0;
        }
      }
    }

    final filtered = _engine.applyToRgba(
      sourceRgba: Uint8List.fromList(source.rgba),
      width: source.width,
      height: source.height,
      tune: tune,
      skinProtectionWeights: skinProtection,
    );

    final entry = context.store.create(
      rgba: filtered,
      width: source.width,
      height: source.height,
    );
    return context.store.toHandle(entry);
  }
}
