import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../debug/agent_debug_log.dart';
import '../filters/face/face_warp_utils.dart';
import '../mesh/tri_mesh_spatial_index.dart';
import '../models/tri_mesh.dart';
import 'face_mesh_forward_warp.dart';
import 'face_warp_render_contract.dart';
import 'face_warp_renderer.dart' show GeometricSupport;

/// Resultado do diagnóstico Fase 4 — origem das neighbor discontinuities.
class NeighborDiscontinuityDiagnosticResult {
  const NeighborDiscontinuityDiagnosticResult({
    required this.summary,
    required this.worstJsonl,
    required this.discontinuities5Png,
    required this.discontinuities10Png,
  });

  final Map<String, dynamic> summary;
  final String worstJsonl;
  final String discontinuities5Png;
  final String discontinuities10Png;
}

/// Fase 4 — classificar saltos de source entre pixels vizinhos.
///
/// Usa o mesmo campo source do remap com scanline coherence (Fase 3).
/// Não altera produção. Somente [kDebugMode].
abstract final class NeighborDiscontinuityDiagnostic {
  NeighborDiscontinuityDiagnostic._();

  static const _defaultOutputDir =
      '/Users/leonardo/Documents/Projetos/editaiapp/.cursor';

  static Future<NeighborDiscontinuityDiagnosticResult?> run({
    required FaceMeshForwardPayload payload,
    required int width,
    required int height,
    String runId = 'neighbor-disc-real-90',
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
      final field = _buildSourceField(
        spatialIndex: built.spatialIndex,
        sourceMesh: built.sourceMesh,
        roi: built.roi,
        width: width,
        height: height,
      );

      final edgeMap = _buildEdgeToTrianglesMap(built.deformedMesh);
      final pairs = _collectNeighborPairs(
        field: field,
        spatialIndex: built.spatialIndex,
        sourceMesh: built.sourceMesh,
        deformedMesh: built.deformedMesh,
        edgeMap: edgeMap,
        roi: built.roi,
        width: width,
        height: height,
      );

      pairs.sort((a, b) => b.deltaSource.compareTo(a.deltaSource));

      final gt5 = pairs.where((p) => p.deltaSource > 5).toList();
      final classification = _classifyPairs(pairs, gt5);

      final top100 = pairs.take(100).map(_pairToJson).toList();
      final top20Jacobian = _analyzeJacobianTop20(
        pairs: pairs.take(20).toList(),
        deformedMesh: built.deformedMesh,
        sourceMesh: built.sourceMesh,
      );

      final allDeltas = pairs.map((p) => p.deltaSource).toList()..sort();

      final summary = {
        'sameTriangleGt5': classification.sameTriangleGt5,
        'sharedEdgeGt5': classification.sharedEdgeGt5,
        'sharedVertexGt5': classification.sharedVertexGt5,
        'unrelatedTriangleGt5': classification.unrelatedGt5,
        'sameTriangleTotal': classification.sameTriangleTotal,
        'differentTriangleSharedEdgeTotal':
            classification.sharedEdgeTotal,
        'differentTriangleSharedVertexTotal':
            classification.sharedVertexTotal,
        'differentTriangleNoRelationTotal': classification.unrelatedTotal,
        'countGt5px': gt5.length,
        'maxSourceDelta': allDeltas.isEmpty ? 0.0 : allDeltas.last,
        'p95SourceDelta': _percentile(allDeltas, 0.95),
        'topCases': top100.take(10).toList(),
        'jacobianTop20': top20Jacobian,
        'sharedEdgeIntersectionAnalysis':
            _sharedEdgeIntersectionSummary(gt5),
        'sameTriangleCriticalCount': classification.sameTriangleGt5,
      };

      final worstJsonl = '$outDir/debug-worst-neighbor-discontinuities.jsonl';
      _writeJsonl(worstJsonl, top100);

      final summaryJsonPath = '$outDir/phase4_neighbor_discontinuity_summary.json';
      File(summaryJsonPath).writeAsStringSync(jsonEncode(summary));

      final disc5Png = '$outDir/debug-source-field-discontinuities-v2.png';
      final disc10Png = '$outDir/debug-source-field-discontinuities-v2-10px.png';
      _writeDiscontinuityField(
        path: disc5Png,
        width: width,
        height: height,
        pairs: gt5,
        threshold: 5,
      );
      _writeDiscontinuityField(
        path: disc10Png,
        width: width,
        height: height,
        pairs: pairs.where((p) => p.deltaSource > 10).toList(),
        threshold: 10,
      );

      AgentDebugLog.write(
        location: 'neighbor_discontinuity_diagnostic.dart:run',
        message: 'phase4_neighbor_discontinuity_diagnostic',
        hypothesisId: 'P4ND',
        runId: runId,
        phase: '4',
        data: summary,
      );

      return NeighborDiscontinuityDiagnosticResult(
        summary: summary,
        worstJsonl: worstJsonl,
        discontinuities5Png: disc5Png,
        discontinuities10Png: disc10Png,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('NeighborDiscontinuityDiagnostic failed: $e\n$st');
      }
      return null;
    }
  }

