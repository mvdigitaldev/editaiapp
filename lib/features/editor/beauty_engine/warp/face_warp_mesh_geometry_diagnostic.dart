import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../debug/agent_debug_log.dart';
import '../mesh/tri_mesh_spatial_index.dart';
import '../models/tri_mesh.dart';
import 'face_mesh_forward_warp.dart';
import 'face_warp_render_contract.dart';
import 'face_warp_renderer.dart' show GeometricSupport;

/// Resultado do diagnóstico Fase 5 — geometria da destination mesh.
class FaceWarpMeshGeometryDiagnosticResult {
  const FaceWarpMeshGeometryDiagnosticResult({
    required this.summary,
    required this.overlapHotspotPng,
    required this.orientationPng,
    required this.coverageCountPng,
    required this.summaryJsonPath,
  });

  final Map<String, dynamic> summary;
  final String overlapHotspotPng;
  final String orientationPng;
  final String coverageCountPng;
  final String summaryJsonPath;
}

/// Fase 5 — overlap, fold, degenerados, gaps e multi-coverage da malha deformada.
///
/// Somente [kDebugMode]. Não altera locate/remap.
abstract final class FaceWarpMeshGeometryDiagnostic {
  FaceWarpMeshGeometryDiagnostic._();

  static const _defaultOutputDir =
      '/Users/leonardo/Documents/Projetos/editaiapp/.cursor';

  static const _degenerateThresholds = [0.01, 0.1, 0.5, 1.0, 2.0];

  static const _hotspots = [
    (
      name: 'jaw_446_469',
      x0: 220,
      y0: 580,
      x1: 250,
      y1: 620,
      triangleIds: {445, 446, 469, 471, 472},
    ),
    (
      name: 'cheek_672_558',
      x0: 405,
      y0: 555,
      x1: 420,
      y1: 570,
      triangleIds: {558, 672},
    ),
    (
      name: 'brow_149_154',
      x0: 162,
      y0: 438,
      x1: 175,
      y1: 448,
      triangleIds: {149, 154},
    ),
  ];

