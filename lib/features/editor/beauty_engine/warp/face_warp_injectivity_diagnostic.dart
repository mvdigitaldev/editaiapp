import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Offset, Size;
import 'package:image/image.dart' as img;

import '../debug/agent_debug_log.dart';
import '../filters/face/face_warp_utils.dart';
import '../mesh/tri_mesh_spatial_index.dart';
import '../models/tri_mesh.dart';
import '../body_reshape/maps/influence_map.dart';
import '../segment/person_mask.dart';
import 'anatomy/anatomical_intent.dart';
import 'anatomy/face_mesh_deformation_engine.dart';
import 'face_mesh_forward_warp.dart';
import 'face_warp_render_contract.dart';
import 'face_warp_renderer.dart' show GeometricSupport;

/// Resultado do sweep Fase 6 — threshold de injetividade.
class FaceWarpInjectivityDiagnosticResult {
  const FaceWarpInjectivityDiagnosticResult({
    required this.summary,
    required this.sweepJsonPath,
  });

  final Map<String, dynamic> summary;
  final String sweepJsonPath;
}

/// Fase 6 — intensity sweep face_slim e threshold de injetividade.
abstract final class FaceWarpInjectivityDiagnostic {
  FaceWarpInjectivityDiagnostic._();

  static const _defaultOutputDir =
      '/Users/leonardo/Documents/Projetos/editaiapp/.cursor';

  static const _intensities = [
    0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0,
  ];

  static const _hotspotPairs = [
    (name: 'jaw_446_469', triA: 446, triB: 469, x0: 220, y0: 580, x1: 250, y1: 620),
    (name: 'cheek_672_558', triA: 672, triB: 558, x0: 405, y0: 555, x1: 420, y1: 570),
    (name: 'brow_149_154', triA: 149, triB: 154, x0: 162, y0: 438, x1: 175, y1: 448),
  ];

  static Future<FaceWarpInjectivityDiagnosticResult?> run({
    required dynamic face,
    required TriMesh mesh,
    required InfluenceMap influenceMap,
    required PersonMask? personMask,
    required int width,
    required int height,
    String runId = 'injectivity-sweep-real',
    String? outputDirectory,
  }) async {
    if (!kDebugMode) {
      return null;
    }

    try {
      final outDir = outputDirectory ?? _defaultOutputDir;
      Directory(outDir).createSync(recursive: true);

      const engine = FaceMeshDeformationEngine();
      final imageSize = Size(width.toDouble(), height.toDouble());

      final sweepRows = <Map<String, dynamic>>[];
      final minJacobianByIntensity = <Map<String, dynamic>>[];
      final overlapByIntensity = <Map<String, dynamic>>[];
      final jumpByIntensity = <Map<String, dynamic>>[];
      final hotspotTables = <Map<String, dynamic>>[];

      double? firstMultiCoverage;
      double? firstSignificantOverlap;
      double? firstJump10;

      for (final intensity in _intensities) {
        debugPrint('P6 sweep face_slim=$intensity');

        final vertexField = engine.composeVertexField(
          parameters: {'face_slim': intensity},
          context: FaceAnatomyContext(
            face: face,
            imageSize: imageSize,
            mesh: mesh,
          ),
        );
        final payload = FaceMeshForwardPayload(
          mesh: mesh,
          vertexField: vertexField,
          influenceMap: influenceMap,
          personMask: personMask,
        );

        final row = _analyzeIntensity(
          payload: payload,
          width: width,
          height: height,
          faceSlim: intensity,
        );
        sweepRows.add(row);

        minJacobianByIntensity.add({
          'faceSlim': intensity,
          ...Map<String, dynamic>.from(row['fieldJacobian'] as Map),
        });
        overlapByIntensity.add({
          'faceSlim': intensity,
          'overlapPairCount': row['overlapPairCount'],
          'maxOverlapArea': row['maxOverlapArea'],
          'multiCoveragePixels': row['multiCoveragePixels'],
        });
        jumpByIntensity.add({
          'faceSlim': intensity,
          'jumpGt5': row['jumpGt5'],
          'jumpGt10': row['jumpGt10'],
          'maxSourceJump': row['maxSourceJump'],
          'p95SourceJump': row['p95SourceJump'],
        });

        for (final hs in _hotspotPairs) {
          hotspotTables.add({
            'hotspot': hs.name,
            'faceSlim': intensity,
            ...(row['hotspots'] as Map<String, dynamic>)[hs.name]
                as Map<String, dynamic>,
          });
        }

        if (firstMultiCoverage == null &&
            (row['multiCoveragePixels'] as int) > 0) {
          firstMultiCoverage = intensity;
        }
        if (firstSignificantOverlap == null &&
            (row['maxOverlapArea'] as double) > 1.0) {
          firstSignificantOverlap = intensity;
        }
        if (firstJump10 == null && (row['jumpGt10'] as int) > 0) {
          firstJump10 = intensity;
        }
      }

      final lastNoOverlap = _findLastIntensity(
        sweepRows,
        (r) => (r['multiCoveragePixels'] as int) == 0,
      );

      final pngIntensities = <double>{
        if (lastNoOverlap != null) lastNoOverlap,
        if (firstMultiCoverage != null) firstMultiCoverage,
        0.9,
      };

      for (final intensity in pngIntensities) {
        await _writeCriticalMaps(
          outDir: outDir,
          face: face,
          mesh: mesh,
          influenceMap: influenceMap,
          personMask: personMask,
          width: width,
          height: height,
          intensity: intensity,
          engine: engine,
          imageSize: imageSize,
        );
      }

      final summary = {
        'firstMultiCoverageIntensity': firstMultiCoverage,
        'firstSignificantOverlapIntensity': firstSignificantOverlap,
        'firstJump10Intensity': firstJump10,
        'lastNoMultiCoverageIntensity': lastNoOverlap,
        'minJacobianByIntensity': minJacobianByIntensity,
        'overlapByIntensity': overlapByIntensity,
        'jumpByIntensity': jumpByIntensity,
        'criticalHotspots': _summarizeHotspots(hotspotTables),
        'intensitySweep': sweepRows,
        'pngIntensitiesGenerated':
            pngIntensities.map(_intensityLabel).toList(),
      };

      final sweepJsonPath = '$outDir/phase6_intensity_sweep.json';
      File(sweepJsonPath).writeAsStringSync(jsonEncode(summary));

      AgentDebugLog.write(
        location: 'face_warp_injectivity_diagnostic.dart:run',
        message: 'phase6_injectivity_diagnostic',
        hypothesisId: 'P6INJ',
        runId: runId,
        phase: '6',
        data: {
          'firstMultiCoverageIntensity': firstMultiCoverage,
          'firstSignificantOverlapIntensity': firstSignificantOverlap,
          'firstJump10Intensity': firstJump10,
          'minJacobianByIntensity': minJacobianByIntensity,
          'overlapByIntensity': overlapByIntensity,
          'jumpByIntensity': jumpByIntensity,
          'criticalHotspots': summary['criticalHotspots'],
        },
      );

      return FaceWarpInjectivityDiagnosticResult(
        summary: summary,
        sweepJsonPath: sweepJsonPath,
      );
    } catch (e, st) {
      debugPrint('FaceWarpInjectivityDiagnostic failed: $e\n$st');
      return null;
    }
  }