  static ({
    int sameTriangleTotal,
    int sharedEdgeTotal,
    int sharedVertexTotal,
    int unrelatedTotal,
    int sameTriangleGt5,
    int sharedEdgeGt5,
    int sharedVertexGt5,
    int unrelatedGt5,
  }) _classifyPairs(
    List<_NeighborPair> all,
    List<_NeighborPair> gt5,
  ) {
    var sameTri = 0;
    var sharedEdge = 0;
    var sharedVertex = 0;
    var unrelated = 0;

    for (final p in all) {
      switch (p.relation) {
        case _TriangleRelation.sameTriangle:
          sameTri++;
        case _TriangleRelation.sharedEdge:
          sharedEdge++;
        case _TriangleRelation.sharedVertex:
          sharedVertex++;
        case _TriangleRelation.noRelation:
          unrelated++;
      }
    }

    var sameTriGt5 = 0;
    var sharedEdgeGt5 = 0;
    var sharedVertexGt5 = 0;
    var unrelatedGt5 = 0;

    for (final p in gt5) {
      switch (p.relation) {
        case _TriangleRelation.sameTriangle:
          sameTriGt5++;
        case _TriangleRelation.sharedEdge:
          sharedEdgeGt5++;
        case _TriangleRelation.sharedVertex:
          sharedVertexGt5++;
        case _TriangleRelation.noRelation:
          unrelatedGt5++;
      }
    }

    return (
      sameTriangleTotal: sameTri,
      sharedEdgeTotal: sharedEdge,
      sharedVertexTotal: sharedVertex,
      unrelatedTotal: unrelated,
      sameTriangleGt5: sameTriGt5,
      sharedEdgeGt5: sharedEdgeGt5,
      sharedVertexGt5: sharedVertexGt5,
      unrelatedGt5: unrelatedGt5,
    );
  }

  static List<Map<String, dynamic>> _sharedEdgeIntersectionSummary(
    List<_NeighborPair> gt5,
  ) {
    final edgePairs = gt5
        .where((p) => p.relation == _TriangleRelation.sharedEdge)
        .take(20)
        .toList();
    return edgePairs
        .map(
          (p) => {
            'deltaSource': p.deltaSource,
            'edgeSourceDeltaAtIntersection': p.edgeSourceDelta,
            'pixelA': {'x': p.ax, 'y': p.ay},
            'pixelB': {'x': p.bx, 'y': p.by},
            'triangleA': p.triA,
            'triangleB': p.triB,
          },
        )
        .toList();
  }