  static Future<FaceWarpMeshGeometryDiagnosticResult?> run({
    required FaceMeshForwardPayload payload,
    required int width,
    required int height,
    String? worstNeighborsJsonlPath,
    String runId = 'mesh-geo-real-90',
    String? outputDirectory,
  }) async {
    if (!kDebugMode) {
      return null;
    }

    try {
      final outDir = outputDirectory ?? _defaultOutputDir;
      Directory(outDir).createSync(recursive: true);

      final built = _buildDeformedContext(
        payload: payload,
        width: width,
        height: height,
      );
      final dest = built.deformedMesh;
      final src = built.sourceMesh;
      final triCount = dest.triangleCount;

      final destAreas = List<double>.generate(triCount, (t) => _signedArea(dest, t));
      final srcAreas = List<double>.generate(triCount, (t) => _signedArea(src, t));
      final absSrcAreas = srcAreas.map((a) => a.abs()).toList()..sort();
      final absDestAreas = destAreas.map((a) => a.abs()).toList()..sort();

      final degenerateCounts = <String, int>{};
      for (final th in _degenerateThresholds) {
        degenerateCounts['lt$th'] =
            absDestAreas.where((a) => a < th).length;
      }

      final orientationInconsistencies =
          _countOrientationInconsistencies(dest, destAreas);

      final coverageCount = _buildCoverageCountMap(
        mesh: dest,
        spatialIndex: built.spatialIndex,
        roi: built.roi,
        width: width,
        height: height,
      );

      final coverageHistogram = _coverageHistogram(coverageCount, built.roi, width);

      final jsonlPath = worstNeighborsJsonlPath ??
          '$outDir/debug-worst-neighbor-discontinuities.jsonl';
      final neighborPairs = _loadNeighborPairs(jsonlPath);

      final gt10Pairs = neighborPairs
          .where((p) => (p['deltaSource'] as num).toDouble() > 10)
          .toList();

      final triangleAnalyses = <Map<String, dynamic>>[];
      final jumpCorrelations = <Map<String, dynamic>>[];
      var spatialOverlappingPairs = 0;
      var maxOverlapArea = 0.0;
      var jumpGt10WithOverlap = 0;
      var jumpGt10WithoutOverlap = 0;

      final analyzedPairKeys = <String>{};

      for (final pair in gt10Pairs) {
        final triA = (pair['a'] as Map)['triangleId'] as int;
        final triB = (pair['b'] as Map)['triangleId'] as int;
        final key = triA <= triB ? '$triA-$triB' : '$triB-$triA';
        if (!analyzedPairKeys.contains(key)) {
          analyzedPairKeys.add(key);
          final overlap = _analyzeTrianglePair(
            dest: dest,
            src: src,
            triA: triA,
            triB: triB,
          );
          triangleAnalyses.add(overlap);
          if (overlap['spatialOverlap'] == true) {
            spatialOverlappingPairs++;
          }
          final ia = (overlap['destinationOverlapArea'] as num?)?.toDouble() ?? 0;
          if (ia > maxOverlapArea) {
            maxOverlapArea = ia;
          }
        }

        final ax = (pair['a'] as Map)['x'] as int;
        final ay = (pair['a'] as Map)['y'] as int;
        final bx = (pair['b'] as Map)['x'] as int;
        final by = (pair['b'] as Map)['y'] as int;
        final pa = ay * width + ax;
        final pb = by * width + bx;
        final covA = coverageCount[pa];
        final covB = coverageCount[pb];

        final overlap = _analyzeTrianglePair(
          dest: dest,
          src: src,
          triA: triA,
          triB: triB,
        );
        final spatial = overlap['spatialOverlap'] == true ||
            covA >= 2 ||
            covB >= 2;

        if (spatial) {
          jumpGt10WithOverlap++;
        } else {
          jumpGt10WithoutOverlap++;
        }

        jumpCorrelations.add({
          'pixelA': {'x': ax, 'y': ay},
          'pixelB': {'x': bx, 'y': by},
          'deltaSource': pair['deltaSource'],
          'coverageA': covA,
          'coverageB': covB,
          'triangleA': triA,
          'triangleB': triB,
          'spatialOverlap': spatial,
          'intersectionArea': overlap['destinationOverlapArea'],
          'overlapRatioA': overlap['overlapRatioA'],
          'overlapRatioB': overlap['overlapRatioB'],
          'orientationA': overlap['orientationA'],
          'orientationB': overlap['orientationB'],
        });
      }

      final gt10Total = jumpGt10WithOverlap + jumpGt10WithoutOverlap;
      final percentWithOverlap = gt10Total > 0
          ? 100.0 * jumpGt10WithOverlap / gt10Total
          : 0.0;
      final percentWithoutOverlap = gt10Total > 0
          ? 100.0 * jumpGt10WithoutOverlap / gt10Total
          : 0.0;

      final pixelsCoveredBy2Plus = _countPixelsWithMinCoverage(
        coverageCount,
        built.roi,
        width,
        minCoverage: 2,
      );

      final hotspotSummaries = <Map<String, dynamic>>[];
      for (final hs in _hotspots) {
        hotspotSummaries.add(
          _analyzeHotspotRegion(
            name: hs.name,
            x0: hs.x0,
            y0: hs.y0,
            x1: hs.x1,
            y1: hs.y1,
            triangleIds: hs.triangleIds,
            dest: dest,
            src: src,
            coverageCount: coverageCount,
            width: width,
            jumpPairs: gt10Pairs,
          ),
        );
      }

      final overlapHotspotPng = '$outDir/debug-mesh-overlap-hotspot.png';
      final orientationPng = '$outDir/debug-mesh-orientation.png';
      final coverageCountPng = '$outDir/debug-destination-coverage-count.png';

      _writeOverlapHotspotPng(
        path: overlapHotspotPng,
        dest: dest,
        width: width,
        height: height,
        jumpPairs: gt10Pairs,
        primaryHotspot: _hotspots.first,
      );
      _writeOrientationPng(
        path: orientationPng,
        dest: dest,
        destAreas: destAreas,
        roi: built.roi,
        width: width,
        height: height,
      );
      _writeCoverageCountPng(
        path: coverageCountPng,
        coverageCount: coverageCount,
        roi: built.roi,
        width: width,
        height: height,
        jumpPairs: gt10Pairs,
      );

      final maxJump = gt10Pairs.isEmpty
          ? 0.0
          : gt10Pairs
              .map((p) => (p['deltaSource'] as num).toDouble())
              .reduce(math.max);

      final summary = {
        'degenerateTriangles': degenerateCounts,
        'destinationAreaStats': {
          'min': absDestAreas.isEmpty ? 0.0 : absDestAreas.first,
          'p01': _percentile(absDestAreas, 0.01),
          'p05': _percentile(absDestAreas, 0.05),
          'median': _percentile(absDestAreas, 0.5),
          'p95': _percentile(absDestAreas, 0.95),
        },
        'sourceAreaStats': {
          'min': absSrcAreas.isEmpty ? 0.0 : absSrcAreas.first,
          'median': _percentile(absSrcAreas, 0.5),
          'p95': _percentile(absSrcAreas, 0.95),
        },
        'orientationInconsistencies': orientationInconsistencies,
        'spatialOverlappingPairs': spatialOverlappingPairs,
        'pixelsCoveredBy2PlusTriangles': pixelsCoveredBy2Plus,
        'coverageHistogramGlobal': coverageHistogram,
        'jumpGt10WithOverlap': jumpGt10WithOverlap,
        'jumpGt10WithoutOverlap': jumpGt10WithoutOverlap,
        'percentJumpGt10WithOverlap': percentWithOverlap,
        'percentJumpGt10WithoutOverlap': percentWithoutOverlap,
        'maxOverlapArea': maxOverlapArea,
        'maxSourceJump': maxJump,
        'trianglePairAnalysesGt10': triangleAnalyses,
        'jumpCorrelationsGt10': jumpCorrelations,
        'hotspots': hotspotSummaries,
      };

      final summaryJsonPath = '$outDir/phase5_mesh_geometry_summary.json';
      File(summaryJsonPath).writeAsStringSync(jsonEncode(summary));

      AgentDebugLog.write(
        location: 'face_warp_mesh_geometry_diagnostic.dart:run',
        message: 'phase5_mesh_geometry_diagnostic',
        hypothesisId: 'P5MG',
        runId: runId,
        phase: '5',
        data: {
          'degenerateTriangles': degenerateCounts,
          'orientationInconsistencies': orientationInconsistencies,
          'spatialOverlappingPairs': spatialOverlappingPairs,
          'pixelsCoveredBy2PlusTriangles': pixelsCoveredBy2Plus,
          'jumpGt10WithOverlap': jumpGt10WithOverlap,
          'jumpGt10WithoutOverlap': jumpGt10WithoutOverlap,
          'maxOverlapArea': maxOverlapArea,
          'maxSourceJump': maxJump,
          'hotspots': hotspotSummaries
              .map((h) => {'name': h['name'], 'coverageHistogram': h['coverageHistogram']})
              .toList(),
        },
      );

      return FaceWarpMeshGeometryDiagnosticResult(
        summary: summary,
        overlapHotspotPng: overlapHotspotPng,
        orientationPng: orientationPng,
        coverageCountPng: coverageCountPng,
        summaryJsonPath: summaryJsonPath,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('FaceWarpMeshGeometryDiagnostic failed: $e\n$st');
      }
      return null;
    }
  }

