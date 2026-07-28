import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../models/warp_field.dart';
import '../models/background_analysis.dart';
import '../protection/background_protector.dart';
import '../protection/rigidity_map.dart';
import 'body_reshape_pass.dart';
import 'pass_profiler.dart';

/// Correção de fundo/borda limitada pelo rigidity map.
///
/// - Zera/atenua deslocamento onde rigidez é alta (linhas estruturais).
/// - Suaviza máscara na transição corpo/fundo para reduzir ghosting.
/// - Nunca aplica correção que *aumente* curvatura sobre linhas rígidas.
class BackgroundCorrectionPass implements BodyReshapePass {
  const BackgroundCorrectionPass({
    this.protector = const BackgroundProtector(),
    this.ghostFeather = 0.18,
    this.rigidityKill = 0.55,
  });

  final BackgroundProtector protector;
  final double ghostFeather;
  final double rigidityKill;

  @override
  String get id => 'background_correction';

  @override
  bool isEnabled(BodyMultiPassConfig config) => config.backgroundCorrection;

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

    final rigidity = field.rigidityMap ??
        rigidityFromBackgroundAnalysis(
          context.assets?.backgroundAnalysis,
          field.imageSize,
        );

    final result = correct(field: field, rigidity: rigidity);
    context.field = result.field;
    return result.field;
  }

  BackgroundCorrectionResult correct({
    required WarpField field,
    RigidityMap? rigidity,
  }) {
    if (field.isIdentity) {
      return BackgroundCorrectionResult(
        field: field,
        correctedCells: 0,
        rigidCellsProtected: 0,
      );
    }

    var working = field;
    var rigidProtected = 0;

    if (rigidity != null && !rigidity.isEmpty) {
      working = protector.applyToField(field: working, rigidity: rigidity);
      for (var gy = 0; gy < working.gridHeight; gy++) {
        for (var gx = 0; gx < working.gridWidth; gx++) {
          final nx = gx / math.max(working.gridWidth - 1, 1);
          final ny = gy / math.max(working.gridHeight - 1, 1);
          final r = rigidity.sampleNormalized(nx, ny);
          if (r < rigidityKill) {
            continue;
          }
          final idx = gy * working.gridWidth + gx;
          final mag = math.sqrt(
            working.displacement[idx * 2] * working.displacement[idx * 2] +
                working.displacement[idx * 2 + 1] *
                    working.displacement[idx * 2 + 1],
          );
          if (mag <= protector.maxLineDistortionPx + 1e-3) {
            rigidProtected++;
          }
        }
      }
    }

    final gw = working.gridWidth;
    final gh = working.gridHeight;
    final outDisp = Float32List.fromList(working.displacement);
    final outMask = Float32List.fromList(working.mask);
    var corrected = 0;
    final feather = ghostFeather.clamp(0.02, 0.5);

    for (var gy = 0; gy < gh; gy++) {
      for (var gx = 0; gx < gw; gx++) {
        final idx = gy * gw + gx;
        final m = working.mask[idx];
        if (m <= 0.001) {
          continue;
        }

        final nx = gx / math.max(gw - 1, 1);
        final ny = gy / math.max(gh - 1, 1);
        final r = rigidity?.sampleNormalized(nx, ny) ?? 0.0;

        // Anti-ghosting: na faixa de máscara intermediária, reduz amostragem cruzada.
        if (m > 0.05 && m < 1.0 - feather) {
          final edgeScale = (m / (1.0 - feather)).clamp(0.0, 1.0);
          outDisp[idx * 2] *= edgeScale;
          outDisp[idx * 2 + 1] *= edgeScale;
          outMask[idx] = m * edgeScale;
          corrected++;
        }

        // Fundo rígido: força máscara/deslocamento para zero (não curva linhas).
        if (r >= rigidityKill) {
          outDisp[idx * 2] = 0;
          outDisp[idx * 2 + 1] = 0;
          outMask[idx] = 0;
          corrected++;
        }
      }
    }

    return BackgroundCorrectionResult(
      field: working.copyWith(
        displacement: outDisp,
        mask: outMask,
        rigidityMap: rigidity ?? working.rigidityMap,
        passId: id,
        activeCellCount: corrected,
      ),
      correctedCells: corrected,
      rigidCellsProtected: rigidProtected,
    );
  }

  /// Converte análise de fundo (bytes) em [RigidityMap].
  static RigidityMap? rigidityFromBackgroundAnalysis(
    BackgroundAnalysis? analysis,
    Size imageSize,
  ) {
    if (analysis == null || analysis.isEmpty) {
      return null;
    }
    final values = Float32List(analysis.rigidity.length);
    var maxV = 0.0;
    for (var i = 0; i < analysis.rigidity.length; i++) {
      final v = analysis.rigidity[i] / 255.0;
      values[i] = v;
      if (v > maxV) {
        maxV = v;
      }
    }
    return RigidityMap(
      values: values,
      width: analysis.width,
      height: analysis.height,
      imageSize: imageSize,
      maxValue: maxV,
      hadLines: maxV > 0.2,
    );
  }
}

class BackgroundCorrectionResult {
  const BackgroundCorrectionResult({
    required this.field,
    required this.correctedCells,
    required this.rigidCellsProtected,
  });

  final WarpField field;
  final int correctedCells;
  final int rigidCellsProtected;
}
