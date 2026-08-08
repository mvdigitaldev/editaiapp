import 'dart:typed_data';

import '../filters/face/makeup_blend_engine.dart';
import '../filters/face/mask_sampling.dart';
import '../filters/face/skin/skin_weight_map.dart';
import '../filters/face/skin_mask_utils.dart';
import '../filters/face/skin_tone_calibration.dart';
import '../models/warp_field.dart';
import 'render_pass.dart';
import 'render_target.dart';
import 'texture_handle.dart';

/// Pass de makeup perceptual (CPU; shader registrado para GPU futura).
class PassMakeupBlend implements RenderPass {
  const PassMakeupBlend();

  @override
  String get shaderName => RenderShaders.makeupBlend;

  @override
  Future<TextureHandle> execute(RenderPassContext context) async {
    final source = context.store.get(context.input.id);
    if (source == null) {
      return context.input;
    }

    final mask = context.uniforms['mask'] as SkinProcessingMask?;
    if (mask == null || mask.isEmpty) {
      return context.pool.acquireCopy(context.input);
    }

    final whitening = _f(context, 'skin_whitening');
    final blush = _f(context, 'blush');
    final eyebrows = _f(context, 'eyebrows');
    if (whitening <= 0 && blush <= 0 && eyebrows <= 0) {
      return context.pool.acquireCopy(context.input);
    }

    final width = source.width;
    final height = source.height;
    final output = Uint8List.fromList(source.rgba);
    final mapping =
        (context.uniforms['tileMapping'] as SkinTileMapping?) ??
            const SkinTileMapping();
    final sampling = MaskSamplingContext(
      tileMapping: mapping,
      faceWarp: context.uniforms['faceWarp'] as WarpField?,
    );
    final skinWeights =
        context.uniforms['skinWeights'] as Uint8List? ?? Uint8List(0);
    final tone = SkinToneCalibration.sample(
      rgba: output,
      skinWeights: skinWeights,
      geometric: mask,
      width: width,
      height: height,
      mapping: mapping,
    );
    final targetL = tone.isValid ? tone.oklabL + 0.08 : 0.72;

    final bounds = mask.faceBounds;
    final resolved = mapping.resolve(width, height);
    final x0 = (bounds.left * resolved.fullWidth - resolved.originX)
        .floor()
        .clamp(0, width);
    final y0 = (bounds.top * resolved.fullHeight - resolved.originY)
        .floor()
        .clamp(0, height);
    final x1 = (bounds.right * resolved.fullWidth - resolved.originX)
        .ceil()
        .clamp(0, width);
    final y1 = (bounds.bottom * resolved.fullHeight - resolved.originY)
        .ceil()
        .clamp(0, height);

    final rgbOut = Float64List(3);
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final sample = sampling.maskNormalized(
          x: x,
          y: y,
          width: width,
          height: height,
        );
        if (!bounds.contains(sample)) {
          continue;
        }

        final skinW = skinWeights.isEmpty
            ? 1.0
            : sampling.weightAt(
                weights: skinWeights,
                x: x,
                y: y,
                width: width,
                height: height,
              );
        if (skinW <= 0 && whitening > 0) {
          continue;
        }

        final i = (y * width + x) * 4;
        var r = output[i];
        var g = output[i + 1];
        var b = output[i + 2];

        if (whitening > 0 &&
            skinW > 0 &&
            !SkinMaskUtils.isProtected(sample.dx, sample.dy, mask) &&
            SkinMaskUtils.foreheadWeight(sample.dx, sample.dy, mask) < 0.35) {
          MakeupBlendEngine.applyWhitening(
            r: r,
            g: g,
            b: b,
            amount: whitening,
            targetLightness: targetL,
            out: rgbOut,
          );
          r = rgbOut[0].round();
          g = rgbOut[1].round();
          b = rgbOut[2].round();
        }

        if (blush > 0) {
          final w = SkinMaskUtils.blushWeight(
            sample.dx,
            sample.dy,
            mask,
            skinWeight: skinW,
          );
          if (w > 0) {
            MakeupBlendEngine.applyBlush(
              r: r,
              g: g,
              b: b,
              amount: blush,
              weight: w,
              out: rgbOut,
            );
            r = rgbOut[0].round();
            g = rgbOut[1].round();
            b = rgbOut[2].round();
          }
        }

        if (eyebrows > 0) {
          final w = SkinMaskUtils.softRegionsWeight(
            sample.dx,
            sample.dy,
            mask.eyebrowRegions,
            edgeFeather: 0.025,
          );
          if (w > 0) {
            MakeupBlendEngine.applyEyebrowDarken(
              r: r,
              g: g,
              b: b,
              amount: eyebrows,
              weight: w,
              out: rgbOut,
            );
            r = rgbOut[0].round();
            g = rgbOut[1].round();
            b = rgbOut[2].round();
          }
        }

        output[i] = r.clamp(0, 255);
        output[i + 1] = g.clamp(0, 255);
        output[i + 2] = b.clamp(0, 255);
      }
    }

    final entry = context.store.create(
      rgba: output,
      width: width,
      height: height,
    );
    return context.store.toHandle(entry);
  }

  static double _f(RenderPassContext context, String key) {
    return ((context.uniforms[key] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0);
  }
}