  static List<Map<String, dynamic>> _analyzeJacobianTop20({
    required List<_NeighborPair> pairs,
    required TriMesh deformedMesh,
    required TriMesh sourceMesh,
  }) {
    final results = <Map<String, dynamic>>[];
    for (final p in pairs) {
      if (p.triA < 0) {
        continue;
      }
      final expected = _expectedSourceDelta(
        triIndex: p.triA,
        deformedMesh: deformedMesh,
        sourceMesh: sourceMesh,
        destDx: (p.bx - p.ax).toDouble(),
        destDy: (p.by - p.ay).toDouble(),
      );
      final actual = p.deltaSource;
      final ratio = expected > 1e-9 ? actual / expected : double.nan;
      results.add({
        'pixelA': {'x': p.ax, 'y': p.ay},
        'pixelB': {'x': p.bx, 'y': p.by},
        'triangleA': p.triA,
        'triangleB': p.triB,
        'relation': p.relation.name,
        'actualDeltaSource': actual,
        'expectedDeltaSource': expected,
        'ratioActualOverExpected': ratio,
        'mathematicallyExpected': ratio.isFinite && ratio <= 1.5,
      });
    }
    return results;
  }

  static double _expectedSourceDelta({
    required int triIndex,
    required TriMesh deformedMesh,
    required TriMesh sourceMesh,
    required double destDx,
    required double destDy,
  }) {
    final i0 = deformedMesh.indices[triIndex * 3];
    final i1 = deformedMesh.indices[triIndex * 3 + 1];
    final i2 = deformedMesh.indices[triIndex * 3 + 2];

    final d0 = _vertex(deformedMesh, i0);
    final d1 = _vertex(deformedMesh, i1);
    final d2 = _vertex(deformedMesh, i2);
    final s0 = _vertex(sourceMesh, i0);
    final s1 = _vertex(sourceMesh, i1);
    final s2 = _vertex(sourceMesh, i2);

    final e1x = d1.x - d0.x;
    final e1y = d1.y - d0.y;
    final e2x = d2.x - d0.x;
    final e2y = d2.y - d0.y;
    final det = e1x * e2y - e1y * e2x;
    if (det.abs() < 1e-12) {
      return 0.0;
    }

    final ds1x = s1.x - s0.x;
    final ds1y = s1.y - s0.y;
    final ds2x = s2.x - s0.x;
    final ds2y = s2.y - s0.y;

    // M * [e1 e2] = [ds1 ds2]  →  expected = |M * dp|
    final m00 = (ds1x * e2y - ds2x * e1y) / det;
    final m01 = (ds2x * e1x - ds1x * e2x) / det;
    final m10 = (ds1y * e2y - ds2y * e1y) / det;
    final m11 = (ds2y * e1x - ds1y * e2x) / det;

    final esx = m00 * destDx + m01 * destDy;
    final esy = m10 * destDx + m11 * destDy;
    return math.sqrt(esx * esx + esy * esy);
  }