  static Map<String, dynamic> _analyzeIntensity({
    required FaceMeshForwardPayload payload,
    required int width,
    required int height,
    required double faceSlim,
  }) {
    final built = _buildDeformedContext(
      payload: payload,
      width: width,
      height: height,
    );
    final dest = built.deformedMesh;
    final src = built.sourceMesh;
    final roi = built.roi;
    final triCount = dest.triangleCount;

    final destAreas = List<double>.generate(
      triCount,
      (t) => _signedAreaFromPoints(_trianglePoints(dest, t)),
    );
    final srcAreas = List<double>.generate(
      triCount,
      (t) => _signedAreaFromPoints(_trianglePoints(src, t)),
    );
    final absDest = destAreas.map((a) => a.abs()).toList()..sort();

    var minAreaRatio = double.infinity;
    for (var t = 0; t < triCount; t++) {
      final sa = srcAreas[t].abs();
      if (sa < 1e-9) {
        continue;
      }
      final ratio = destAreas[t].abs() / sa;
      if (ratio < minAreaRatio) {
        minAreaRatio = ratio;
      }
    }

    final degenerateCounts = <String, int>{};
    for (final th in [0.01, 0.1, 0.5, 1.0, 2.0]) {
      degenerateCounts['lt$th'] = absDest.where((a) => a < th).length;
    }

    final coverageCount = _buildCoverageCountMap(
      mesh: dest,
      spatialIndex: built.spatialIndex,
      roi: roi,
      width: width,
      height: height,
    );

    final hist = _coverageHistogram(coverageCount, roi, width);
    final roiPixels = (roi.x1 - roi.x0 + 1) * (roi.y1 - roi.y0 + 1);
    var meshHitPx = 0;
    var multiCoverage = 0;
    var cov2 = 0;
    var cov3Plus = 0;
    for (var y = roi.y0; y <= roi.y1; y++) {
      for (var x = roi.x0; x <= roi.x1; x++) {
        final c = coverageCount[y * width + x];
        if (c >= 1) {
          meshHitPx++;
        }
        if (c >= 2) {
          multiCoverage++;
        }
        if (c == 2) {
          cov2++;
        }
        if (c >= 3) {
          cov3Plus++;
        }
      }
    }

    final overlapScan = _scanTriangleOverlaps(dest);
    final jumps = _computeNeighborJumps(
      spatialIndex: built.spatialIndex,
      sourceMesh: src,
      roi: roi,
      width: width,
      height: height,
    );

    final fieldJ = _computeFieldJacobian(
      payload: payload,
      sourceMesh: src,
      roi: roi,
      width: width,
      height: height,
    );

    final hotspots = <String, Map<String, dynamic>>{};
    for (final hs in _hotspotPairs) {
      if (hs.triA >= triCount || hs.triB >= triCount) {
        hotspots[hs.name] = {'error': 'triangle_index_out_of_range'};
        continue;
      }
      final overlap = _trianglePairOverlap(dest, hs.triA, hs.triB);
      var regionMulti = 0;
      var regionMaxJump = 0.0;
      for (var y = hs.y0; y <= hs.y1; y++) {
        for (var x = hs.x0; x <= hs.x1; x++) {
          if (coverageCount[y * width + x] >= 2) {
            regionMulti++;
          }
        }
      }
      for (final p in jumps.pairs) {
        final inA = p.ax >= hs.x0 &&
            p.ax <= hs.x1 &&
            p.ay >= hs.y0 &&
            p.ay <= hs.y1;
        final inB = p.bx >= hs.x0 &&
            p.bx <= hs.x1 &&
            p.by >= hs.y0 &&
            p.by <= hs.y1;
        if (inA || inB) {
          regionMaxJump = math.max(regionMaxJump, p.delta);
        }
      }

      hotspots[hs.name] = {
        'overlapArea': overlap['destinationOverlapArea'],
        'overlapRatioA': overlap['overlapRatioA'],
        'overlapRatioB': overlap['overlapRatioB'],
        'regionMultiCoveragePixels': regionMulti,
        'regionMaxSourceJump': regionMaxJump,
        'spatialOverlap': overlap['spatialOverlap'],
      };
    }

    return {
      'faceSlim': faceSlim,
      'meshHitPx': meshHitPx,
      'destinationCoverage': roiPixels > 0 ? meshHitPx / roiPixels : 0.0,
      'multiCoveragePixels': multiCoverage,
      'coverage2': cov2,
      'coverage3Plus': cov3Plus,
      'coverageHistogram': hist,
      'overlapPairCount': overlapScan.pairCount,
      'maxOverlapArea': overlapScan.maxArea,
      'degenerateTriangles': degenerateCounts,
      'negativeDestinationTriangles': destAreas.where((a) => a < 0).length,
      'nearZeroDestinationTriangles':
          destAreas.where((a) => a.abs() < 0.5).length,
      'orientationInconsistencies':
          _countOrientationInconsistencies(dest, destAreas),
      'minDestinationArea': absDest.isEmpty ? 0.0 : absDest.first,
      'p01DestinationArea': _percentile(absDest, 0.01),
      'p05DestinationArea': _percentile(absDest, 0.05),
      'medianDestinationArea': _percentile(absDest, 0.5),
      'minAreaRatio': minAreaRatio.isFinite ? minAreaRatio : 0.0,
      'jumpGt5': jumps.gt5,
      'jumpGt10': jumps.gt10,
      'maxSourceJump': jumps.maxDelta,
      'p95SourceJump': jumps.p95,
      'fieldJacobian': fieldJ,
      'meshVsField': {
        'continuousFieldHasFold': (fieldJ['fractionJLeZero'] as double) > 0,
        'meshHasMultiCoverage': multiCoverage > 0,
        'diagnosis': _meshFieldDiagnosis(fieldJ, multiCoverage),
      },
      'hotspots': hotspots,
    };
  }

