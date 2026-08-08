import 'dart:typed_data';
import 'dart:ui';

import '../body_reshape/maps/influence_map.dart';
import '../models/warp_field.dart';
import 'face_warp_post_inpaint.dart';

/// Máscara RGBA8 de faixas fantasma para inpaint GPU (Sprint 38).
class FaceWarpGhostMask {
  const FaceWarpGhostMask({
    required this.rgba,
    required this.width,
    required this.height,
    required this.imageSize,
  });

  final Uint8List rgba;
  final int width;
  final int height;
  final Size imageSize;

  static FaceWarpGhostMask? buildRgba({
    required WarpField field,
    InfluenceMap? influenceMap,
    required Map<String, double> parameters,
  }) {
    if (FaceWarpPostInpaint.countGhostPixels(
          field: field,
          influenceMap: influenceMap,
          parameters: parameters,
        ) <=
        0) {
      return null;
    }

    final imgW = field.imageSize.width.round();
    final imgH = field.imageSize.height.round();
    final mask = FaceWarpPostInpaint.ghostMaskFor(
      field: field,
      influenceMap: influenceMap,
      parameters: parameters,
    );
    final rgba = Uint8List(imgW * imgH * 4);
    for (var i = 0; i < mask.length; i++) {
      final v = mask[i] == 1 ? 255 : 0;
      final o = i * 4;
      rgba[o] = v;
      rgba[o + 1] = v;
      rgba[o + 2] = v;
      rgba[o + 3] = 255;
    }

    return FaceWarpGhostMask(
      rgba: rgba,
      width: imgW,
      height: imgH,
      imageSize: field.imageSize,
    );
  }
}