  static _SourceField _buildSourceField({
    required TriMeshSpatialIndex spatialIndex,
    required TriMesh sourceMesh,
    required ({int x0, int y0, int x1, int y1}) roi,
    required int width,
    required int height,
  }) {
    final pixelCount = width * height;
    final srcX = Float32List(pixelCount)..fillRange(0, pixelCount, double.nan);
    final srcY = Float32List(pixelCount)..fillRange(0, pixelCount, double.nan);
    final triId = Int32List(pixelCount)..fillRange(0, pixelCount, -1);
    final hitMask = Uint8List(pixelCount);

    final w0 = Float32List(pixelCount)..fillRange(0, pixelCount, double.nan);
    final w1 = Float32List(pixelCount)..fillRange(0, pixelCount, double.nan);
    final w2 = Float32List(pixelCount)..fillRange(0, pixelCount, double.nan);

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

        rowSrcX[col] = src.srcX;
        rowSrcY[col] = src.srcY;
        final p = y * width + x;
        srcX[p] = src.srcX;
        srcY[p] = src.srcY;
        triId[p] = tri;
        w0[p] = hit.w0;
        w1[p] = hit.w1;
        w2[p] = hit.w2;
        hitMask[p] = 1;
      }
      for (var col = 0; col < rowTris.length; col++) {
        topSrcX[col] = rowSrcX[col];
        topSrcY[col] = rowSrcY[col];
      }
    }

    return _SourceField(
      srcX: srcX,
      srcY: srcY,
      triId: triId,
      w0: w0,
      w1: w1,
      w2: w2,
      hitMask: hitMask,
    );
  }

  static List<_NeighborPair> _collectNeighborPairs({
    required _SourceField field,
    required TriMeshSpatialIndex spatialIndex,
    required TriMesh sourceMesh,
    required TriMesh deformedMesh,
    required Map<String, List<int>> edgeMap,
    required ({int x0, int y0, int x1, int y1}) roi,
    required int width,
    required int height,
  }) {
    final pairs = <_NeighborPair>[];

    void addPair(int ax, int ay, int bx, int by) {
      final pa = ay * width + ax;
      final pb = by * width + bx;
      if (field.hitMask[pa] == 0 || field.hitMask[pb] == 0) {
        return;
      }

      final sxA = field.srcX[pa];
      final syA = field.srcY[pa];
      final sxB = field.srcX[pb];
      final syB = field.srcY[pb];
      if (sxA.isNaN || syA.isNaN || sxB.isNaN || syB.isNaN) {
        return;
      }

      final delta = _dist(sxA, syA, sxB, syB);
      final triA = field.triId[pa];
      final triB = field.triId[pb];
      final relation = _classifyTriangleRelation(
        triA,
        triB,
        deformedMesh,
        edgeMap,
      );

      double? edgeSourceDelta;
      if (relation == _TriangleRelation.sharedEdge &&
          triA >= 0 &&
          triB >= 0) {
        edgeSourceDelta = _edgeSourceDeltaAtSegmentIntersection(
          ax: ax,
          ay: ay,
          bx: bx,
          by: by,
          triA: triA,
          triB: triB,
          spatialIndex: spatialIndex,
          sourceMesh: sourceMesh,
          deformedMesh: deformedMesh,
          edgeMap: edgeMap,
        );
      }

      pairs.add(
        _NeighborPair(
          ax: ax,
          ay: ay,
          bx: bx,
          by: by,
          triA: triA,
          triB: triB,
          srcAx: sxA,
          srcAy: syA,
          srcBx: sxB,
          srcBy: syB,
          wA: [field.w0[pa], field.w1[pa], field.w2[pa]],
          wB: [field.w0[pb], field.w1[pb], field.w2[pb]],
          deltaSource: delta,
          relation: relation,
          edgeSourceDelta: edgeSourceDelta,
        ),
      );
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

    return pairs;
  }

  static double? _edgeSourceDeltaAtSegmentIntersection({
    required int ax,
    required int ay,
    required int bx,
    required int by,
    required int triA,
    required int triB,
    required TriMeshSpatialIndex spatialIndex,
    required TriMesh sourceMesh,
    required TriMesh deformedMesh,
    required Map<String, List<int>> edgeMap,
  }) {
    final shared = _sharedEdgeVertices(triA, triB, deformedMesh);
    if (shared == null) {
      return null;
    }

    final (v0, v1) = shared;
    final d0p = _vertex(deformedMesh, v0);
    final d1p = _vertex(deformedMesh, v1);
    final d0 = (d0p.x, d0p.y);
    final d1 = (d1p.x, d1p.y);

    final pA = (ax + 0.5, ay + 0.5);
    final pB = (bx + 0.5, by + 0.5);
    final intersection = _segmentSegmentIntersection(pA, pB, d0, d1);
    if (intersection == null) {
      return null;
    }

    final (ix, iy) = intersection;
    final srcA = _sourceAtTriangle(sourceMesh, spatialIndex, triA, ix, iy);
    final srcB = _sourceAtTriangle(sourceMesh, spatialIndex, triB, ix, iy);
    if (srcA == null || srcB == null) {
      return null;
    }
    return _dist(srcA.srcX, srcA.srcY, srcB.srcX, srcB.srcY);
  }

  static (int v0, int v1)? _sharedEdgeVertices(
    int triA,
    int triB,
    TriMesh mesh,
  ) {
    final vertsA = {
      mesh.indices[triA * 3],
      mesh.indices[triA * 3 + 1],
      mesh.indices[triA * 3 + 2],
    };
    final vertsB = {
      mesh.indices[triB * 3],
      mesh.indices[triB * 3 + 1],
      mesh.indices[triB * 3 + 2],
    };
    final shared = vertsA.intersection(vertsB);
    if (shared.length != 2) {
      return null;
    }
    final list = shared.toList()..sort();
    return (list[0], list[1]);
  }

  static ({double srcX, double srcY})? _sourceAtTriangle(
    TriMesh sourceMesh,
    TriMeshSpatialIndex index,
    int tri,
    double px,
    double py,
  ) {
    final hit = index.barycentricInTriangle(tri, px, py);
    if (hit == null) {
      return null;
    }
    return _sourceFromHit(sourceMesh, hit);
  }

  static _TriangleRelation _classifyTriangleRelation(
    int triA,
    int triB,
    TriMesh mesh,
    Map<String, List<int>> edgeMap,
  ) {
    if (triA < 0 || triB < 0) {
      return _TriangleRelation.noRelation;
    }
    if (triA == triB) {
      return _TriangleRelation.sameTriangle;
    }

    final vertsA = _triangleVerts(mesh, triA);
    final vertsB = _triangleVerts(mesh, triB);
    final shared = vertsA.intersection(vertsB);

    if (shared.length == 2) {
      final list = shared.toList()..sort();
      final key = '${list[0]}-${list[1]}';
      final tris = edgeMap[key];
      if (tris != null && tris.contains(triA) && tris.contains(triB)) {
        return _TriangleRelation.sharedEdge;
      }
    }
    if (shared.isNotEmpty) {
      return _TriangleRelation.sharedVertex;
    }
    return _TriangleRelation.noRelation;
  }

  static Set<int> _triangleVerts(TriMesh mesh, int tri) {
    return {
      mesh.indices[tri * 3],
      mesh.indices[tri * 3 + 1],
      mesh.indices[tri * 3 + 2],
    };
  }

  static Map<String, List<int>> _buildEdgeToTrianglesMap(TriMesh mesh) {
    final edgeMap = <String, List<int>>{};
    for (var t = 0; t < mesh.triangleCount; t++) {
      final i0 = mesh.indices[t * 3];
      final i1 = mesh.indices[t * 3 + 1];
      final i2 = mesh.indices[t * 3 + 2];
      _addEdge(edgeMap, t, i0, i1);
      _addEdge(edgeMap, t, i1, i2);
      _addEdge(edgeMap, t, i2, i0);
    }
    return edgeMap;
  }

  static void _addEdge(
    Map<String, List<int>> map,
    int tri,
    int a,
    int b,
  ) {
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    final key = '$lo-$hi';
    (map[key] ??= <int>[]).add(tri);
  }

  static Map<String, dynamic> _pairToJson(_NeighborPair p) {
    return {
      'a': {
        'x': p.ax,
        'y': p.ay,
        'triangleId': p.triA,
        'sourceX': p.srcAx,
        'sourceY': p.srcAy,
        'barycentric': p.wA,
      },
      'b': {
        'x': p.bx,
        'y': p.by,
        'triangleId': p.triB,
        'sourceX': p.srcBx,
        'sourceY': p.srcBy,
        'barycentric': p.wB,
      },
      'deltaSource': p.deltaSource,
      'triangleRelation': {
        'sameTriangle': p.relation == _TriangleRelation.sameTriangle,
        'shareEdge': p.relation == _TriangleRelation.sharedEdge,
        'shareVertex': p.relation == _TriangleRelation.sharedVertex,
        'noRelation': p.relation == _TriangleRelation.noRelation,
        'category': p.relation.name,
      },
      if (p.edgeSourceDelta != null)
        'edgeSourceDeltaAtIntersection': p.edgeSourceDelta,
    };
  }

  static void _writeJsonl(String path, List<Map<String, dynamic>> records) {
    final sink = File(path).openWrite();
    for (final record in records) {
      sink.writeln(jsonEncode(record));
    }
    sink.close();
  }

  static void _writeDiscontinuityField({
    required String path,
    required int width,
    required int height,
    required List<_NeighborPair> pairs,
    required double threshold,
  }) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(0, 0, 0));

    var maxDelta = threshold;
    for (final p in pairs) {
      if (p.deltaSource > maxDelta) {
        maxDelta = p.deltaSource;
      }
    }

    for (final p in pairs) {
      if (p.deltaSource <= threshold) {
        continue;
      }
      final t = ((p.deltaSource - threshold) / (maxDelta - threshold))
          .clamp(0.0, 1.0);
      final r = (255 * t).round();
      for (final (x, y) in [(p.ax, p.ay), (p.bx, p.by)]) {
        image.setPixelRgb(x, y, r, 60, 60);
      }
    }

    File(path).writeAsBytesSync(img.encodePng(image));
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

  static ({double srcX, double srcY})? _sourceFromHit(
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
      srcX: hit.w0 * s0.dx + hit.w1 * s1.dx + hit.w2 * s2.dx,
      srcY: hit.w0 * s0.dy + hit.w1 * s1.dy + hit.w2 * s2.dy,
    );
  }

  static (double, double)? _segmentSegmentIntersection(
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

  static math.Point<double> _vertex(TriMesh mesh, int i) {
    return math.Point(mesh.vertices[i * 2], mesh.vertices[i * 2 + 1]);
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

  static double _dist(double ax, double ay, double bx, double by) {
    final dx = ax - bx;
    final dy = ay - by;
    return math.sqrt(dx * dx + dy * dy);
  }

  static double _percentile(List<double> sorted, double p) {
    if (sorted.isEmpty) {
      return 0.0;
    }
    final idx = ((sorted.length - 1) * p).round().clamp(0, sorted.length - 1);
    return sorted[idx];
  }
}

enum _TriangleRelation {
  sameTriangle,
  sharedEdge,
  sharedVertex,
  noRelation,
}

class _SourceField {
  const _SourceField({
    required this.srcX,
    required this.srcY,
    required this.triId,
    required this.w0,
    required this.w1,
    required this.w2,
    required this.hitMask,
  });

  final Float32List srcX;
  final Float32List srcY;
  final Int32List triId;
  final Float32List w0;
  final Float32List w1;
  final Float32List w2;
  final Uint8List hitMask;
}

class _NeighborPair {
  const _NeighborPair({
    required this.ax,
    required this.ay,
    required this.bx,
    required this.by,
    required this.triA,
    required this.triB,
    required this.srcAx,
    required this.srcAy,
    required this.srcBx,
    required this.srcBy,
    required this.wA,
    required this.wB,
    required this.deltaSource,
    required this.relation,
    this.edgeSourceDelta,
  });

  final int ax;
  final int ay;
  final int bx;
  final int by;
  final int triA;
  final int triB;
  final double srcAx;
  final double srcAy;
  final double srcBx;
  final double srcBy;
  final List<double> wA;
  final List<double> wB;
  final double deltaSource;
  final _TriangleRelation relation;
  final double? edgeSourceDelta;
}