  static String _meshFieldDiagnosis(
    Map<String, dynamic> fieldJ,
    int multiCoverage,
  ) {
    final fieldFold = (fieldJ['fractionJLeZero'] as double) > 0;
    final meshOverlap = multiCoverage > 0;
    if (fieldFold && meshOverlap) {
      return 'both_field_fold_and_mesh_overlap';
    }
    if (fieldFold) {
      return 'field_deformation_fold';
    }
    if (meshOverlap) {
      return 'triangulation_discretization_overlap';
    }
    return 'injective';
  }

  static Future<void> _writeCriticalMaps({
    required String outDir,
    required dynamic face,
    required TriMesh mesh,
    required InfluenceMap influenceMap,
    required PersonMask? personMask,
    required int width,
    required int height,
    required double intensity,
    required FaceMeshDeformationEngine engine,
    required Size imageSize,
  }) async {
    final label = _intensityLabel(intensity);
    final vertexField = engine.composeVertexField(
      parameters: {'face_slim': intensity},
      context: FaceAnatomyContext(
        face: face,
        imageSize: imageSize,
        mesh: mesh,
      ),
    );
    final payload = FaceMeshForwardPayload(
      mesh: mesh,
      vertexField: vertexField,
      influenceMap: influenceMap,
      personMask: personMask,
    );
    final built = _buildDeformedContext(
      payload: payload,
      width: width,
      height: height,
    );

    final coverageCount = _buildCoverageCountMap(
      mesh: built.deformedMesh,
      spatialIndex: built.spatialIndex,
      roi: built.roi,
      width: width,
      height: height,
    );

    _writeCoveragePng(
      '$outDir/debug-mesh-coverage-$label.png',
      coverageCount,
      built.roi,
      width,
      height,
    );
    _writeOverlapPng(
      '$outDir/debug-mesh-overlap-$label.png',
      built.deformedMesh,
      built.roi,
      width,
      height,
      coverageCount,
    );

    if ((intensity - 0.9).abs() < 0.01) {
      _writeJacobianPng(
        path: '$outDir/debug-field-jacobian-90.png',
        payload: payload,
        sourceMesh: built.sourceMesh,
        roi: built.roi,
        width: width,
        height: height,
      );
    }
  }

  static String _intensityLabel(double intensity) =>
      (intensity * 100).round().toString();

  static double? _findLastIntensity(
    List<Map<String, dynamic>> rows,
    bool Function(Map<String, dynamic>) predicate,
  ) {
    double? last;
    for (final r in rows) {
      if (predicate(r)) {
        last = (r['faceSlim'] as num).toDouble();
      }
    }
    return last;
  }

