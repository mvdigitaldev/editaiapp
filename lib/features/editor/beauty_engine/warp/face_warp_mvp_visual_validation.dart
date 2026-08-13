import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/quality/image_quality_metrics.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/anatomical_intent.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_matte_roi.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_mesh_deformation_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_model_specification.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_mesh_forward_warp.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_mvp_structural_validation_diagnostic.dart';
import 'package:flutter/material.dart' show Offset, Size;
import 'package:image/image.dart' as img;

/// Etapa 6.3 — validação visual Go/No-Go (render produção + métricas).
abstract final class FaceWarpMvpVisualValidation {
  FaceWarpMvpVisualValidation._();

  static const toolConfigs = {
    'v_face': (
      current: 0.05,
      recommended: 0.075,
      secondBest: 0.08,
      secondLabel: 'uniform_0.08',
    ),
    'chin': (
      current: 0.06,
      recommended: 0.075,
      secondBest: 0.08,
      secondLabel: 'uniform_0.08',
    ),
    'cheekbone': (
      current: 0.05,
      recommended: 0.07,
      secondBest: 0.08,
      secondLabel: 'uniform_0.08',
    ),
    'narrow_face': (
      current: 0.06,
      recommended: 0.08,
      secondBest: 0.075,
      secondLabel: 'parity_0.075',
    ),
  };

  static const realPhotoAssets = {
    'real-p01': 'test/beauty_engine/warp/fixtures/phase12/p01-man-5021469.png',
    'real-p05': 'test/beauty_engine/warp/fixtures/phase12/p05-young-woman.png',
    'real-p06': 'test/beauty_engine/warp/fixtures/phase12/p06-senior-woman.png',
    'real-p12': 'test/beauty_engine/warp/fixtures/phase12/p12.jpg',
    'real-p21': 'test/beauty_engine/warp/fixtures/phase12/p21.jpg',
  };

  static const faceOvalIndices = {
    10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365,
    379, 378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93,
    234, 127, 162, 21, 54, 103, 67, 109,
  };

  static const _leftEyeIndex = 263;
  static const _rightEyeIndex = 33;

