import 'dart:typed_data';

import '../body_reshape/maps/influence_map.dart';
import '../debug/agent_debug_log.dart';
import '../models/warp_field.dart';
import '../segment/person_mask.dart';
import 'warp_cpu_remap.dart';

/// Pipeline **face_slim** — backward liquify + composite de vaga lateral com fundo.
///
/// Fantasma = pixels na posição **original** que o liquify backward não reescreveu;
/// substituímos só a faixa lateral desocluída pela cor do fundo (person mask baixa).
abstract final class FaceSlimWarp {
  static const _lateralNormMin = 0.38;
  static const _lateralInfluenceMin = 0.05;
  /// Só borda externa da silhueta — evita pintar bochecha/barba com fundo.
  static const _personOuterMax = 0.54;
  static const _maxBgDistancePx = 36;

  static Uint8List apply({
    required Uint8List rgba,
    required int width,
    required int height,
    required WarpField field,
    required InfluenceMap influence,
    required Map<String, double> parameters,
    PersonMask? personMask,
    String runId = 'face-slim-cpu',
  }) {
    if (field.isIdentity || rgba.isEmpty) {
      return rgba;
    }

    final warped = const WarpCpuRemap(antiGhosting: false).apply(
      rgba: rgba,
      width: width,
      height: height,
      field: field,
      influenceMap: influence,
      influenceGated: false,
      personMask: personMask,
      neckFadeBelow: 0.66,
    );

    return postProcess(
      original: rgba,
      warped: warped,
      width: width,
      height: height,
      field: field,
      influence: influence,
      parameters: parameters,
      personMask: personMask,
      backend: 'cpu',
      gridW: field.gridWidth,
      gridH: field.gridHeight,
      runId: runId,
    );
  }

  static Uint8List postProcess({
    required Uint8List original,
    required Uint8List warped,
    required int width,
    required int height,
    required WarpField field,
    required InfluenceMap influence,
    required Map<String, double> parameters,
    PersonMask? personMask,
    required String backend,
    int gridW = 0,
    int gridH = 0,
    String runId = 'face-slim-post',
  }) {
    final lateralGhostBefore = _countLateralVacancy(
      original: original,
      current: warped,
      width: width,
      height: height,
      influence: influence,
      personMask: personMask,
    );

    var out = warped;
    var vacCompositePx = 0;
    var vacSecondPassPx = 0;
    var vacSkippedNoBg = 0;

    // Mesh backward já preenche disocclusão lateral; vac composite pintava ~2k px
    // com fundo flat na bochecha (D1 confirmado nos logs).
    if (backend != 'mesh' &&
        personMask != null &&
        personMask.bytes.isNotEmpty) {
      final pass1 = _applyVacancyComposite(
        original: original,
        warped: out,
        width: width,
        height: height,
        influence: influence,
        personMask: personMask,
        similarTolerance: 6,
      );
      out = pass1.output;
      vacCompositePx = pass1.filled;
      vacSkippedNoBg = pass1.skippedNoBg;

      final pass2 = _applyVacancyComposite(
        original: original,
        warped: out,
        width: width,
        height: height,
        influence: influence,
        personMask: personMask,
        similarTolerance: 4,
      );
      out = pass2.output;
      vacSecondPassPx = pass2.filled;
      vacSkippedNoBg += pass2.skippedNoBg;
    }

    final lateralGhostAfter = _countLateralVacancy(
      original: original,
      current: out,
      width: width,
      height: height,
      influence: influence,
      personMask: personMask,
      similarTolerance: 4,
    );

    // #region agent log
    AgentDebugLog.write(
      location: 'face_slim_warp.dart:postProcess',
      message: 'face_slim_pipeline',
      hypothesisId: 'D1',
      runId: runId,
      data: {
        'backend': backend,
        'gridW': gridW,
        'gridH': gridH,
        'lateralGhostBefore': lateralGhostBefore,
        'vacCompositePx': vacCompositePx,
        'vacSecondPassPx': vacSecondPassPx,
        'vacSkippedNoBg': vacSkippedNoBg,
        'lateralGhostAfter': lateralGhostAfter,
        'peakDisp': field.maxDisplacementMagnitude,
      },
    );
    // #endregion

    return out;
  }

  static ({Uint8List output, int filled, int skippedNoBg}) _applyVacancyComposite({
    required Uint8List original,
    required Uint8List warped,
    required int width,
    required int height,
    required InfluenceMap influence,
    required PersonMask personMask,
    required int similarTolerance,
  }) {
    final vacancyMask = _buildLateralVacancyMask(
      original: original,
      current: warped,
      width: width,
      height: height,
      influence: influence,
      personMask: personMask,
      similarTolerance: similarTolerance,
    );
    return _compositeVacancyWithBackground(
      original: original,
      warped: warped,
      output: Uint8List.fromList(warped),
      vacancy: vacancyMask,
      width: width,
      height: height,
      personMask: personMask,
    );
  }