  static List<Map<String, dynamic>> _summarizeHotspots(
    List<Map<String, dynamic>> table,
  ) {
    final byName = <String, List<Map<String, dynamic>>>{};
    for (final row in table) {
      (byName[row['hotspot'] as String] ??= []).add(row);
    }

    return byName.entries.map((e) {
      final rows = e.value;
      double? firstOverlapInt;
      for (final r in rows) {
        if (r['spatialOverlap'] == true) {
          firstOverlapInt = (r['faceSlim'] as num).toDouble();
          break;
        }
      }
      final at90 = rows.firstWhere(
        (r) => ((r['faceSlim'] as num).toDouble() - 0.9).abs() < 0.01,
        orElse: () => rows.last,
      );
      final maxJumpRow = rows.reduce(
        (a, b) =>
            (a['regionMaxSourceJump'] as num).toDouble() >
                    (b['regionMaxSourceJump'] as num).toDouble()
                ? a
                : b,
      );
      return {
        'name': e.key,
        'firstSpatialOverlapIntensity': firstOverlapInt,
        'at90': {
          'overlapArea': at90['overlapArea'],
          'overlapRatioA': at90['overlapRatioA'],
          'overlapRatioB': at90['overlapRatioB'],
          'regionMultiCoveragePixels': at90['regionMultiCoveragePixels'],
          'regionMaxSourceJump': at90['regionMaxSourceJump'],
        },
        'maxRegionJumpIntensity': maxJumpRow['faceSlim'],
        'maxRegionJump': maxJumpRow['regionMaxSourceJump'],
        'sweepTable': rows
            .map(
              (r) => {
                'faceSlim': r['faceSlim'],
                'overlapArea': r['overlapArea'],
                'overlapRatioA': r['overlapRatioA'],
                'overlapRatioB': r['overlapRatioB'],
                'regionMultiCoverage': r['regionMultiCoveragePixels'],
                'regionMaxJump': r['regionMaxSourceJump'],
              },
            )
            .toList(),
      };
    }).toList();
  }

  // --- neighbor jumps (coherent source field) ---

  static ({
    int gt5,
    int gt10,
    double maxDelta,
    double p95,
    List<({int ax, int ay, int bx, int by, double delta})> pairs,
  }) _computeNeighborJumps({
    required TriMeshSpatialIndex spatialIndex,
    required TriMesh sourceMesh,
    required ({int x0, int y0, int x1, int y1}) roi,
    required int width,
    required int height,
  }) {
    final pixelCount = width * height;
    final srcX = Float32List(pixelCount)..fillRange(0, pixelCount, double.nan);
    final srcY = Float32List(pixelCount)..fillRange(0, pixelCount, double.nan);
    final hitMask = Uint8List(pixelCount);

    final rowTris = List<int?>.filled(roi.x1 - roi.x0 + 1, null);
    final rowSrcX = List<double?>.filled(roi.x1 - roi.x0 + 1, null);
    final rowSrcY = List<double?>.filled(roi.x1 - roi.x0 + 1, null);
    final topSrcX = List<double?>.filled(roi.x1 - roi.x0 + 1, null);
    final topSrcY = List<double?>.filled(roi.x1 - roi.x0 + 1, null);

    for (var y = roi.y0; y <= roi.y1; y++) {
      final py = y + 0.5;
      int? rowTri;
      for (var x = roi.x0; x <= roi.x1; x++) {
        final px = x + 0.5;
        final col = x - roi.x0;
        final tri = spatialIndex.locateTriangleIndex(
          px,
          py,
          coherenceTriangle: rowTri,
          verticalCoherenceTriangle: rowTris[col],
          sourceMesh: sourceMesh,
          preferSourceX: col > 0 ? rowSrcX[col - 1] : null,
          preferSourceY: col > 0 ? rowSrcY[col - 1] : null,
          verticalPreferSourceX: topSrcX[col],
          verticalPreferSourceY: topSrcY[col],
        );
        if (tri == null) {
          continue;
        }
        rowTri = tri;
        rowTris[col] = tri;
        final hit = spatialIndex.barycentricInTriangle(tri, px, py);
        if (hit == null) {
          continue;
        }
        final src = _sourceFromHit(sourceMesh, hit);
        if (src == null) {
          continue;
        }
        rowSrcX[col] = src.$1;
        rowSrcY[col] = src.$2;
        final p = y * width + x;
        srcX[p] = src.$1;
        srcY[p] = src.$2;
        hitMask[p] = 1;
      }
      for (var col = 0; col < rowTris.length; col++) {
        topSrcX[col] = rowSrcX[col];
        topSrcY[col] = rowSrcY[col];
      }
    }

    final pairs = <({int ax, int ay, int bx, int by, double delta})>[];
    final deltas = <double>[];

    void addPair(int ax, int ay, int bx, int by) {
      final pa = ay * width + ax;
      final pb = by * width + bx;
      if (hitMask[pa] == 0 || hitMask[pb] == 0) {
        return;
      }
      final dx = srcX[pa] - srcX[pb];
      final dy = srcY[pa] - srcY[pb];
      if (dx.isNaN || dy.isNaN) {
        return;
      }
      final delta = math.sqrt(dx * dx + dy * dy);
      pairs.add((ax: ax, ay: ay, bx: bx, by: by, delta: delta));
      deltas.add(delta);
    }

    for (var y = roi.y0; y <= roi.y1; y++) {
      for (var x = roi.x0; x <= roi.x1; x++) {
        if (x < roi.x1) {
          addPair(x, y, x + 1, y);
        }
        if (y < roi.y1) {
          addPair(x, y, x, y + 1);
        }
      }
    }

    deltas.sort();
    var gt5 = 0;
    var gt10 = 0;
    for (final d in deltas) {
      if (d > 5) {
        gt5++;
      }
      if (d > 10) {
        gt10++;
      }
    }

    return (
      gt5: gt5,
      gt10: gt10,
      maxDelta: deltas.isEmpty ? 0.0 : deltas.last,
      p95: _percentile(deltas, 0.95),
      pairs: pairs,
    );
  }

