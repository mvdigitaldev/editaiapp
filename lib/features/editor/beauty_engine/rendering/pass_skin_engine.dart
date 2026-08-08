import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../filters/face/derived_masks.dart';
import '../filters/face/mask_sampling.dart';
import '../filters/face/skin/native_skin_backend.dart';
import '../filters/face/skin/skin_retouch_engine.dart';
import '../filters/face/skin/skin_weight_map.dart';
import '../filters/face/makeup_blend_engine.dart';
import '../filters/face/skin_tone_calibration.dart';
import '../filters/face/skin_mask_utils.dart';
import '../models/warp_field.dart';
import '../segment/face_parts_segmentation.dart';
import '../segment/face_parsing_result.dart';
import 'render_pass.dart';
import 'render_target.dart';
import 'texture_handle.dart';

/// Pass consolidado de pele e makeup (Grupos A + C).
class PassSkinEngine implements RenderPass {
  const PassSkinEngine({this.nativeSkinBackend});

  final NativeSkinBackend? nativeSkinBackend;

  static const isolateThresholdPixels = 400 * 400;

  @override
  String get shaderName => RenderShaders.skinEngine;

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

    final smooth = _f(context, 'skin_smooth');
    final whitening = _f(context, 'skin_whitening');
    final acne = _f(context, 'remove_acne');
    final wrinkles = _f(context, 'remove_wrinkles');
    final darkCircles = _f(context, 'remove_dark_circles');
    final shine = _f(context, 'skin_shine');
    final teeth = _f(context, 'teeth_whitening');
    final blush = _f(context, 'blush');
    final contour = _f(context, 'contour');
    final eyebrows = _f(context, 'eyebrows');
    final eyelashes = _f(context, 'eyelashes');
    final irisEnhance = _f(context, 'iris_enhance');

    final retouchParams = SkinRetouchParams(
      smooth: smooth,
      acne: acne,
      wrinkles: wrinkles,
      darkCircles: darkCircles,
      shine: shine,
    );

    final hasMakeup = whitening > 0 ||
        teeth > 0 ||
        blush > 0 ||
        contour > 0 ||
        eyebrows > 0 ||
        eyelashes > 0 ||
        irisEnhance > 0;

    if (retouchParams.isNoop && !hasMakeup) {
      return context.pool.acquireCopy(context.input);
    }

    final width = source.width;
    final height = source.height;
    final mapping =
        (context.uniforms['tileMapping'] as SkinTileMapping?) ??
            const SkinTileMapping();
    final faceWarp = context.uniforms['faceWarp'] as WarpField?;
    var output = Uint8List.fromList(source.rgba);

    DerivedMaskBundle? derived;
    SkinWeightMap? skinMap;
    final needsDerived = !retouchParams.isNoop ||
        teeth > 0 ||
        irisEnhance > 0 ||
        contour > 0 ||
        eyebrows > 0;
    if (!retouchParams.isNoop || hasMakeup) {
      skinMap = SkinWeightMap.build(
        width: width,
        height: height,
        geometric: mask,
        segmentation: (context.uniforms['faceParsing'] as FaceParsingResult?) ==
                null
            ? context.uniforms['faceParts'] as FacePartsSegmentation?
            : null,
        parsing: context.uniforms['faceParsing'] as FaceParsingResult?,
        mapping: mapping,
      );
      if (needsDerived) {
        derived = DerivedMaskBuilder.build(
          rgba: output,
          width: width,
          height: height,
          geometric: mask,
          skinWeights: skinMap.weights,
          parsing: context.uniforms['faceParsing'] as FaceParsingResult?,
          mapping: mapping,
          sampling: MaskSamplingContext(
            tileMapping: mapping,
            faceWarp: faceWarp,
          ),
        );
      }
    }

    if (!retouchParams.isNoop && derived != null && skinMap != null) {
      output = await _runRetouch(
        rgba: output,
        width: width,
        height: height,
        mask: mask,
        params: retouchParams,
        mapping: mapping,
        skinWeights: skinMap.weights,
        derived: derived,
        nativeSkinBackend: nativeSkinBackend,
      );
    }

    if (hasMakeup) {
      _applyMakeup(
        output: output,
        width: width,
        height: height,
        mask: mask,
        mapping: mapping,
        derived: derived,
        skinWeights: skinMap?.weights,
        faceWarp: faceWarp,
        whitening: whitening,
        teeth: teeth,
        blush: blush,
        contour: contour,
        eyebrows: eyebrows,
        eyelashes: eyelashes,
        irisEnhance: irisEnhance,
      );
    }