  static List<Map<String, dynamic>> _loadNeighborPairs(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      return [];
    }
    return file
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty)
        .map((l) => jsonDecode(l) as Map<String, dynamic>)
        .toList();
  }

  static Map<String, dynamic> _analyzeTrianglePair({
    required TriMesh dest,
    required TriMesh src,
    required int triA,
    required int triB,
  }) {
    final dA = _trianglePoints(dest, triA);
    final dB = _trianglePoints(dest, triB);
    final sA = _trianglePoints(src, triA);
    final sB = _trianglePoints(src, triB);

    final areaA = _signedAreaFromPoints(dA);
    final areaB = _signedAreaFromPoints(dB);
    final srcAreaA = _signedAreaFromPoints(sA);
    final srcAreaB = _signedAreaFromPoints(sB);

    final aabbOverlap = _aabbOverlap(dA, dB);
    final intersectionArea = _triangleIntersectionArea(dA, dB);
    final spatialOverlap = intersectionArea > 1e-6;

    final centroidA = _centroid(dA);
    final centroidB = _centroid(dB);

    return {
      'triangleA': triA,
      'triangleB': triB,
      'destinationVerticesA': dA.map((p) => [p.$1, p.$2]).toList(),
      'destinationVerticesB': dB.map((p) => [p.$1, p.$2]).toList(),
      'sourceVerticesA': sA.map((p) => [p.$1, p.$2]).toList(),
      'sourceVerticesB': sB.map((p) => [p.$1, p.$2]).toList(),
      'destinationAreaA': areaA,
      'destinationAreaB': areaB,
      'sourceAreaA': srcAreaA,
      'sourceAreaB': srcAreaB,
      'orientationA': areaA >= 0 ? 'positive' : 'negative',
      'orientationB': areaB >= 0 ? 'positive' : 'negative',
      'destinationCentroidA': centroidA,
      'destinationCentroidB': centroidB,
      'aabbOverlap': aabbOverlap,
      'destinationOverlapArea': intersectionArea,
      'spatialOverlap': spatialOverlap,
      'overlapRatioA': areaA.abs() > 1e-9 ? intersectionArea / areaA.abs() : 0.0,
      'overlapRatioB': areaB.abs() > 1e-9 ? intersectionArea / areaB.abs() : 0.0,
      'vertexContainment': {
        'aVertexInB': _verticesInside(dA, dB),
        'bVertexInA': _verticesInside(dB, dA),
      },
      'edgeIntersections': _edgeIntersectionCount(dA, dB),
    };
  }

  static Map<String, dynamic> _analyzeHotspotRegion({
    required String name,
    required int x0,
    required int y0,
    required int x1,
    required int y1,
    required Set<int> triangleIds,
    required TriMesh dest,
    required TriMesh src,
    required Uint16List coverageCount,
    required int width,
    required List<Map<String, dynamic>> jumpPairs,
  }) {
    final hist = <String, int>{
      '0': 0,
      '1': 0,
      '2': 0,
      '3+': 0,
    };
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final c = coverageCount[y * width + x];
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

    final triAnalyses = <Map<String, dynamic>>[];
    final ids = triangleIds.toList()..sort();
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        triAnalyses.add(
          _analyzeTrianglePair(
            dest: dest,
            src: src,
            triA: ids[i],
            triB: ids[j],
          ),
        );
      }
    }

    final jumpsInRegion = jumpPairs.where((p) {
      final ax = (p['a'] as Map)['x'] as int;
      final ay = (p['a'] as Map)['y'] as int;
      final bx = (p['b'] as Map)['x'] as int;
      final by = (p['b'] as Map)['y'] as int;
      return (ax >= x0 && ax <= x1 && ay >= y0 && ay <= y1) ||
          (bx >= x0 && bx <= x1 && by >= y0 && by <= y1);
    }).length;

    final triInfo = <Map<String, dynamic>>[];
    for (final t in ids) {
      final area = _signedArea(dest, t);
      triInfo.add({
        'triangleId': t,
        'destinationSignedArea': area,
        'destinationAbsArea': area.abs(),
        'sourceSignedArea': _signedArea(src, t),
        'orientation': area >= 0 ? 'positive' : 'negative',
        'vertices': _trianglePoints(dest, t).map((p) => [p.$1, p.$2]).toList(),
      });
    }

    return {
      'name': name,
      'region': {'x0': x0, 'y0': y0, 'x1': x1, 'y1': y1},
      'coverageHistogram': hist,
      'jumpPairsInRegion': jumpsInRegion,
      'triangleInfo': triInfo,
      'pairOverlaps': triAnalyses,
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
      final minX = pts.map((p) => p.$1).reduce(math.min).floor().clamp(roi.x0, roi.x1);
      final maxX = pts.map((p) => p.$1).reduce(math.max).ceil().clamp(roi.x0, roi.x1);
      final minY = pts.map((p) => p.$2).reduce(math.min).floor().clamp(roi.y0, roi.y1);
      final maxY = pts.map((p) => p.$2).reduce(math.max).ceil().clamp(roi.y0, roi.y1);

      for (var y = minY; y <= maxY; y++) {
        final py = y + 0.5;
        for (var x = minX; x <= maxX; x++) {
          final px = x + 0.5;
          if (spatialIndex.barycentricInTriangle(t, px, py) != null) {
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

  static int _countPixelsWithMinCoverage(
    Uint16List counts,
    ({int x0, int y0, int x1, int y1}) roi,
    int width, {
    required int minCoverage,
  }) {
    var n = 0;
    for (var y = roi.y0; y <= roi.y1; y++) {
      for (var x = roi.x0; x <= roi.x1; x++) {
        if (counts[y * width + x] >= minCoverage) {
          n++;
        }
      }
    }
    return n;
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

  static void _writeOverlapHotspotPng({
    required String path,
    required TriMesh dest,
    required int width,
    required int height,
    required List<Map<String, dynamic>> jumpPairs,
    required ({String name, int x0, int y0, int x1, int y1, Set<int> triangleIds})
        primaryHotspot,
  }) {
    const scale = 4;
    final hs = primaryHotspot;
    final rw = (hs.x1 - hs.x0 + 1) * scale;
    final rh = (hs.y1 - hs.y0 + 1) * scale;
    final image = img.Image(width: rw, height: rh);
    img.fill(image, color: img.ColorRgb8(20, 20, 24));

    (double, double) toLocal(double x, double y) => (
          (x - hs.x0) * scale,
          (y - hs.y0) * scale,
        );

    for (final tri in hs.triangleIds) {
      final pts = _trianglePoints(dest, tri);
      final color = switch (tri) {
        446 => img.ColorRgb8(255, 80, 80),
        469 => img.ColorRgb8(80, 180, 255),
        445 => img.ColorRgb8(255, 200, 60),
        472 => img.ColorRgb8(180, 80, 255),
        471 => img.ColorRgb8(80, 255, 140),
        _ => img.ColorRgb8(160, 160, 160),
      };
      for (var e = 0; e < 3; e++) {
        final p0 = pts[e];
        final p1 = pts[(e + 1) % 3];
        final l0 = toLocal(p0.$1, p0.$2);
        final l1 = toLocal(p1.$1, p1.$2);
        _drawLine(image, l0.$1, l0.$2, l1.$1, l1.$2, color, thickness: 2);
      }
      final c = _centroid(pts);
      final lc = toLocal(c[0], c[1]);
      _drawLabel(image, lc.$1.toInt(), lc.$2.toInt(), '$tri', color);
    }

    for (final pair in jumpPairs) {
      if ((pair['deltaSource'] as num).toDouble() <= 10) {
        continue;
      }
      final ax = (pair['a'] as Map)['x'] as int;
      final ay = (pair['a'] as Map)['y'] as int;
      final bx = (pair['b'] as Map)['x'] as int;
      final by = (pair['b'] as Map)['y'] as int;
      if (ax < hs.x0 || ax > hs.x1 || ay < hs.y0 || ay > hs.y1) {
        continue;
      }
      final la = toLocal(ax + 0.5, ay + 0.5);
      final lb = toLocal(bx + 0.5, by + 0.5);
      _drawLine(
        image,
        la.$1,
        la.$2,
        lb.$1,
        lb.$2,
        img.ColorRgb8(255, 255, 0),
        thickness: 1,
      );
      _fillSquare(image, la.$1.toInt(), la.$2.toInt(), img.ColorRgb8(255, 0, 255));
      _fillSquare(image, lb.$1.toInt(), lb.$2.toInt(), img.ColorRgb8(255, 128, 0));
    }

    File(path).writeAsBytesSync(img.encodePng(image));
  }

  static void _writeOrientationPng({
    required String path,
    required TriMesh dest,
    required List<double> destAreas,
    required ({int x0, int y0, int x1, int y1}) roi,
    required int width,
    required int height,
  }) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(10, 10, 12));

    for (var t = 0; t < dest.triangleCount; t++) {
      final pts = _trianglePoints(dest, t);
      final minX = pts.map((p) => p.$1).reduce(math.min).floor();
      final maxX = pts.map((p) => p.$1).reduce(math.max).ceil();
      final minY = pts.map((p) => p.$2).reduce(math.min).floor();
      final maxY = pts.map((p) => p.$2).reduce(math.max).ceil();
      if (maxX < roi.x0 || minX > roi.x1 || maxY < roi.y0 || minY > roi.y1) {
        continue;
      }

      final area = destAreas[t];
      final absA = area.abs();
      img.ColorRgb8 color;
      if (absA < 0.5) {
        color = img.ColorRgb8(255, 0, 255);
      } else if (area >= 0) {
        color = img.ColorRgb8(40, 90, 220);
      } else {
        color = img.ColorRgb8(220, 50, 40);
      }

      for (var y = minY.clamp(roi.y0, roi.y1); y <= maxY.clamp(roi.y0, roi.y1); y++) {
        for (var x = minX.clamp(roi.x0, roi.x1); x <= maxX.clamp(roi.x0, roi.x1); x++) {
          if (_pointInTriangle(x + 0.5, y + 0.5, pts)) {
            image.setPixelRgb(x, y, color.r.toInt(), color.g.toInt(), color.b.toInt());
          }
        }
      }
    }

    File(path).writeAsBytesSync(img.encodePng(image));
  }

  static void _writeCoverageCountPng({
    required String path,
    required Uint16List coverageCount,
    required ({int x0, int y0, int x1, int y1}) roi,
    required int width,
    required int height,
    required List<Map<String, dynamic>> jumpPairs,
  }) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(0, 0, 0));

    for (var y = roi.y0; y <= roi.y1; y++) {
      for (var x = roi.x0; x <= roi.x1; x++) {
        final c = coverageCount[y * width + x];
        final color = switch (c) {
          0 => img.ColorRgb8(0, 0, 0),
          1 => img.ColorRgb8(30, 30, 30),
          2 => img.ColorRgb8(255, 180, 0),
          _ => img.ColorRgb8(255, 40, 40),
        };
        image.setPixelRgb(x, y, color.r.toInt(), color.g.toInt(), color.b.toInt());
      }
    }

    for (final pair in jumpPairs) {
      if ((pair['deltaSource'] as num).toDouble() <= 10) {
        continue;
      }
      for (final key in ['a', 'b']) {
        final p = pair[key] as Map;
        final x = p['x'] as int;
        final y = p['y'] as int;
        image.setPixelRgb(x, y, 255, 255, 255);
      }
    }

    File(path).writeAsBytesSync(img.encodePng(image));
  }

  // --- geometry helpers ---

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

  static double _signedArea(TriMesh mesh, int tri) {
    return _signedAreaFromPoints(_trianglePoints(mesh, tri));
  }

  static double _signedAreaFromPoints(List<(double, double)> pts) {
    final a = pts[0];
    final b = pts[1];
    final c = pts[2];
    return 0.5 *
        ((b.$1 - a.$1) * (c.$2 - a.$2) - (c.$1 - a.$1) * (b.$2 - a.$2));
  }

  static List<double> _centroid(List<(double, double)> pts) {
    var sx = 0.0;
    var sy = 0.0;
    for (final p in pts) {
      sx += p.$1;
      sy += p.$2;
    }
    return [sx / pts.length, sy / pts.length];
  }

  static bool _aabbOverlap(
    List<(double, double)> a,
    List<(double, double)> b,
  ) {
    final ax0 = a.map((p) => p.$1).reduce(math.min);
    final ax1 = a.map((p) => p.$1).reduce(math.max);
    final ay0 = a.map((p) => p.$2).reduce(math.min);
    final ay1 = a.map((p) => p.$2).reduce(math.max);
    final bx0 = b.map((p) => p.$1).reduce(math.min);
    final bx1 = b.map((p) => p.$1).reduce(math.max);
    final by0 = b.map((p) => p.$2).reduce(math.min);
    final by1 = b.map((p) => p.$2).reduce(math.max);
    return ax0 <= bx1 && ax1 >= bx0 && ay0 <= by1 && ay1 >= by0;
  }

  static bool _pointInTriangle(
    double px,
    double py,
    List<(double, double)> tri,
  ) {
    final a = tri[0];
    final b = tri[1];
    final c = tri[2];
    final d1 = _cross(b.$1 - a.$1, b.$2 - a.$2, px - a.$1, py - a.$2);
    final d2 = _cross(c.$1 - b.$1, c.$2 - b.$2, px - b.$1, py - b.$2);
    final d3 = _cross(a.$1 - c.$1, a.$2 - c.$2, px - c.$1, py - c.$2);
    final hasNeg = d1 < 0 || d2 < 0 || d3 < 0;
    final hasPos = d1 > 0 || d2 > 0 || d3 > 0;
    return !(hasNeg && hasPos);
  }

  static double _cross(double ax, double ay, double bx, double by) => ax * by - ay * bx;

  static List<int> _verticesInside(
    List<(double, double)> verts,
    List<(double, double)> tri,
  ) {
    final inside = <int>[];
    for (var i = 0; i < verts.length; i++) {
      if (_pointInTriangle(verts[i].$1, verts[i].$2, tri)) {
        inside.add(i);
      }
    }
    return inside;
  }

  static int _edgeIntersectionCount(
    List<(double, double)> a,
    List<(double, double)> b,
  ) {
    var count = 0;
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        if (_segmentIntersect(a[i], a[(i + 1) % 3], b[j], b[(j + 1) % 3]) !=
            null) {
          count++;
        }
      }
    }
    return count;
  }

  static (double, double)? _segmentIntersect(
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
    final u = ((x1 - x3) * (y1 - y2) - (y1 - y3) * (x1 - x2)) / denom;
    if (t < 0 || t > 1 || u < 0 || u > 1) {
      return null;
    }
    return (x1 + t * (x2 - x1), y1 + t * (y2 - y1));
  }

  static double _triangleIntersectionArea(
    List<(double, double)> triA,
    List<(double, double)> triB,
  ) {
    var poly = List<(double, double)>.from(triA);
    for (var i = 0; i < 3; i++) {
      final p0 = triB[i];
      final p1 = triB[(i + 1) % 3];
      poly = _clipPolygonByEdge(poly, p0, p1);
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

  static void _drawLine(
    img.Image image,
    double x0,
    double y0,
    double x1,
    double y1,
    img.ColorRgb8 color, {
    int thickness = 1,
  }) {
    final steps = (math.max((x1 - x0).abs(), (y1 - y0).abs()) * 2).ceil();
    if (steps == 0) {
      return;
    }
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = (x0 + (x1 - x0) * t).round();
      final y = (y0 + (y1 - y0) * t).round();
      for (var dy = -thickness; dy <= thickness; dy++) {
        for (var dx = -thickness; dx <= thickness; dx++) {
          final px = x + dx;
          final py = y + dy;
          if (px >= 0 && py >= 0 && px < image.width && py < image.height) {
            image.setPixelRgb(px, py, color.r.toInt(), color.g.toInt(), color.b.toInt());
          }
        }
      }
    }
  }

  static void _fillSquare(img.Image image, int x, int y, img.ColorRgb8 color) {
    for (var dy = -2; dy <= 2; dy++) {
      for (var dx = -2; dx <= 2; dx++) {
        final px = x + dx;
        final py = y + dy;
        if (px >= 0 && py >= 0 && px < image.width && py < image.height) {
          image.setPixelRgb(px, py, color.r, color.g, color.b);
        }
      }
    }
  }

  static void _drawLabel(
    img.Image image,
    int x,
    int y,
    String text,
    img.ColorRgb8 color,
  ) {
    for (var i = 0; i < text.length; i++) {
      final px = x + i * 4;
      if (px >= 0 && px < image.width && y >= 0 && y < image.height) {
        image.setPixelRgb(px, y, color.r, color.g, color.b);
      }
    }
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