  // --- continuous field Jacobian ---

  static Map<String, dynamic> _computeFieldJacobian({
    required FaceMeshForwardPayload payload,
    required TriMesh sourceMesh,
    required ({int x0, int y0, int x1, int y1}) roi,
    required int width,
    required int height,
  }) {
    const gridStep = 4.0;
    const h = 2.0;

    final sourceIndex = TriMeshSpatialIndex(
      sourceMesh,
      imageWidth: width.toDouble(),
      imageHeight: height.toDouble(),
    );

    final vf = payload.vertexField;
    final vertexCount = FaceWarpFieldMetrics.safeVertexCount(
      field: vf,
      mesh: sourceMesh,
    );
    final supportWeights = GeometricSupport.computeWeights(
      mesh: sourceMesh,
      coreField: vf,
      influenceMap: payload.influenceMap,
      params: const DeformationSupportParams(),
      imageWidth: width,
      imageHeight: height,
      personMask: payload.personMask,
    );

    final jValues = <double>[];

    for (var y = roi.y0 + gridStep; y <= roi.y1 - gridStep; y += gridStep) {
      for (var x = roi.x0 + gridStep; x <= roi.x1 - gridStep; x += gridStep) {
        final j = _jacobianAt(
          sourceIndex: sourceIndex,
          vf: vf,
          supportWeights: supportWeights,
          vertexCount: vertexCount,
          px: x + 0.5,
          py: y + 0.5,
          h: h,
        );
        if (j != null) {
          jValues.add(j);
        }
      }
    }

    jValues.sort();
    var leZero = 0;
    var nearZero = 0;
    for (final j in jValues) {
      if (j <= 0) {
        leZero++;
      }
      if (j.abs() < 0.05) {
        nearZero++;
      }
    }
    final n = jValues.length;

    return {
      'minJ': jValues.isEmpty ? 0.0 : jValues.first,
      'p01J': _percentile(jValues, 0.01),
      'p05J': _percentile(jValues, 0.05),
      'medianJ': _percentile(jValues, 0.5),
      'fractionJLeZero': n > 0 ? leZero / n : 0.0,
      'fractionJNearZero': n > 0 ? nearZero / n : 0.0,
      'sampleCount': n,
    };
  }

  static double? _jacobianAt({
    required TriMeshSpatialIndex sourceIndex,
    required dynamic vf,
    required Float32List supportWeights,
    required int vertexCount,
    required double px,
    required double py,
    required double h,
  }) {
    Offset? sample(double x, double y) {
      final tri = sourceIndex.locateTriangleIndex(x, y);
      if (tri == null) {
        return null;
      }
      final hit = sourceIndex.barycentricInTriangle(tri, x, y);
      if (hit == null) {
        return null;
      }
      var dx = 0.0;
      var dy = 0.0;
      for (final (i, w) in [
        (hit.i0, hit.w0),
        (hit.i1, hit.w1),
        (hit.i2, hit.w2),
      ]) {
        if (i >= vertexCount) {
          return null;
        }
        final core = vf.displacementAt(i);
        final eff = FaceWarpFieldMetrics.effectiveDelta(
          core,
          supportWeights[i].clamp(0.0, 1.0),
        );
        dx += w * eff.dx;
        dy += w * eff.dy;
      }
      return Offset(dx, dy);
    }

    final c = sample(px, py);
    final xp = sample(px + h, py);
    final xm = sample(px - h, py);
    final yp = sample(px, py + h);
    final ym = sample(px, py - h);
    if (c == null || xp == null || xm == null || yp == null || ym == null) {
      return null;
    }

    final dudx = (xp.dx - xm.dx) / (2 * h);
    final dudy = (yp.dx - ym.dx) / (2 * h);
    final dvdx = (xp.dy - xm.dy) / (2 * h);
    final dvdy = (yp.dy - ym.dy) / (2 * h);

    return (1 + dudx) * (1 + dvdy) - dudy * dvdx;
  }

  // --- PNG writers ---