  static Future<Map<String, dynamic>> run({
    required String outputDirectory,
    required List<FaceBenchInput> faces,
  }) async {
    Directory(outputDirectory).createSync(recursive: true);
    const builder = FaceMeshBuilder();
    const engine = FaceMeshDeformationEngine();

    final toolReports = <Map<String, dynamic>>[];

    for (final entry in toolConfigs.entries) {
      final toolKey = entry.key;
      final cfg = entry.value;
      final candidates = [
        ('current', cfg.current),
        ('recommended', cfg.recommended),
        (cfg.secondLabel, cfg.secondBest),
      ];

      final perFaceBoards = <Map<String, dynamic>>[];

      for (final f in faces) {
        final sourceRgba = f.sourceRgba;
        final w = f.imageSize.width.round();
        final h = f.imageSize.height.round();
        final mesh = builder.build(f.face, f.imageSize);
        final influence = FaceMatteRoi.buildInfluenceMap(
          face: f.face,
          imageSize: f.imageSize,
          lateralRadiusExpand: 0.07,
        );

        final renders = <String, Uint8List>{};
        final meta = <String, Map<String, dynamic>>{};

        for (final (label, fse) in candidates) {
          FaceModelSpecification.maxDisplacementFseOverrides = {toolKey: fse};
          try {
            final outDir = '$outputDirectory/$toolKey/${f.id}/$label';
            Directory(outDir).createSync(recursive: true);

            final vertexField = engine.composeVertexField(
              parameters: {toolKey: 1.0},
              context: FaceAnatomyContext(
                face: f.face,
                imageSize: f.imageSize,
                mesh: mesh,
              ),
              mesh: mesh,
            );
            final payload = FaceMeshForwardPayload(
              mesh: mesh,
              vertexField: vertexField,
              influenceMap: influence,
            );
            final rendered = FaceMeshForwardWarp.apply(
              rgba: Uint8List.fromList(sourceRgba),
              width: w,
              height: h,
              payload: payload,
              runId: 'stage6.3-$toolKey-$label-${f.id}',
            );

            final pngPath = '$outDir/render.png';
            File(pngPath).writeAsBytesSync(
              img.encodePng(_rgbaToImage(rendered, w, h)),
            );
            renders[label] = rendered;

            final structural =
                FaceWarpMvpStructuralValidationDiagnostic.validateTool(
              toolKey: toolKey,
              face: f.face,
              mesh: mesh,
              imageSize: f.imageSize,
              skipFieldDiagnostics: true,
            );
            final row100 = (structural['rows'] as List).last as Map;
            final checks = row100['structuralChecks'] as Map<String, dynamic>;

            final vis = _visualMetrics(
              source: sourceRgba,
              rendered: rendered,
              width: w,
              height: h,
              face: f.face,
              imageSize: f.imageSize,
            );

            final row = {
              'faceId': f.id,
              'label': label,
              'fse': fse,
              'pngPath': pngPath,
              'phase14Pass': structural['structuralPassAllIntensities'],
              'safetyGatePass': checks['allPassed'],
              ...vis,
            };
            meta[label] = row;
          } finally {
            FaceModelSpecification.maxDisplacementFseOverrides = null;
          }
        }

        final rec = renders['recommended']!;
        final sec = renders[cfg.secondLabel]!;
        final cur = renders['current']!;
        final pair = _pairMetrics(rec, sec, w, h);
        final ssimRecSrc = ImageQualityMetrics.ssim(rec, sourceRgba, width: w, height: h);
        final ssimSecSrc = ImageQualityMetrics.ssim(sec, sourceRgba, width: w, height: h);

        final boardPath = '$outputDirectory/$toolKey/boards/${f.id}.png';
        Directory('$outputDirectory/$toolKey/boards').createSync(recursive: true);
        _writeBoard(
          boardPath,
          [
            (renders['current']!, 'Atual ${cfg.current}'),
            (rec, 'Recomendado ${cfg.recommended}'),
            (sec, '2º ${cfg.secondBest}'),
          ],
          w,
          h,
        );

        perFaceBoards.add({
          'faceId': f.id,
          'boardPath': boardPath,
          'recVsSecond': pair,
          'candidates': meta,
          'recWorseThanSecond': ssimRecSrc < ssimSecSrc - 0.002,
          'ssimRecVsSource': ssimRecSrc,
          'ssimSecondVsSource': ssimSecSrc,
        });
      }

      var sumSsimRecSecond = 0.0;
      var sumDeltaE = 0.0;
      var sumEdge = 0.0;
      for (final b in perFaceBoards) {
        final pair = b['recVsSecond'] as Map<String, dynamic>;
        sumSsimRecSecond += pair['ssimRecVsSecond'] as double;
        sumDeltaE += pair['deltaERecVsSecond'] as double;
        sumEdge += pair['meanEdgeDiffRecVsSecond'] as double;
      }
      final n = perFaceBoards.length;

      toolReports.add({
        'toolKey': toolKey,
        'config': {
          'current': cfg.current,
          'recommended': cfg.recommended,
          'secondBest': cfg.secondBest,
          'secondLabel': cfg.secondLabel,
        },
        'perFace': perFaceBoards,
        'aggregateRecVsSecond': {
          'avgSsimRecVsSecond': sumSsimRecSecond / n,
          'avgDeltaERecVsSecond': sumDeltaE / n,
          'avgEdgeDiffRecVsSecond': sumEdge / n,
        },
        'outliers': _findOutliers(perFaceBoards, cfg),
      });
    }

    final verdict = _verdict(toolReports);
    final report = {
      'phase': '6.3',
      'lpipsAvailable': false,
      'lpipsNote':
          'LPIPS não existe no projeto; SSIM + ΔE2000 + métricas geométricas usadas.',
      'renderCount': toolConfigs.length * faces.length * 3,
      'tools': toolReports,
      'verdict': verdict,
    };

    File('$outputDirectory/stage6-3-report.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    File('$outputDirectory/stage6-3-report.md')
        .writeAsStringSync(_markdown(report));

    return report;
  }

  static Uint8List syntheticPortraitRgba(FaceMeshResult face, Size size) {
    final w = size.width.round();
    final h = size.height.round();
    final image = img.Image(width: w, height: h);
    img.fill(image, color: img.ColorRgb8(225, 210, 195));

    Offset? px(int index) {
      for (final lm in face.landmarks) {
        if (lm.index == index) {
          return Offset(lm.normalized.dx * w, lm.normalized.dy * h);
        }
      }
      return null;
    }

    void fillEllipse(Offset c, double rx, double ry, img.Color color) {
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final dx = (x - c.dx) / rx;
          final dy = (y - c.dy) / ry;
          if (dx * dx + dy * dy <= 1) {
            image.setPixel(x, y, color);
          }
        }
      }
    }

    fillEllipse(
      Offset(w * 0.5, h * 0.42),
      w * 0.22,
      h * 0.28,
      img.ColorRgb8(240, 200, 170),
    );
    final leftEye = px(_leftEyeIndex);
    final rightEye = px(_rightEyeIndex);
    if (leftEye != null) {
      fillEllipse(leftEye, w * 0.045, h * 0.022, img.ColorRgb8(40, 30, 25));
    }
    if (rightEye != null) {
      fillEllipse(rightEye, w * 0.045, h * 0.022, img.ColorRgb8(40, 30, 25));
    }
    fillEllipse(
      Offset(w * 0.5, h * 0.58),
      w * 0.06,
      h * 0.025,
      img.ColorRgb8(180, 90, 90),
    );