  /// Pixels que o backward não reescreveu — a imagem original “atrás” do rosto.
  static Uint8List _buildLateralVacancyMask({
    required Uint8List original,
    required Uint8List current,
    required int width,
    required int height,
    required InfluenceMap influence,
    required PersonMask personMask,
    required int similarTolerance,
  }) {
    final mask = Uint8List(width * height);
    final centerX = width * 0.5;

    for (var y = 0; y < height; y++) {
      final ny = y / height;
      if (ny < 0.14 || ny > 0.70) {
        continue;
      }
      for (var x = 0; x < width; x++) {
        final nx = x / width;
        final lateral = (x - centerX).abs() / (width * 0.5);
        if (lateral < _lateralNormMin) {
          continue;
        }

        final person = personMask.sampleNormalized(nx, ny);
        if (person < 0.28 || person > _personOuterMax) {
          continue;
        }

        final p = y * width + x;
        if (!_pixelsSimilar(original, current, p, tolerance: similarTolerance)) {
          continue;
        }

        final inf = influence.sampleNormalized(nx, ny);
        // Só vaga real: dentro do oval ou borda externa estreita.
        if (inf >= _lateralInfluenceMin) {
          mask[p] = 1;
          continue;
        }
        if (inf <= 0.08 &&
            person >= 0.30 &&
            person <= 0.50 &&
            lateral >= 0.42) {
          mask[p] = 1;
        }
      }
    }
    return mask;
  }

  /// Substitui vaga lateral pela cor do fundo imediato (fora da person mask).
  static ({Uint8List output, int filled, int skippedNoBg})
      _compositeVacancyWithBackground({
    required Uint8List original,
    required Uint8List warped,
    required Uint8List output,
    required Uint8List vacancy,
    required int width,
    required int height,
    required PersonMask personMask,
  }) {
    const bgThreshold = 0.18;
    const inwardBlend = 0.22;
    var filled = 0;
    var skippedNoBg = 0;
    final centerX = width * 0.5;

    for (var y = 0; y < height; y++) {
      final ny = y / height;
      for (var x = 0; x < width; x++) {
        final p = y * width + x;
        if (vacancy[p] == 0) {
          continue;
        }

        final side = x >= centerX ? 1 : -1;
        final bgSample = _sampleBackgroundOutward(
          original: original,
          personMask: personMask,
          width: width,
          height: height,
          x: x,
          y: y,
          ny: ny,
          side: side,
          bgThreshold: bgThreshold,
          maxSearch: _maxBgDistancePx,
        );

        if (bgSample == null || bgSample.distance > _maxBgDistancePx) {
          skippedNoBg++;
          continue;
        }

        final bgRgb = bgSample.rgb;
        final ix = (x - side).clamp(0, width - 1);
        final io = (y * width + ix) * 4;
        final ir = warped[io];
        final ig = warped[io + 1];
        final ib = warped[io + 2];

        final o = p * 4;
        output[o] =
            (bgRgb[0] * (1 - inwardBlend) + ir * inwardBlend).round().clamp(0, 255);
        output[o + 1] =
            (bgRgb[1] * (1 - inwardBlend) + ig * inwardBlend).round().clamp(0, 255);
        output[o + 2] =
            (bgRgb[2] * (1 - inwardBlend) + ib * inwardBlend).round().clamp(0, 255);
        filled++;
      }
    }

    return (output: output, filled: filled, skippedNoBg: skippedNoBg);
  }

  static ({List<int> rgb, int distance})? _sampleBackgroundOutward({
    required Uint8List original,
    required PersonMask personMask,
    required int width,
    required int height,
    required int x,
    required int y,
    required double ny,
    required int side,
    required double bgThreshold,
    required int maxSearch,
  }) {
    var sumR = 0.0;
    var sumG = 0.0;
    var sumB = 0.0;
    var count = 0;
    var firstDist = 0;

    for (var r = 1; r <= maxSearch; r++) {
      final sx = x + side * r;
      if (sx < 0 || sx >= width) {
        break;
      }
      if (personMask.sampleNormalized(sx / width, ny) >= bgThreshold) {
        continue;
      }
      final o = (y * width + sx) * 4;
      sumR += original[o];
      sumG += original[o + 1];
      sumB += original[o + 2];
      count++;
      firstDist = r;
      if (count >= 2) {
        break;
      }
    }

    if (count == 0) {
      return null;
    }
    return (
      rgb: [
        (sumR / count).round(),
        (sumG / count).round(),
        (sumB / count).round(),
      ],
      distance: firstDist,
    );
  }

  static int _countLateralVacancy({
    required Uint8List original,
    required Uint8List current,
    required int width,
    required int height,
    required InfluenceMap influence,
    PersonMask? personMask,
    int similarTolerance = 10,
  }) {
    if (personMask == null || personMask.bytes.isEmpty) {
      return 0;
    }
    final mask = _buildLateralVacancyMask(
      original: original,
      current: current,
      width: width,
      height: height,
      influence: influence,
      personMask: personMask,
      similarTolerance: similarTolerance,
    );
    return mask.where((v) => v == 1).length;
  }

  static bool _pixelsSimilar(
    Uint8List a,
    Uint8List b,
    int pixelIndex, {
    int tolerance = 4,
  }) {
    final o = pixelIndex * 4;
    return (a[o] - b[o]).abs() <= tolerance &&
        (a[o + 1] - b[o + 1]).abs() <= tolerance &&
        (a[o + 2] - b[o + 2]).abs() <= tolerance;
  }
}
