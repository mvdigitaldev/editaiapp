import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../models/warp_field.dart';
import '../../warp/models/control_point.dart';
import 'body_reshape_pass.dart';
import 'pass_profiler.dart';

/// Refinamento TPS de baixa frequência sobre o [WarpField].
///
/// Suaviza ruído de alta frequência no deslocamento preservando a deformação
/// global (âncoras esparsas + kernel thin-plate / blend low-pass).
class TpsRefinementPass implements BodyReshapePass {
  const TpsRefinementPass({
    this.maxAnchors = 48,
    this.lowPassBlend = 0.55,
    this.minMask = 0.05,
    this.intensityLimit = 0.85,
  });

  final int maxAnchors;
  final double lowPassBlend;
  final double minMask;
  final double intensityLimit;

  @override
  String get id => 'tps_refinement';

  @override
  bool isEnabled(BodyMultiPassConfig config) => config.tpsRefinement;

  @override
  WarpField run(BodyPassContext context) {
    final field = context.field;
    if (field == null || field.isIdentity) {
      return field ??
          WarpField.identity(
            imageSize: context.imageSize,
            region: context.region,
          );
    }

    final refined = refine(
      field: field,
      controlPoints: context.controlPoints,
    );
    context.field = refined;
    context.intermediateBuffers['tps_lowpass'] =
        Float32List.fromList(refined.displacement);
    return refined;
  }

  WarpField refine({
    required WarpField field,
    List<ControlPoint> controlPoints = const [],
  }) {
    if (field.isIdentity) {
      return field;
    }

    final gw = field.gridWidth;
    final gh = field.gridHeight;
    final low = _lowPassDisplacement(field);
    final anchors = _selectAnchors(field, controlPoints);

    final outDisp = Float32List(field.displacement.length);
    final outMask = Float32List.fromList(field.mask);
    final blend = lowPassBlend.clamp(0.0, 1.0) * intensityLimit.clamp(0.0, 1.0);

    for (var gy = 0; gy < gh; gy++) {
      for (var gx = 0; gx < gw; gx++) {
        final idx = gy * gw + gx;
        final m = field.mask[idx];
        if (m < minMask) {
          outDisp[idx * 2] = 0;
          outDisp[idx * 2 + 1] = 0;
          continue;
        }

        final ox = field.displacement[idx * 2];
        final oy = field.displacement[idx * 2 + 1];
        var tx = low[idx * 2];
        var ty = low[idx * 2 + 1];

        // TPS esparso só guia o low-pass (não substitui — evita amplificar HF).
        if (anchors.length >= 4) {
          final px = (gx / (gw - 1)) * field.imageSize.width;
          final py = (gy / (gh - 1)) * field.imageSize.height;
          final tps = _sampleThinPlate(anchors, Offset(px, py));
          tx = tx * 0.65 + tps.dx * 0.35;
          ty = ty * 0.65 + tps.dy * 0.35;
        }

        // Mistura limitada: não anula o efeito corporal.
        outDisp[idx * 2] = ox * (1.0 - blend) + tx * blend;
        outDisp[idx * 2 + 1] = oy * (1.0 - blend) + ty * blend;
      }
    }

    return field.copyWith(
      displacement: outDisp,
      mask: outMask,
      passId: id,
    );
  }