  static void _writeCoveragePng(
    String path,
    Uint16List coverageCount,
    ({int x0, int y0, int x1, int y1}) roi,
    int width,
    int height,
  ) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(0, 0, 0));
    for (var y = roi.y0; y <= roi.y1; y++) {
      for (var x = roi.x0; x <= roi.x1; x++) {
        final c = coverageCount[y * width + x];
        final (r, g, b) = switch (c) {
          0 => (0, 0, 0),
          1 => (30, 30, 30),
          2 => (255, 180, 0),
          _ => (255, 40, 40),
        };
        image.setPixelRgb(x, y, r, g, b);
      }
    }
    File(path).writeAsBytesSync(img.encodePng(image));
  }

  static void _writeOverlapPng(
    String path,
    TriMesh dest,
    ({int x0, int y0, int x1, int y1}) roi,
    int width,
    int height,
    Uint16List coverageCount,
  ) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(12, 12, 16));

    for (var t = 0; t < dest.triangleCount; t++) {
      final pts = _trianglePoints(dest, t);
      final minX = pts.map((p) => p.$1).reduce(math.min).floor();
      final maxX = pts.map((p) => p.$1).reduce(math.max).ceil();
      final minY = pts.map((p) => p.$2).reduce(math.min).floor();
      final maxY = pts.map((p) => p.$2).reduce(math.max).ceil();
      if (maxX < roi.x0 || minX > roi.x1 || maxY < roi.y0 || minY > roi.y1) {
        continue;
      }
      for (var e = 0; e < 3; e++) {
        _drawLineImage(
          image,
          pts[e].$1,
          pts[e].$2,
          pts[(e + 1) % 3].$1,
          pts[(e + 1) % 3].$2,
          40,
          40,
          50,
        );
      }
    }

    for (var y = roi.y0; y <= roi.y1; y++) {
      for (var x = roi.x0; x <= roi.x1; x++) {
        if (coverageCount[y * width + x] >= 2) {
          image.setPixelRgb(x, y, 255, 60, 60);
        }
      }
    }

    File(path).writeAsBytesSync(img.encodePng(image));
  }

  static void _writeJacobianPng({
    required String path,
    required FaceMeshForwardPayload payload,
    required TriMesh sourceMesh,
    required ({int x0, int y0, int x1, int y1}) roi,
    required int width,
    required int height,
  }) {
    const gridStep = 4.0;
    const h = 2.0;

    final sourceIndex = TriMeshSpatialIndex(
      sourceMesh,
      imageWidth: width.toDouble(),
      imageHeight: height.toDouble(),
    );
    final vf = payload.vertexField;
    final vertexCount = FaceWarpFieldMetrics.safeVertexCount(
      field: vf,
      mesh: sourceMesh,
    );
    final supportWeights = GeometricSupport.computeWeights(
      mesh: sourceMesh,
      coreField: vf,
      influenceMap: payload.influenceMap,
      params: const DeformationSupportParams(),
      imageWidth: width,
      imageHeight: height,
      personMask: payload.personMask,
    );

    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(0, 0, 0));

    for (var y = roi.y0 + gridStep; y <= roi.y1 - gridStep; y += gridStep) {
      for (var x = roi.x0 + gridStep; x <= roi.x1 - gridStep; x += gridStep) {
        final j = _jacobianAt(
          sourceIndex: sourceIndex,
          vf: vf,
          supportWeights: supportWeights,
          vertexCount: vertexCount,
          px: x + 0.5,
          py: y + 0.5,
          h: h,
        );
        if (j == null) {
          continue;
        }
        final r = j <= 0 ? 220 : (j < 0.05 ? 255 : 40);
        final g = j <= 0 ? 40 : (j < 0.05 ? 200 : 180);
        final b = j <= 0 ? 40 : (j < 0.05 ? 0 : 80);
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            image.setPixelRgb(
              (x + dx).round(),
              (y + dy).round(),
              r,
              g,
              b,
            );
          }
        }
      }
    }

    File(path).writeAsBytesSync(img.encodePng(image));
  }

  static void _drawLineImage(
    img.Image image,
    double x0,
    double y0,
    double x1,
    double y1,
    int r,
    int g,
    int b,
  ) {
    final steps = (math.max((x1 - x0).abs(), (y1 - y0).abs()) * 2).ceil();
    if (steps == 0) {
      return;
    }
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = (x0 + (x1 - x0) * t).round();
      final y = (y0 + (y1 - y0) * t).round();
      if (x >= 0 && y >= 0 && x < image.width && y < image.height) {
        image.setPixelRgb(x, y, r, g, b);
      }
    }
  }

  // --- geometry helpers ---

  static ({int pairCount, double maxArea}) _scanTriangleOverlaps(TriMesh mesh) {
    final n = mesh.triangleCount;
    final aabbs = List.generate(n, (t) => _triangleAabb(mesh, t));
    var pairCount = 0;
    var maxArea = 0.0;
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        if (!aabbs[i].overlaps(aabbs[j])) {
          continue;
        }
        final area = _triangleIntersectionArea(
          _trianglePoints(mesh, i),
          _trianglePoints(mesh, j),
        );
        if (area > 1e-6) {
          pairCount++;
          maxArea = math.max(maxArea, area);
        }
      }
    }
    return (pairCount: pairCount, maxArea: maxArea);
  }

  static Map<String, dynamic> _trianglePairOverlap(
    TriMesh dest,
    int triA,
    int triB,
  ) {
    final dA = _trianglePoints(dest, triA);
    final dB = _trianglePoints(dest, triB);
    final areaA = _signedAreaFromPoints(dA).abs();
    final areaB = _signedAreaFromPoints(dB).abs();
    final intersection = _triangleIntersectionArea(dA, dB);
    return {
      'destinationOverlapArea': intersection,
      'overlapRatioA': areaA > 1e-9 ? intersection / areaA : 0.0,
      'overlapRatioB': areaB > 1e-9 ? intersection / areaB : 0.0,
      'spatialOverlap': intersection > 1e-6,
    };
  }

  static Uint16List _buildCoverageCountMap({
    required TriMesh mesh,
    required TriMeshSpatialIndex spatialIndex,
    required ({int x0, int y0, int x1, int y1}) roi,
    required int width,
    required int height,
  }) {
    final counts = Uint16List(width * height);
    for (var t = 0; t < mesh.triangleCount; t++) {
      final pts = _trianglePoints(mesh, t);
      final minX =
          pts.map((p) => p.$1).reduce(math.min).floor().clamp(roi.x0, roi.x1);
      final maxX =
          pts.map((p) => p.$1).reduce(math.max).ceil().clamp(roi.x0, roi.x1);
      final minY =
          pts.map((p) => p.$2).reduce(math.min).floor().clamp(roi.y0, roi.y1);
      final maxY =
          pts.map((p) => p.$2).reduce(math.max).ceil().clamp(roi.y0, roi.y1);
      for (var y = minY; y <= maxY; y++) {
        final py = y + 0.5;
        for (var x = minX; x <= maxX; x++) {
          if (spatialIndex.barycentricInTriangle(t, x + 0.5, py) != null) {
            counts[y * width + x]++;
          }
        }
      }
    }
    return counts;
  }

  static Map<String, int> _coverageHistogram(
    Uint16List counts,
    ({int x0, int y0, int x1, int y1}) roi,
    int width,
  ) {
    final hist = <String, int>{'0': 0, '1': 0, '2': 0, '3+': 0};
    for (var y = roi.y0; y <= roi.y1; y++) {
      for (var x = roi.x0; x <= roi.x1; x++) {
        final c = counts[y * width + x];
        if (c == 0) {
          hist['0'] = hist['0']! + 1;
        } else if (c == 1) {
          hist['1'] = hist['1']! + 1;
        } else if (c == 2) {
          hist['2'] = hist['2']! + 1;
        } else {
          hist['3+'] = hist['3+']! + 1;
        }
      }
    }
    return hist;
  }

  static int _countOrientationInconsistencies(
    TriMesh mesh,
    List<double> signedAreas,
  ) {
    final edgeMap = <String, List<int>>{};
    for (var t = 0; t < mesh.triangleCount; t++) {
      final i0 = mesh.indices[t * 3];
      final i1 = mesh.indices[t * 3 + 1];
      final i2 = mesh.indices[t * 3 + 2];
      _addEdge(edgeMap, t, i0, i1);
      _addEdge(edgeMap, t, i1, i2);
      _addEdge(edgeMap, t, i2, i0);
    }
    var flips = 0;
    for (final tris in edgeMap.values) {
      if (tris.length != 2) {
        continue;
      }
      final a = signedAreas[tris[0]];
      final b = signedAreas[tris[1]];
      if (a.sign != b.sign && a.abs() > 0.5 && b.abs() > 0.5) {
        flips++;
      }
    }
    return flips;
  }

  static void _addEdge(
    Map<String, List<int>> map,
    int tri,
    int a,
    int b,
  ) {
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    (map['$lo-$hi'] ??= <int>[]).add(tri);
  }

  static List<(double, double)> _trianglePoints(TriMesh mesh, int tri) {
    final i0 = mesh.indices[tri * 3];
    final i1 = mesh.indices[tri * 3 + 1];
    final i2 = mesh.indices[tri * 3 + 2];
    return [
      (mesh.vertices[i0 * 2], mesh.vertices[i0 * 2 + 1]),
      (mesh.vertices[i1 * 2], mesh.vertices[i1 * 2 + 1]),
      (mesh.vertices[i2 * 2], mesh.vertices[i2 * 2 + 1]),
    ];
  }

  static _Aabb _triangleAabb(TriMesh mesh, int tri) {
    final pts = _trianglePoints(mesh, tri);
    return _Aabb(
      pts.map((p) => p.$1).reduce(math.min),
      pts.map((p) => p.$1).reduce(math.max),
      pts.map((p) => p.$2).reduce(math.min),
      pts.map((p) => p.$2).reduce(math.max),
    );
  }

  static double _signedAreaFromPoints(List<(double, double)> pts) {
    final a = pts[0];
    final b = pts[1];
    final c = pts[2];
    return 0.5 *
        ((b.$1 - a.$1) * (c.$2 - a.$2) - (c.$1 - a.$1) * (b.$2 - a.$2));
  }

  static double _triangleIntersectionArea(
    List<(double, double)> triA,
    List<(double, double)> triB,
  ) {
    var poly = List<(double, double)>.from(triA);
    for (var i = 0; i < 3; i++) {
      poly = _clipPolygonByEdge(poly, triB[i], triB[(i + 1) % 3]);
      if (poly.isEmpty) {
        return 0.0;
      }
    }
    return _polygonArea(poly).abs();
  }

  static List<(double, double)> _clipPolygonByEdge(
    List<(double, double)> poly,
    (double, double) edgeStart,
    (double, double) edgeEnd,
  ) {
    if (poly.isEmpty) {
      return poly;
    }
    final output = <(double, double)>[];
    for (var i = 0; i < poly.length; i++) {
      final current = poly[i];
      final previous = poly[(i + poly.length - 1) % poly.length];
      final currInside = _isInsideEdge(current, edgeStart, edgeEnd);
      final prevInside = _isInsideEdge(previous, edgeStart, edgeEnd);
      if (currInside) {
        if (!prevInside) {
          final isect = _lineLineIntersection(previous, current, edgeStart, edgeEnd);
          if (isect != null) {
            output.add(isect);
          }
        }
        output.add(current);
      } else if (prevInside) {
        final isect = _lineLineIntersection(previous, current, edgeStart, edgeEnd);
        if (isect != null) {
          output.add(isect);
        }
      }
    }
    return output;
  }

  static bool _isInsideEdge(
    (double, double) p,
    (double, double) edgeStart,
    (double, double) edgeEnd,
  ) {
    return _cross(
          edgeEnd.$1 - edgeStart.$1,
          edgeEnd.$2 - edgeStart.$2,
          p.$1 - edgeStart.$1,
          p.$2 - edgeStart.$2,
        ) >=
        -1e-9;
  }

  static (double, double)? _lineLineIntersection(
    (double, double) p1,
    (double, double) p2,
    (double, double) p3,
    (double, double) p4,
  ) {
    final x1 = p1.$1;
    final y1 = p1.$2;
    final x2 = p2.$1;
    final y2 = p2.$2;
    final x3 = p3.$1;
    final y3 = p3.$2;
    final x4 = p4.$1;
    final y4 = p4.$2;
    final denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
    if (denom.abs() < 1e-12) {
      return null;
    }
    final t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / denom;
    return (x1 + t * (x2 - x1), y1 + t * (y2 - y1));
  }

  static double _cross(double ax, double ay, double bx, double by) =>
      ax * by - ay * bx;

  static double _polygonArea(List<(double, double)> poly) {
    if (poly.length < 3) {
      return 0.0;
    }
    var sum = 0.0;
    for (var i = 0; i < poly.length; i++) {
      final p0 = poly[i];
      final p1 = poly[(i + 1) % poly.length];
      sum += p0.$1 * p1.$2 - p1.$1 * p0.$2;
    }
    return 0.5 * sum;
  }

  static (double, double)? _sourceFromHit(
    TriMesh sourceMesh,
    BarycentricHit hit,
  ) {
    final s0 = FaceWarpUtils.vertexAt(sourceMesh, hit.i0);
    final s1 = FaceWarpUtils.vertexAt(sourceMesh, hit.i1);
    final s2 = FaceWarpUtils.vertexAt(sourceMesh, hit.i2);
    if (s0 == null || s1 == null || s2 == null) {
      return null;
    }
    return (
      hit.w0 * s0.dx + hit.w1 * s1.dx + hit.w2 * s2.dx,
      hit.w0 * s0.dy + hit.w1 * s1.dy + hit.w2 * s2.dy,
    );
  }

  static ({
    TriMesh sourceMesh,
    TriMesh deformedMesh,
    TriMeshSpatialIndex spatialIndex,
    ({int x0, int y0, int x1, int y1}) roi,
  }) _buildDeformedContext({
    required FaceMeshForwardPayload payload,
    required int width,
    required int height,
  }) {
    final mesh = payload.mesh;
    final vf = payload.vertexField;
    final vertexCount = FaceWarpFieldMetrics.safeVertexCount(
      field: vf,
      mesh: mesh,
    );
    final supportWeights = GeometricSupport.computeWeights(
      mesh: mesh,
      coreField: vf,
      influenceMap: payload.influenceMap,
      params: const DeformationSupportParams(),
      imageWidth: width,
      imageHeight: height,
      personMask: payload.personMask,
    );

    final deformedVerts = Float32List.fromList(mesh.vertices);
    for (var i = 0; i < vertexCount; i++) {
      final core = vf.displacementAt(i);
      final eff = FaceWarpFieldMetrics.effectiveDelta(
        core,
        supportWeights[i].clamp(0.0, 1.0),
      );
      deformedVerts[i * 2] += eff.dx;
      deformedVerts[i * 2 + 1] += eff.dy;
    }

    final deformedMesh = TriMesh(
      vertices: deformedVerts,
      uvs: mesh.uvs,
      indices: mesh.indices,
      regionBuffers: mesh.regionBuffers,
      isPartial: mesh.isPartial,
    );

    final spatialIndex = TriMeshSpatialIndex(
      deformedMesh,
      imageWidth: width.toDouble(),
      imageHeight: height.toDouble(),
    );
    final roi = _roiFromDeformedMesh(deformedMesh, width, height);

    return (
      sourceMesh: mesh,
      deformedMesh: deformedMesh,
      spatialIndex: spatialIndex,
      roi: roi,
    );
  }

  static ({
    int x0,
    int y0,
    int x1,
    int y1,
  }) _roiFromDeformedMesh(
    TriMesh deformedMesh,
    int width,
    int height,
  ) {
    var minX = width;
    var minY = height;
    var maxX = 0;
    var maxY = 0;
    for (var i = 0; i < deformedMesh.vertices.length; i += 2) {
      final x = deformedMesh.vertices[i];
      final y = deformedMesh.vertices[i + 1];
      minX = math.min(minX, x.floor());
      minY = math.min(minY, y.floor());
      maxX = math.max(maxX, x.ceil());
      maxY = math.max(maxY, y.ceil());
    }
    const margin = 3;
    return (
      x0: (minX - margin).clamp(0, width - 1),
      y0: (minY - margin).clamp(0, height - 1),
      x1: (maxX + margin).clamp(0, width - 1),
      y1: (maxY + margin).clamp(0, height - 1),
    );
  }

  static double _percentile(List<double> sorted, double p) {
    if (sorted.isEmpty) {
      return 0.0;
    }
    final idx = ((sorted.length - 1) * p).round().clamp(0, sorted.length - 1);
    return sorted[idx];
  }
}

class _Aabb {
  const _Aabb(this.minX, this.maxX, this.minY, this.maxY);

  final double minX;
  final double maxX;
  final double minY;
  final double maxY;

  bool overlaps(_Aabb o) =>
      minX <= o.maxX && maxX >= o.minX && minY <= o.maxY && maxY >= o.minY;
}