    return _imageToRgba(image);
  }

  static Map<String, dynamic> _visualMetrics({
    required Uint8List source,
    required Uint8List rendered,
    required int width,
    required int height,
    required FaceMeshResult face,
    required Size imageSize,
  }) {
    final ssimVsSource = ImageQualityMetrics.ssim(
      source,
      rendered,
      width: width,
      height: height,
    );
    final deltaE = ImageQualityMetrics.deltaE2000Mean(source, rendered);
    final edgeDiff = _meanEdgeDiff(source, rendered, width, height);
    final contourDiff = _contourDiff(face, imageSize, source, rendered, width, height);
    final bbox = _deformedBBox(source, rendered, width, height);

    return {
      'ssimVsSource': ssimVsSource,
      'deltaEVsSource': deltaE,
      'meanEdgeDiff': edgeDiff,
      'contourDiffPx': contourDiff,
      'deformedBBox': bbox,
    };
  }

  static Map<String, dynamic> _pairMetrics(
    Uint8List a,
    Uint8List b,
    int w,
    int h,
  ) {
    return {
      'ssimRecVsSecond': ImageQualityMetrics.ssim(a, b, width: w, height: h),
      'deltaERecVsSecond': ImageQualityMetrics.deltaE2000Mean(a, b),
      'meanEdgeDiffRecVsSecond': _meanEdgeDiff(a, b, w, h),
    };
  }

  static double _meanEdgeDiff(
    Uint8List a,
    Uint8List b,
    int width,
    int height,
  ) {
    final ea = _sobelMag(a, width, height);
    final eb = _sobelMag(b, width, height);
    var sum = 0.0;
    for (var i = 0; i < ea.length; i++) {
      sum += (ea[i] - eb[i]).abs();
    }
    return sum / ea.length;
  }

  static Float32List _sobelMag(Uint8List rgba, int width, int height) {
    final gray = Float32List(width * height);
    for (var i = 0, p = 0; i < rgba.length; i += 4, p++) {
      gray[p] = 0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2];
    }
    final out = Float32List(width * height);
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final p = y * width + x;
        final gx = -gray[p - width - 1] +
            gray[p - width + 1] -
            2 * gray[p - 1] +
            2 * gray[p + 1] -
            gray[p + width - 1] +
            gray[p + width + 1];
        final gy = -gray[p - width - 1] -
            2 * gray[p - width] -
            gray[p - width + 1] +
            gray[p + width - 1] +
            2 * gray[p + width] +
            gray[p + width + 1];
        out[p] = math.sqrt(gx * gx + gy * gy);
      }
    }
    return out;
  }

  static double _contourDiff(
    FaceMeshResult face,
    Size imageSize,
    Uint8List source,
    Uint8List rendered,
    int width,
    int height,
  ) {
    var sum = 0.0;
    var n = 0;
    for (final index in faceOvalIndices) {
      FaceLandmark? lm;
      for (final l in face.landmarks) {
        if (l.index == index) {
          lm = l;
          break;
        }
      }
      if (lm == null) {
        continue;
      }
      final x = (lm.normalized.dx * width).round().clamp(1, width - 2);
      final y = (lm.normalized.dy * height).round().clamp(1, height - 2);
      final ps = _sobelMag(source, width, height)[y * width + x];
      final pr = _sobelMag(rendered, width, height)[y * width + x];
      sum += (pr - ps).abs();
      n++;
    }
    return n == 0 ? 0 : sum / n;
  }

  static Map<String, int> _deformedBBox(
    Uint8List source,
    Uint8List rendered,
    int width,
    int height,
  ) {
    var x0 = width, y0 = height, x1 = 0, y1 = 0;
    var any = false;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        final d = (source[i] - rendered[i]).abs() +
            (source[i + 1] - rendered[i + 1]).abs() +
            (source[i + 2] - rendered[i + 2]).abs();
        if (d > 12) {
          any = true;
          if (x < x0) {
            x0 = x;
          }
          if (y < y0) {
            y0 = y;
          }
          if (x > x1) {
            x1 = x;
          }
          if (y > y1) {
            y1 = y;
          }
        }
      }
    }
    if (!any) {
      return {'x0': 0, 'y0': 0, 'x1': 0, 'y1': 0, 'areaPx': 0};
    }
    return {
      'x0': x0,
      'y0': y0,
      'x1': x1,
      'y1': y1,
      'areaPx': (x1 - x0) * (y1 - y0),
    };
  }

  static void _writeBoard(
    String path,
    List<(Uint8List rgba, String label)> panels,
    int w,
    int h,
  ) {
    const pad = 8;
    const labelH = 28;
    final board = img.Image(
      width: w * panels.length + pad * (panels.length + 1),
      height: h + labelH + pad * 2,
    );
    img.fill(board, color: img.ColorRgb8(32, 32, 40));
    for (var i = 0; i < panels.length; i++) {
      final x0 = pad + i * (w + pad);
      final panel = _rgbaToImage(panels[i].$1, w, h);
      img.compositeImage(board, panel, dstX: x0, dstY: pad + labelH);
      img.drawString(
        board,
        panels[i].$2,
        font: img.arial14,
        x: x0 + 4,
        y: 6,
        color: img.ColorRgb8(220, 220, 220),
      );
    }
    File(path).writeAsBytesSync(img.encodePng(board));
  }

  static img.Image _rgbaToImage(Uint8List rgba, int w, int h) {
    final image = img.Image(width: w, height: h);
    var o = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        image.setPixelRgba(
          x,
          y,
          rgba[o],
          rgba[o + 1],
          rgba[o + 2],
          rgba[o + 3],
        );
        o += 4;
      }
    }
    return image;
  }

  static Uint8List _imageToRgba(img.Image image) {
    final out = Uint8List(image.width * image.height * 4);
    var o = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        out[o++] = p.r.toInt();
        out[o++] = p.g.toInt();
        out[o++] = p.b.toInt();
        out[o++] = p.a.toInt();
      }
    }
    return out;
  }

  static List<Map<String, dynamic>> _findOutliers(
    List<Map<String, dynamic>> boards,
    ({double current, double recommended, double secondBest, String secondLabel}) cfg,
  ) {
    final outliers = <Map<String, dynamic>>[];
    for (final b in boards) {
      final cands = b['candidates'] as Map<String, dynamic>;
      final rec = cands['recommended'] as Map<String, dynamic>;
      if ((rec['ssimVsSource'] as double) < 0.80) {
        outliers.add({
          'faceId': b['faceId'],
          'type': 'low_ssim',
          'value': rec['ssimVsSource'],
        });
      }
      if ((rec['deltaEVsSource'] as double) > 8.0) {
        outliers.add({
          'faceId': b['faceId'],
          'type': 'high_deltaE',
          'value': rec['deltaEVsSource'],
        });
      }
      if (rec['phase14Pass'] != true || rec['safetyGatePass'] != true) {
        outliers.add({'faceId': b['faceId'], 'type': 'structural_fail'});
      }
    }
    return outliers;
  }

  static Map<String, dynamic> _verdict(List<Map<String, dynamic>> tools) {
    final reasons = <String>[];
    var structuralFail = false;

    for (final t in tools) {
      final outliers = t['outliers'] as List;
      if (outliers.any((o) => o['type'] == 'structural_fail')) {
        structuralFail = true;
        reasons.add('${t['toolKey']}: falha Phase14/Safety Gate');
      }
      final perFace = t['perFace'] as List;
      final worse = perFace.where((f) => f['recWorseThanSecond'] == true).length;
      if (worse > 2) {
        reasons.add('${t['toolKey']}: rec pior que 2º em $worse/10 rostos');
      }
    }

    if (structuralFail) {
      return {'decision': 'NO-GO', 'reasons': reasons};
    }
    return {
      'decision': 'GO',
      'reasons': reasons,
    };
  }

  static String _markdown(Map<String, dynamic> report) {
    final buf = StringBuffer()
      ..writeln('# Etapa 6.3 — Validação visual')
      ..writeln()
      ..writeln('LPIPS: **não disponível** no projeto')
      ..writeln('Veredito: **${(report['verdict'] as Map)['decision']}**')
      ..writeln()
      ..writeln('| Tool | Rec SSIM vs 2º | Outliers | Boards |')
      ..writeln('|------|----------------|----------|--------|');

    for (final t in (report['tools'] as List).cast<Map<String, dynamic>>()) {
      final pf = (t['perFace'] as List).cast<Map<String, dynamic>>();
      final avgSsim = pf.isEmpty
          ? 0.0
          : pf
                  .map(
                    (f) =>
                        (f['recVsSecond'] as Map)['ssimRecVsSecond'] as num,
                  )
                  .reduce((a, b) => a + b) /
              pf.length;
      buf.writeln(
        '| ${t['toolKey']} | ${avgSsim.toStringAsFixed(4)} | '
        '${(t['outliers'] as List).length} | ${pf.length} |',
      );
    }
    return buf.toString();
  }
}

class FaceBenchInput {
  const FaceBenchInput({
    required this.id,
    required this.label,
    required this.face,
    required this.imageSize,
    required this.sourceRgba,
    required this.isSynthetic,
  });

  final String id;
  final String label;
  final FaceMeshResult face;
  final Size imageSize;
  final Uint8List sourceRgba;
  final bool isSynthetic;
}