  /// Low-pass 3×3 (separável) no deslocamento ponderado pela máscara.
  Float32List _lowPassDisplacement(WarpField field) {
    final gw = field.gridWidth;
    final gh = field.gridHeight;
    final src = field.displacement;
    final mask = field.mask;
    final tmp = Float32List(src.length);
    final out = Float32List(src.length);

    // Horizontal
    for (var gy = 0; gy < gh; gy++) {
      for (var gx = 0; gx < gw; gx++) {
        var wx = 0.0;
        var wy = 0.0;
        var w = 0.0;
        for (var dx = -1; dx <= 1; dx++) {
          final x = (gx + dx).clamp(0, gw - 1);
          final i = gy * gw + x;
          final mw = mask[i] + 0.05;
          final k = dx == 0 ? 2.0 : 1.0;
          wx += src[i * 2] * mw * k;
          wy += src[i * 2 + 1] * mw * k;
          w += mw * k;
        }
        final o = (gy * gw + gx) * 2;
        tmp[o] = wx / w;
        tmp[o + 1] = wy / w;
      }
    }

    // Vertical
    for (var gy = 0; gy < gh; gy++) {
      for (var gx = 0; gx < gw; gx++) {
        var wx = 0.0;
        var wy = 0.0;
        var w = 0.0;
        for (var dy = -1; dy <= 1; dy++) {
          final y = (gy + dy).clamp(0, gh - 1);
          final i = y * gw + gx;
          final mw = mask[i] + 0.05;
          final k = dy == 0 ? 2.0 : 1.0;
          wx += tmp[i * 2] * mw * k;
          wy += tmp[i * 2 + 1] * mw * k;
          w += mw * k;
        }
        final o = (gy * gw + gx) * 2;
        out[o] = wx / w;
        out[o + 1] = wy / w;
      }
    }
    return out;
  }

  List<_TpsAnchor> _selectAnchors(
    WarpField field,
    List<ControlPoint> controlPoints,
  ) {
    final anchors = <_TpsAnchor>[];
    if (controlPoints.isNotEmpty) {
      final step = math.max(1, controlPoints.length ~/ maxAnchors);
      for (var i = 0; i < controlPoints.length && anchors.length < maxAnchors; i += step) {
        final cp = controlPoints[i];
        if (cp.isAnchor) {
          continue;
        }
        anchors.add(
          _TpsAnchor(
            position: cp.source,
            displacement: Offset(
              cp.target.dx - cp.source.dx,
              cp.target.dy - cp.source.dy,
            ),
          ),
        );
      }
    }

    if (anchors.length >= 4) {
      return anchors;
    }

    // Fallback: amostrar células ativas da grade.
    final gw = field.gridWidth;
    final gh = field.gridHeight;
    final stride = math.max(1, math.min(gw, gh) ~/ 8);
    for (var gy = 0; gy < gh; gy += stride) {
      for (var gx = 0; gx < gw; gx += stride) {
        final idx = gy * gw + gx;
        if (field.mask[idx] < minMask) {
          continue;
        }
        anchors.add(
          _TpsAnchor(
            position: Offset(
              (gx / (gw - 1)) * field.imageSize.width,
              (gy / (gh - 1)) * field.imageSize.height,
            ),
            displacement: Offset(
              field.displacement[idx * 2],
              field.displacement[idx * 2 + 1],
            ),
          ),
        );
        if (anchors.length >= maxAnchors) {
          return anchors;
        }
      }
    }
    return anchors;
  }

  /// Kernel RBF gaussiano sobre âncoras (LOD preview, baixa frequência).
  Offset _sampleThinPlate(List<_TpsAnchor> anchors, Offset p) {
    var sumW = 0.0;
    var sx = 0.0;
    var sy = 0.0;
    // Escala ~10% da diagonal típica da imagem.
    final sigma = 24.0;
    final inv2s2 = 1.0 / (2.0 * sigma * sigma);
    for (final a in anchors) {
      final dx = p.dx - a.position.dx;
      final dy = p.dy - a.position.dy;
      final r2 = dx * dx + dy * dy;
      final weight = math.exp(-r2 * inv2s2);
      sumW += weight;
      sx += weight * a.displacement.dx;
      sy += weight * a.displacement.dy;
    }
    if (sumW < 1e-12) {
      return Offset.zero;
    }
    return Offset(sx / sumW, sy / sumW);
  }
}

class _TpsAnchor {
  const _TpsAnchor({required this.position, required this.displacement});
  final Offset position;
  final Offset displacement;
}
