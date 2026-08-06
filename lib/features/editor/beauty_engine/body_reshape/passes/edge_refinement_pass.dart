import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/warp_field.dart';
import '../maps/protection_maps.dart';
import '../models/person_matte.dart';
import 'body_reshape_pass.dart';
import 'pass_profiler.dart';

/// Refina máscara/deslocamento na borda do matte (anti-ghosting / silhueta).
///
/// Suaviza o campo na transição e atenua gradualmente na banda exterior —
/// NÃO zera abruptamente fora do corpo (evita borda dupla ao afinar).
class EdgeRefinementPass implements BodyReshapePass {
  const EdgeRefinementPass({
    this.edgeSoftness = 0.12,
    this.preserveOuterBand = true,
  });

  /// Largura relativa da zona de feather na borda (0–1 do matte).
  final double edgeSoftness;

  /// Mantém deslocamento na banda exterior (fundo vizinho).
  final bool preserveOuterBand;

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

        final bodyWeight = _sampleBodyWeight(
          nx: nx,
          ny: ny,
          matte: matte,
          protectionMaps: protectionMaps,
        );

        // Fundo rígido (além da banda): zera.
        if (bodyWeight <= 0.001) {
          if (outMask[idx] > 0) {
            refinedCells++;
          }
          outMask[idx] = 0;
          outDisp[idx * 2] = 0;
          outDisp[idx * 2 + 1] = 0;
          continue;
        }

        // Na faixa de borda / banda exterior, alinha máscara ao peso.
        final soft = edgeSoftness.clamp(0.02, 0.5);
        final edgeWeight = _edgeWeight(bodyWeight, soft);
        final targetMask = math.min(outMask[idx], bodyWeight * edgeWeight);
        if ((targetMask - outMask[idx]).abs() > 1e-4 || edgeWeight < 0.999) {
          outDisp[idx * 2] *= edgeWeight;
          outDisp[idx * 2 + 1] *= edgeWeight;
          outMask[idx] = targetMask;
          refinedCells++;
        } else {
          outMask[idx] = math.min(outMask[idx], bodyWeight);
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

  double _sampleBodyWeight({
    required double nx,
    required double ny,
    PersonMatte? matte,
    ProtectionMaps? protectionMaps,
  }) {
    if (protectionMaps != null && !protectionMaps.isEmpty) {
      return protectionMaps.sampleWarpWeight(nx, ny).clamp(0.0, 1.0);
    }
    if (matte != null && !matte.isEmpty) {
      // Sem protection maps: matte binário + pequena banda soft no exterior.
      final alpha = matte.sampleNormalized(nx, ny).clamp(0.0, 1.0);
      if (alpha > 0.05 || !preserveOuterBand) {
        return alpha;
      }
      return 0.0;
    }
    return 1.0;
  }

  /// 1 no interior, cai para 0 só na borda real (alfa baixo).
  ///
  /// Antes decaía linearmente por todo o corpo (0.35 no meio), o que somado ao
  /// `edgeScale²` do shader deixava o warp interno quase imperceptível.
  double _edgeWeight(double alpha, double softness) {
    final soft = softness.clamp(1e-6, 0.5);
    final knee = soft * 2;
    if (alpha >= knee) {
      return 1.0;
    }
    final t = (alpha / knee).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
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
