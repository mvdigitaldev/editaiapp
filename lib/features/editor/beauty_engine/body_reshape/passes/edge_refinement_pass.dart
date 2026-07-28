import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/warp_field.dart';
import '../maps/protection_maps.dart';
import '../models/person_matte.dart';
import 'body_reshape_pass.dart';
import 'pass_profiler.dart';

/// Refina máscara/deslocamento na borda do matte (anti-ghosting / silhueta).
///
/// Suaviza o campo onde o matte está em transição e zera fora do corpo.
class EdgeRefinementPass implements BodyReshapePass {
  const EdgeRefinementPass({
    this.edgeSoftness = 0.12,
    this.exteriorKill = true,
  });

  /// Largura relativa da zona de feather na borda (0–1 do matte).
  final double edgeSoftness;

  /// Fora do matte (alfa ≈ 0) força máscara zero.
  final bool exteriorKill;

  @override
  String get id => 'edge_refinement';

  @override
  bool isEnabled(BodyMultiPassConfig config) => config.edgeRefinement;

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

    final matte = context.assets?.personMatte;
    final protection = context.protectionMaps;
    final refined = refine(
      field: field,
      matte: matte,
      protectionMaps: protection,
    );
    context.field = refined;
    return refined;
  }

  WarpField refine({
    required WarpField field,
    PersonMatte? matte,
    ProtectionMaps? protectionMaps,
  }) {
    if (field.isIdentity) {
      return field;
    }

    final gw = field.gridWidth;
    final gh = field.gridHeight;
    final outDisp = Float32List.fromList(field.displacement);
    final outMask = Float32List.fromList(field.mask);
    var refinedCells = 0;

    for (var gy = 0; gy < gh; gy++) {
      for (var gx = 0; gx < gw; gx++) {
        final nx = gx / (gw - 1);
        final ny = gy / (gh - 1);
        final idx = gy * gw + gx;

        final bodyAlpha = _sampleBodyAlpha(
          nx: nx,
          ny: ny,
          matte: matte,
          protectionMaps: protectionMaps,
        );

        if (exteriorKill && bodyAlpha <= 0.001) {
          if (outMask[idx] > 0) {
            refinedCells++;
          }
          outMask[idx] = 0;
          outDisp[idx * 2] = 0;
          outDisp[idx * 2 + 1] = 0;
          continue;
        }

        // Na faixa de borda, atenua deslocamento e alinha máscara ao alfa.
        final soft = edgeSoftness.clamp(0.02, 0.5);
        final edgeWeight = _edgeWeight(bodyAlpha, soft);
        if (edgeWeight < 0.999) {
          outDisp[idx * 2] *= edgeWeight;
          outDisp[idx * 2 + 1] *= edgeWeight;
          outMask[idx] = math.min(outMask[idx], bodyAlpha * edgeWeight);
          refinedCells++;
        } else {
          outMask[idx] = math.min(outMask[idx], bodyAlpha);
        }
      }
    }

    // Suavização local 3×3 da máscara (LOD leve para preview).
    final smoothed = _smoothMask(outMask, gw, gh);

    return field.copyWith(
      displacement: outDisp,
      mask: smoothed,
      passId: id,
      activeCellCount: refinedCells,
    );
  }

  double _sampleBodyAlpha({
    required double nx,
    required double ny,
    PersonMatte? matte,
    ProtectionMaps? protectionMaps,
  }) {
    if (protectionMaps != null && !protectionMaps.isEmpty) {
      return protectionMaps.sampleWarpWeight(nx, ny).clamp(0.0, 1.0);
    }
    if (matte != null && !matte.isEmpty) {
      return matte.sampleNormalized(nx, ny).clamp(0.0, 1.0);
    }
    return 1.0;
  }

  /// 1 no interior, cai para 0 na borda (alfa baixo).
  double _edgeWeight(double alpha, double softness) {
    final soft = softness <= 1e-6 ? 1e-6 : softness;
    if (alpha >= 1.0 - soft) {
      return 1.0;
    }
    if (alpha <= soft) {
      return (alpha / soft).clamp(0.0, 1.0);
    }
    final t = ((alpha - soft) / (1.0 - 2 * soft)).clamp(0.0, 1.0);
    return 0.35 + 0.65 * t;
  }

  Float32List _smoothMask(Float32List mask, int gw, int gh) {
    final out = Float32List(mask.length);
    for (var gy = 0; gy < gh; gy++) {
      for (var gx = 0; gx < gw; gx++) {
        var sum = 0.0;
        var count = 0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final x = gx + dx;
            final y = gy + dy;
            if (x < 0 || y < 0 || x >= gw || y >= gh) {
              continue;
            }
            sum += mask[y * gw + x];
            count++;
          }
        }
        out[gy * gw + gx] = count == 0 ? 0.0 : sum / count;
      }
    }
    return out;
  }
}
