import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../models/warp_field.dart';
import '../maps/texture_confidence_map.dart';
import 'body_reshape_pass.dart';
import 'pass_profiler.dart';

/// Estabiliza textura onde o estiramento (jacobiano) é alto e a confiança
/// de textura é alta — reduz deslocamento de alta frequência sem zerar o efeito.
class TextureStabilizationPass implements BodyReshapePass {
  const TextureStabilizationPass({
    this.stretchThreshold = 1.35,
    this.maxAttenuation = 0.55,
    this.minConfidence = 0.25,
    this.preserveBodyFloor = 0.40,
  });

  /// |singular value| aproximado acima do qual estabiliza.
  final double stretchThreshold;

  /// Fração máxima de atenuação do deslocamento (nunca 1.0).
  final double maxAttenuation;

  /// Confiança mínima de textura para agir.
  final double minConfidence;

  /// Piso: mantém pelo menos esta fração do deslocamento original.
  final double preserveBodyFloor;

  @override
  String get id => 'texture_stabilization';

  @override
  bool isEnabled(BodyMultiPassConfig config) => config.textureStabilization;

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

    final confidence = context.textureConfidence ??
        TextureConfidenceMap.filled(
          width: field.gridWidth,
          height: field.gridHeight,
          imageSize: field.imageSize,
          value: 0.35,
        );

    final result = stabilize(field: field, confidence: confidence);
    context.field = result.field;
    context.intermediateBuffers['texture_stretch'] = result.stretchMap;
    return result.field;
  }

  TextureStabilizationResult stabilize({
    required WarpField field,
    required TextureConfidenceMap confidence,
  }) {
    if (field.isIdentity) {
      return TextureStabilizationResult(
        field: field,
        stretchMap: Float32List(field.gridWidth * field.gridHeight),
        attenuatedCells: 0,
      );
    }

    final gw = field.gridWidth;
    final gh = field.gridHeight;
    final stretchMap = Float32List(gw * gh);
    final outDisp = Float32List.fromList(field.displacement);
    final cellW = field.imageSize.width / math.max(gw - 1, 1);
    final cellH = field.imageSize.height / math.max(gh - 1, 1);
    var attenuated = 0;

    Offset warped(int gx, int gy) {
      final idx = gy * gw + gx;
      final m = field.mask[idx];
      return Offset(
        gx * cellW + field.displacement[idx * 2] * m,
        gy * cellH + field.displacement[idx * 2 + 1] * m,
      );
    }

    for (var gy = 0; gy < gh; gy++) {
      for (var gx = 0; gx < gw; gx++) {
        final idx = gy * gw + gx;
        if (field.mask[idx] <= 0.001) {
          stretchMap[idx] = 1.0;
          continue;
        }

        final gx1 = (gx + 1).clamp(0, gw - 1);
        final gy1 = (gy + 1).clamp(0, gh - 1);
        final p00 = warped(gx, gy);
        final p10 = warped(gx1, gy);
        final p01 = warped(gx, gy1);
        final exLen = (p10 - p00).distance / math.max(cellW, 1e-6);
        final eyLen = (p01 - p00).distance / math.max(cellH, 1e-6);
        final stretch = math.max(exLen, eyLen);
        stretchMap[idx] = stretch;

        if (stretch < stretchThreshold) {
          continue;
        }

        final nx = gx / math.max(gw - 1, 1);
        final ny = gy / math.max(gh - 1, 1);
        final conf = confidence.sampleNormalized(nx, ny);
        if (conf < minConfidence) {
          continue;
        }

        // Atenuação proporcional ao excesso de stretch e à confiança.
        final excess = ((stretch - stretchThreshold) / stretchThreshold)
            .clamp(0.0, 2.0);
        final atten = (excess * conf * maxAttenuation).clamp(0.0, maxAttenuation);
        final keep = math.max(preserveBodyFloor, 1.0 - atten);
        outDisp[idx * 2] *= keep;
        outDisp[idx * 2 + 1] *= keep;
        attenuated++;
      }
    }

    return TextureStabilizationResult(
      field: field.copyWith(
        displacement: outDisp,
        passId: id,
        activeCellCount: attenuated,
      ),
      stretchMap: stretchMap,
      attenuatedCells: attenuated,
    );
  }
}

class TextureStabilizationResult {
  const TextureStabilizationResult({
    required this.field,
    required this.stretchMap,
    required this.attenuatedCells,
  });

  final WarpField field;
  final Float32List stretchMap;
  final int attenuatedCells;
}