    final entry = context.store.create(
      rgba: output,
      width: width,
      height: height,
    );
    return context.store.toHandle(entry);
  }

  static Future<Uint8List> _runRetouch({
    required Uint8List rgba,
    required int width,
    required int height,
    required SkinProcessingMask mask,
    required SkinRetouchParams params,
    required SkinTileMapping mapping,
    required Uint8List skinWeights,
    required DerivedMaskBundle derived,
    NativeSkinBackend? nativeSkinBackend,
  }) async {
    if (skinWeights.isEmpty && derived.underEye.every((v) => v == 0)) {
      return rgba;
    }

    final resolved = mapping.resolve(width, height);
    final underEye = params.darkCircles > 0 ? derived.underEye : Uint8List(0);
    final shineMask = params.shine > 0 ? derived.shine : null;

    final request = SkinRetouchRequest(
      rgba: rgba,
      width: width,
      height: height,
      skinWeights: skinWeights,
      underEyeWeights: underEye,
      params: params,
      shineWeights: shineMask,
      shineKnee: derived.tone.isValid ? derived.tone.shineKnee : null,
      faceEdgePx: math.max(
        mask.faceBounds.width * resolved.fullWidth,
        mask.faceBounds.height * resolved.fullHeight,
      ),
    );

    if (nativeSkinBackend != null) {
      final native = await nativeSkinBackend.skinRetouch(request);
      if (native != null && native.length == rgba.length) {
        return native;
      }
    }

    if (width * height >= isolateThresholdPixels) {
      return compute(SkinRetouchEngine.run, request);
    }
    return SkinRetouchEngine.run(request);
  }

  static double _f(RenderPassContext context, String key) {
    return ((context.uniforms[key] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0);
  }

  static void _applyMakeup({
    required Uint8List output,
    required int width,
    required int height,
    required SkinProcessingMask mask,
    required SkinTileMapping mapping,
    required DerivedMaskBundle? derived,
    required Uint8List? skinWeights,
    required WarpField? faceWarp,
    required double whitening,
    required double teeth,
    required double blush,
    required double contour,
    required double eyebrows,
    required double eyelashes,
    required double irisEnhance,
  }) {
    final resolved = mapping.resolve(width, height);
    final bounds = mask.faceBounds;
    final sampling = MaskSamplingContext(
      tileMapping: mapping,
      faceWarp: faceWarp,
    );
    final weights = skinWeights ?? Uint8List(0);
    final tone = SkinToneCalibration.sample(
      rgba: output,
      skinWeights: weights,
      geometric: mask,
      width: width,
      height: height,
      mapping: mapping,
    );
    final targetL = tone.isValid ? tone.oklabL + 0.08 : 0.72;
    final rgbOut = Float64List(3);
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

        final nx = sample.dx;
        final ny = sample.dy;
        final p = y * width + x;
        final skinW = weights.isEmpty
            ? 1.0
            : sampling.weightAt(
                weights: weights,
                x: x,
                y: y,
                width: width,
                height: height,
              );

        final i = p * 4;
        var r = output[i];
        var g = output[i + 1];
        var b = output[i + 2];

        if (whitening > 0 &&
            skinW > 0 &&
            !SkinMaskUtils.isProtected(nx, ny, mask) &&
            SkinMaskUtils.foreheadWeight(nx, ny, mask) < 0.35) {
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

      if (teeth > 0 && derived != null) {
        final weight = derived.teeth[p] / 255.0;
        if (weight > 0) {
          final t = teeth * 0.28 * weight;
          r = (r + (255 - r) * t).round();
          g = (g + (255 - g) * t).round();
          b = (b + (255 - b) * t).round();
        }
      }

      if (irisEnhance > 0 && derived != null) {
        final weight = derived.iris[p] / 255.0;
        if (weight > 0) {
          final t = irisEnhance * 0.22 * weight;
          r = (r + (255 - r) * t * 0.35).round().clamp(0, 255);
          g = (g + (255 - g) * t * 0.55).round().clamp(0, 255);
          b = (b + (255 - b) * t).round().clamp(0, 255);
        }
      }

      if (blush > 0) {
        final weight = SkinMaskUtils.blushWeight(
          nx,
          ny,
          mask,
          skinWeight: skinW,
        );
        if (weight > 0) {
          MakeupBlendEngine.applyBlush(
            r: r,
            g: g,
            b: b,
            amount: blush,
            weight: weight,
            out: rgbOut,
          );
          r = rgbOut[0].round();
          g = rgbOut[1].round();
          b = rgbOut[2].round();
        }
      }

      if (contour > 0) {
        final jaw =
            derived != null ? derived.jawBand[p] / 255.0 : 0.0;
        final weight = jaw > 0
            ? jaw
            : SkinMaskUtils.softRegionsWeight(
                nx,
                ny,
                mask.contourRegions,
                edgeFeather: 0.03,
              );
        if (weight > 0) {
          final c = contour * 0.12 * weight;
          r = (r * (1 - c)).round();
          g = (g * (1 - c)).round();
          b = (b * (1 - c)).round();
        }
      }

      if (eyebrows > 0) {
        var weight = derived != null ? derived.eyebrows[p] / 255.0 : 0.0;
        if (weight <= 0) {
          weight = SkinMaskUtils.softRegionsWeight(
            nx,
            ny,
            mask.eyebrowRegions,
            edgeFeather: 0.025,
          );
        }
        if (weight > 0) {
          MakeupBlendEngine.applyEyebrowDarken(
            r: r,
            g: g,
            b: b,
            amount: eyebrows,
            weight: weight,
            out: rgbOut,
          );
          r = rgbOut[0].round();
          g = rgbOut[1].round();
          b = rgbOut[2].round();
        }
      }

      if (eyelashes > 0) {
        final weight = SkinMaskUtils.softRegionsWeight(
          nx,
          ny,
          mask.eyelashRegions,
          edgeFeather: 0.02,
        );
        if (weight > 0) {
          final e = eyelashes * 0.15 * weight;
          r = (r * (1 - e)).round();
          g = (g * (1 - e)).round();
          b = (b * (1 - e)).round();
        }
      }

        output[i] = r.clamp(0, 255);
        output[i + 1] = g.clamp(0, 255);
        output[i + 2] = b.clamp(0, 255);
      }
    }
  }
}
