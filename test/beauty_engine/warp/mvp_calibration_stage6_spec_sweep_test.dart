import 'dart:convert';
import 'dart:io';

import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_mvp_spec_sweep_benchmark.dart';
import 'package:flutter/material.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';

import '../filters/skin/mvp_benchmark_faces.dart';

/// Etapa 6 — validação experimental de maxDisplacementFse.
///
/// flutter test test/beauty_engine/warp/mvp_calibration_stage6_spec_sweep_test.dart --concurrency=1
void main() {
  const tools = ['v_face', 'chin', 'cheekbone', 'narrow_face'];
  final outRoot = '${Directory.current.path}/.cursor/mvp-calibration-stage6';

  List<
      ({
        String id,
        String label,
        FaceMeshResult face,
        Size imageSize,
        bool isSynthetic,
      })> loadFaces() {
    final synthetic = defaultSyntheticBenchmarkFaces()
        .map(
          (s) => (
            id: s.id,
            label: s.label ?? s.shape.name,
            face: syntheticFaceForShape(s.shape),
            imageSize: s.imageSize,
            isSynthetic: true,
          ),
        )
        .toList();
    final real = loadAvailableRealBenchmarkFaces()
        .map(
          (r) => (
            id: r.id,
            label: r.label,
            face: r.face,
            imageSize: r.imageSize,
            isSynthetic: false,
          ),
        )
        .toList();
    return [...synthetic, ...real];
  }

  for (final toolKey in tools) {
    test('Stage 6 — $toolKey maxDisplacementFse sweep', () async {
      final faces = loadFaces();
      expect(faces.length, greaterThanOrEqualTo(10));

      final report = await FaceWarpMvpSpecSweepBenchmark.runToolSweep(
        toolKey: toolKey,
        faces: faces,
        outputDirectory: '$outRoot/$toolKey',
        runId: 'stage6',
      );

      final rec = report['recommendation'] as Map<String, dynamic>;
      // ignore: avoid_print
      print(
        'STAGE6 $toolKey recommended=${rec['recommendedMaxDisplacementFse']} '
        'firstRegression=${rec['firstRegressionAtFse']}',
      );

      for (final s in (report['steps'] as List).cast<Map<String, dynamic>>()) {
        // ignore: avoid_print
        print(
          'STAGE6 $toolKey fse=${s['maxDisplacementFse']} '
          'effMax=${((s['aggregateAll'] as Map)['avgEffectiveRoiMaxPx'] as num).toStringAsFixed(2)} '
          'structural=${s['structuralPassAllFaces']} '
          'regression=${s['regressionDetected']}',
        );
      }
    });
  }

  test('Stage 6 — summary report', () async {
    final summaries = <Map<String, dynamic>>[];
    for (final toolKey in tools) {
      final path = '$outRoot/$toolKey/stage6-$toolKey-sweep.json';
      expect(File(path).existsSync(), isTrue, reason: 'run tool sweeps first');
      summaries.add(
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>,
      );
    }

    final summary = {
      'phase': 6,
      'tools': summaries.map((s) {
        final rec = s['recommendation'] as Map<String, dynamic>;
        final baseline = s['baselineMaxDisplacementFse'];
        final baselineStep = (s['steps'] as List).cast<Map<String, dynamic>>().first;
        final recStep = (s['steps'] as List)
            .cast<Map<String, dynamic>>()
            .firstWhere(
              (st) =>
                  st['maxDisplacementFse'] == rec['recommendedMaxDisplacementFse'],
            );
        return {
          'toolKey': s['toolKey'],
          'baselineMaxDisplacementFse': baseline,
          'recommendedMaxDisplacementFse': rec['recommendedMaxDisplacementFse'],
          'firstRegressionAtFse': rec['firstRegressionAtFse'],
          'baselineAvgEffectiveRoiMaxPx':
              (baselineStep['aggregateAll'] as Map)['avgEffectiveRoiMaxPx'],
          'recommendedAvgEffectiveRoiMaxPx':
              (recStep['aggregateAll'] as Map)['avgEffectiveRoiMaxPx'],
          'measuredGainPct': _gainPct(
            (baselineStep['aggregateAll'] as Map)['avgEffectiveRoiMaxPx'] as num,
            (recStep['aggregateAll'] as Map)['avgEffectiveRoiMaxPx'] as num,
          ),
        };
      }).toList(),
    };

    Directory(outRoot).createSync(recursive: true);
    File('$outRoot/stage6-summary.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(summary),
    );
    File('$outRoot/stage6-summary.md').writeAsStringSync(_summaryMarkdown(summary));

    // ignore: avoid_print
    print('STAGE6 summary written to $outRoot/stage6-summary.md');
  });
}

double _gainPct(num before, num after) {
  if (before <= 1e-9) {
    return 0;
  }
  return ((after - before) / before) * 100;
}

String _summaryMarkdown(Map<String, dynamic> summary) {
  final buf = StringBuffer()
    ..writeln('# Etapa 6 — Resumo spec ACE (medido)')
    ..writeln()
    ..writeln(
      '| Tool | Baseline FSE | Recomendado | Ganho medido (eff max) | '
      '1ª regressão |',
    )
    ..writeln(
      '|------|--------------|-------------|------------------------|--------------|',
    );

  for (final t in (summary['tools'] as List).cast<Map<String, dynamic>>()) {
    buf.writeln(
      '| ${t['toolKey']} '
      '| ${t['baselineMaxDisplacementFse']} '
      '| ${t['recommendedMaxDisplacementFse']} '
      '| ${(t['measuredGainPct'] as num).toStringAsFixed(1)}% '
      '| ${t['firstRegressionAtFse'] ?? '—'} |',
    );
  }

  return buf.toString();
}
