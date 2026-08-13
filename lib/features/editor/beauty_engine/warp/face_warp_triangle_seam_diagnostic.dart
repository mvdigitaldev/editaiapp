import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../debug/agent_debug_log.dart';
import '../filters/face/face_warp_utils.dart';
import '../mesh/tri_mesh_spatial_index.dart';
import '../models/tri_mesh.dart';
import '../models/mesh_region.dart';
import 'face_mesh_forward_warp.dart';
import 'face_warp_render_contract.dart';
import 'face_warp_renderer.dart' show GeometricSupport, FaceWarpFieldMetrics;

/// Resultado do diagnóstico de continuidade entre triângulos adjacentes.
class FaceWarpTriangleSeamDiagnosticResult {
  const FaceWarpTriangleSeamDiagnosticResult({
    required this.test1EdgeContinuity,
    required this.test2ProblematicEdges,
    required this.test3PureRemap,
    required this.outputMetrics,
    required this.conclusion,
    required this.seamsPng,
    required this.seamsHeatmapPng,
    required this.pureRemapPng,
  });

  final Map<String, dynamic> test1EdgeContinuity;
  final List<Map<String, dynamic>> test2ProblematicEdges;
  final Map<String, dynamic> test3PureRemap;
  final Map<String, dynamic> outputMetrics;
  final String conclusion;
  final String seamsPng;
  final String seamsHeatmapPng;
  final String pureRemapPng;
}

/// Diagnóstico — continuidade piecewise-affine entre triângulos adjacentes.
///
/// Isola matemática de baricêntricas por triângulo vs [TriMeshSpatialIndex.locate].
/// Não altera produção. Somente [kDebugMode].
abstract final class FaceWarpTriangleSeamDiagnostic {
  FaceWarpTriangleSeamDiagnostic._();

  static const _sampleTs = [0.1, 0.25, 0.5, 0.75, 0.9];
  static const _defaultOutputDir =
      '/Users/leonardo/Documents/Projetos/editaiapp/.cursor';

  static Future<FaceWarpTriangleSeamDiagnosticResult?> run({
    required Uint8List sourceRgba,
    required int width,
    required int height,
    required FaceMeshForwardPayload payload,
    String runId = 'triangle-seam-real-90',
    String? outputDirectory,
  }) async {
    if (!kDebugMode || sourceRgba.isEmpty) {
      return null;
    }

    try {
      final outDir = outputDirectory ?? _defaultOutputDir;
      Directory(outDir).createSync(recursive: true);

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
      final centerX = width * 0.5;

      // ── TESTE 1: continuidade das arestas ──
      final edgePairs = _buildSharedEdgePairs(mesh);
      final perEdgeMaxDeltas = <double>[];
      final perEdgeMaxLocateDeltas = <double>[];
      final allSampleDeltas = <double>[];
      final locateDeltas = <double>[];
      final problematicEdges = <_ProblematicEdge>[];

      for (final pair in edgePairs) {
        final v0 = pair.vertex0;
        final v1 = pair.vertex1;
        final d0 = FaceWarpUtils.vertexAt(deformedMesh, v0)!;
        final d1 = FaceWarpUtils.vertexAt(deformedMesh, v1)!;
        final s0 = FaceWarpUtils.vertexAt(mesh, v0)!;
        final s1 = FaceWarpUtils.vertexAt(mesh, v1)!;

        var maxDelta = 0.0;
        var maxLocateDelta = 0.0;
        final samples = <Map<String, dynamic>>[];

        for (final t in _sampleTs) {
          final px = d0.dx + t * (d1.dx - d0.dx);
          final py = d0.dy + t * (d1.dy - d0.dy);

          final srcA = _sourceAtTriangle(
            sourceMesh: mesh,
            deformedMesh: deformedMesh,
            triIndex: pair.triA,
            px: px,
            py: py,
          );
          final srcB = _sourceAtTriangle(
            sourceMesh: mesh,
            deformedMesh: deformedMesh,
            triIndex: pair.triB,
            px: px,
            py: py,
          );
          if (srcA == null || srcB == null) {
            continue;
          }

          final delta = _dist(srcA.srcX, srcA.srcY, srcB.srcX, srcB.srcY);
          allSampleDeltas.add(delta);
          if (delta > maxDelta) {
            maxDelta = delta;
          }

          final locateHit = spatialIndex.locate(px, py);
          var locateDelta = 0.0;
          if (locateHit != null) {
            final srcLocate = _sourceFromHit(mesh, locateHit);
            if (srcLocate != null) {
              final dA = _dist(
                srcLocate.srcX,
                srcLocate.srcY,
                srcA.srcX,
                srcA.srcY,
              );
              final dB = _dist(
                srcLocate.srcX,
                srcLocate.srcY,
                srcB.srcX,
                srcB.srcY,
              );
              locateDelta = math.min(dA, dB);
              locateDeltas.add(locateDelta);
              if (locateDelta > maxLocateDelta) {
                maxLocateDelta = locateDelta;
              }
            }
          }

          samples.add({
            't': t,
            'destX': px,
            'destY': py,
            'sourceA': {'x': srcA.srcX, 'y': srcA.srcY},
            'sourceB': {'x': srcB.srcX, 'y': srcB.srcY},
            'deltaSource': delta,
            'locateDelta': locateDelta,
            'locateTri': spatialIndex.locateTriangleIndex(px, py),
          });
        }

        if (samples.isNotEmpty) {
          perEdgeMaxDeltas.add(maxDelta);
          perEdgeMaxLocateDeltas.add(maxLocateDelta);
        }

        if (maxDelta > 1.0) {
          final midX = (d0.dx + d1.dx) * 0.5;
          problematicEdges.add(
            _ProblematicEdge(
              triA: pair.triA,
              triB: pair.triB,
              vertex0: v0,
              vertex1: v1,
              source0: s0,
              source1: s1,
              dest0: d0,
              dest1: d1,
              maxDelta: maxDelta,
              maxLocateDelta: maxLocateDelta,
              side: midX < centerX ? 'left' : 'right',
              region: _inferRegion(mesh, pair.triA),
              samples: samples,
            ),
          );
        }
      }

      perEdgeMaxDeltas.sort();
      allSampleDeltas.sort();
      locateDeltas.sort();

      final test1 = {
        'sharedEdgeCount': edgePairs.length,
        'sampleCount': allSampleDeltas.length,
        'maxEdgeSourceDiscontinuity':
            perEdgeMaxDeltas.isEmpty ? 0.0 : perEdgeMaxDeltas.last,
        'p95EdgeSourceDiscontinuity': _percentile(allSampleDeltas, 0.95),
        'meanEdgeSourceDiscontinuity': allSampleDeltas.isEmpty
            ? 0.0
            : allSampleDeltas.reduce((a, b) => a + b) / allSampleDeltas.length,
        'edgesGt025px': perEdgeMaxDeltas.where((d) => d > 0.25).length,
        'edgesGt1px': perEdgeMaxDeltas.where((d) => d > 1.0).length,
        'edgesGt5px': perEdgeMaxDeltas.where((d) => d > 5.0).length,
        'edgesGt10px': perEdgeMaxDeltas.where((d) => d > 10.0).length,
        'maxLocateEdgeDiscontinuity':
            locateDeltas.isEmpty ? 0.0 : locateDeltas.last,
        'p95LocateEdgeDiscontinuity': _percentile(locateDeltas, 0.95),
        'locateSamplesGt025px': locateDeltas.where((d) => d > 0.25).length,
        'locateSamplesGt1px': locateDeltas.where((d) => d > 1.0).length,
      };

      // ── TESTE 2: visualização das arestas problemáticas ──
      final seamsPng = '$outDir/debug-face-slim-triangle-seams.png';
      final heatmapPng = '$outDir/debug-face-slim-triangle-seams-heatmap.png';
      _writeSeamImages(
        width: width,
        height: height,
        problematicEdges: problematicEdges,
        seamsPath: seamsPng,
        heatmapPath: heatmapPng,
      );

      final test2Log = problematicEdges
          .map(
            (e) => {
              'triangleA': e.triA,
              'triangleB': e.triB,
              'vertex0': e.vertex0,
              'vertex1': e.vertex1,
              'source0': {'x': e.source0.dx, 'y': e.source0.dy},
              'source1': {'x': e.source1.dx, 'y': e.source1.dy},
              'dest0': {'x': e.dest0.dx, 'y': e.dest0.dy},
              'dest1': {'x': e.dest1.dx, 'y': e.dest1.dy},
              'maxDeltaSource': e.maxDelta,
              'maxLocateDelta': e.maxLocateDelta,
              'region': e.region,
              'side': e.side,
              'samples': e.samples,
            },
          )
          .toList();

      // ── TESTE 3: remap puro (sem FaceWarpRenderer) ──
      final pureRemap = _pureBackwardRemap(
        sourceRgba: sourceRgba,
        width: width,
        height: height,
        sourceMesh: mesh,
        deformedMesh: deformedMesh,
        spatialIndex: spatialIndex,
        roi: roi,
      );
      final pureRemapPng = '$outDir/debug-face-slim-pure-remap.png';
      _writeRgbaPng(pureRemapPng, pureRemap.rgba, width, height);

      final test3 = {
        'meshHitPx': pureRemap.meshHitPx,
        'coverageRatio': pureRemap.coverageRatio,
        'algorithm': 'pure_locate_barycentric_bilinear',
        'usesFaceWarpRenderer': false,
      };

      // ── Métricas de output ──
      final seamMask = _rasterizeEdgeMask(
        width: width,
        height: height,
        edges: problematicEdges,
        radius: 3,
      );

      final outputMetrics = _computeOutputMetrics(
        rgba: pureRemap.rgba,
        width: width,
        height: height,
        roi: roi,
        seamMask: seamMask,
        srcXField: pureRemap.srcXField,
        srcYField: pureRemap.srcYField,
        hitMask: pureRemap.hitMask,
      );

      final conclusion = _computeConclusion(
        test1: test1,
        outputMetrics: outputMetrics,
      );

      AgentDebugLog.write(
        location: 'face_warp_triangle_seam_diagnostic.dart:run',
        message: 'phase2_triangle_seam_diagnostic',
        hypothesisId: 'P2TS',
        runId: runId,
        phase: '2',
        data: {
          'test1EdgeContinuity': test1,
          'test2ProblematicEdgeCount': test2Log.length,
          'test2ProblematicEdges': test2Log.take(20).toList(),
          'test3PureRemap': test3,
          'outputMetrics': outputMetrics,
          'conclusion': conclusion,
          'seamsPng': seamsPng,
          'seamsHeatmapPng': heatmapPng,
          'pureRemapPng': pureRemapPng,
        },
      );

      return FaceWarpTriangleSeamDiagnosticResult(
        test1EdgeContinuity: test1,
        test2ProblematicEdges: test2Log,
        test3PureRemap: test3,
        outputMetrics: outputMetrics,
        conclusion: conclusion,
        seamsPng: seamsPng,
        seamsHeatmapPng: heatmapPng,
        pureRemapPng: pureRemapPng,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('FaceWarpTriangleSeamDiagnostic failed: $e\n$st');
      }
      return null;
    }
  }

  static String _computeConclusion({
    required Map<String, dynamic> test1,
    required Map<String, dynamic> outputMetrics,
  }) {
    final maxEdge = test1['maxEdgeSourceDiscontinuity'] as num? ?? 0;
    final p95Edge = test1['p95EdgeSourceDiscontinuity'] as num? ?? 0;
    final edgesGt1 = test1['edgesGt1px'] as int? ?? 0;
    final maxLocate = test1['maxLocateEdgeDiscontinuity'] as num? ?? 0;
    final locateGt1 = test1['locateSamplesGt1px'] as int? ?? 0;
    final seamCorr = outputMetrics['seamRgbJumpCorrelation'] as num? ?? 0;

    // A: descontinuidade geométrica real na aresta compartilhada
    if (maxEdge > 1.0 || edgesGt1 > 10) {
      return 'TRIANGLE SEAM DISCONTINUITY';
    }

    // B: baricêntricas contínuas mas locate inconsistente
    if (maxEdge <= 0.25 &&
        p95Edge <= 0.5 &&
        (maxLocate > 1.0 || locateGt1 > 5)) {
      return 'REMAP IMPLEMENTATION / LOCATE BUG';
    }

    // B alternativo: edges OK mas saltos RGB correlacionados com seams via locate
    if (maxEdge <= 0.25 &&
        maxLocate <= 0.25 &&
        seamCorr > 0.3 &&
        (outputMetrics['faceRoiRgbMaxHorizJump'] as num? ?? 0) > 40) {
      return 'REMAP IMPLEMENTATION / LOCATE BUG';
    }

    return 'NO GEOMETRIC DISCONTINUITY';
  }

  static ({
    Uint8List rgba,
    int meshHitPx,
    double coverageRatio,
    Float32List srcXField,
    Float32List srcYField,
    Uint8List hitMask,
  }) _pureBackwardRemap({
    required Uint8List sourceRgba,
    required int width,
    required int height,
    required TriMesh sourceMesh,
    required TriMesh deformedMesh,
    required TriMeshSpatialIndex spatialIndex,
    required ({int x0, int y0, int x1, int y1}) roi,
  }) {
    final output = Uint8List.fromList(sourceRgba);
    final pixelCount = width * height;
    final srcXField =
        Float32List(pixelCount)..fillRange(0, pixelCount, double.nan);
    final srcYField =
        Float32List(pixelCount)..fillRange(0, pixelCount, double.nan);
    final hitMask = Uint8List(pixelCount);

    var meshHitPx = 0;
    final roiPixels = (roi.x1 - roi.x0 + 1) * (roi.y1 - roi.y0 + 1);
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

        final s0 = FaceWarpUtils.vertexAt(sourceMesh, hit.i0);
        final s1 = FaceWarpUtils.vertexAt(sourceMesh, hit.i1);
        final s2 = FaceWarpUtils.vertexAt(sourceMesh, hit.i2);
        if (s0 == null || s1 == null || s2 == null) {
          continue;
        }

        final srcX =
            hit.w0 * s0.dx + hit.w1 * s1.dx + hit.w2 * s2.dx;
        final srcY =
            hit.w0 * s0.dy + hit.w1 * s1.dy + hit.w2 * s2.dy;
        rowSrcX[col] = srcX;
        rowSrcY[col] = srcY;
        final rgb = _sampleBilinear(sourceRgba, width, height, srcX, srcY);

        final p = y * width + x;
        final o = p * 4;
        output[o] = rgb[0];
        output[o + 1] = rgb[1];
        output[o + 2] = rgb[2];
        srcXField[p] = srcX;
        srcYField[p] = srcY;
        hitMask[p] = 1;
        meshHitPx++;
      }
      for (var col = 0; col < rowTris.length; col++) {
        topSrcX[col] = rowSrcX[col];
        topSrcY[col] = rowSrcY[col];
      }
    }

    return (
      rgba: output,
      meshHitPx: meshHitPx,
      coverageRatio: roiPixels > 0 ? meshHitPx / roiPixels : 0.0,
      srcXField: srcXField,
      srcYField: srcYField,
      hitMask: hitMask,
    );
  }

  static Map<String, dynamic> _computeOutputMetrics({
    required Uint8List rgba,
    required int width,
    required int height,
    required ({int x0, int y0, int x1, int y1}) roi,
    required Uint8List seamMask,
    required Float32List srcXField,
    required Float32List srcYField,
    required Uint8List hitMask,
  }) {
    final globalRgb = _rgbHorizontalDiscontinuity(rgba, width, height, 0, 0,
        width - 1, height - 1);
    final faceRgb = _rgbHorizontalDiscontinuity(
      rgba,
      width,
      height,
      roi.x0,
      roi.y0,
      roi.x1,
      roi.y1,
    );
    final seamRgb = _rgbHorizontalDiscontinuityMasked(
      rgba,
      width,
      height,
      seamMask,
    );

    final srcDisc = _sourceCoordNeighborDiscontinuity(
      srcXField: srcXField,
      srcYField: srcYField,
      hitMask: hitMask,
      width: width,
      height: height,
      x0: roi.x0,
      y0: roi.y0,
      x1: roi.x1,
      y1: roi.y1,
    );

    final seamCorr = _seamRgbJumpCorrelation(
      rgba: rgba,
      width: width,
      height: height,
      seamMask: seamMask,
      jumpThreshold: 40,
    );

    return {
      'globalRgbMaxHorizJump': globalRgb.max,
      'globalRgbP95HorizJump': globalRgb.p95,
      'faceRoiRgbMaxHorizJump': faceRgb.max,
      'faceRoiRgbP95HorizJump': faceRgb.p95,
      'seamRegionRgbMaxHorizJump': seamRgb.max,
      'seamRegionRgbP95HorizJump': seamRgb.p95,
      'sourceCoordMaxHorizJump': srcDisc.maxHoriz,
      'sourceCoordP95HorizJump': srcDisc.p95Horiz,
      'sourceCoordMaxVertJump': srcDisc.maxVert,
      'sourceCoordP95VertJump': srcDisc.p95Vert,
      'seamRgbJumpCorrelation': seamCorr.correlation,
      'highJumpPixels': seamCorr.highJumpPixels,
      'highJumpNearSeamPixels': seamCorr.highJumpNearSeamPixels,
    };
  }

  static List<_SharedEdgePair> _buildSharedEdgePairs(TriMesh mesh) {
    final edgeMap = <String, List<_EdgeRef>>{};

    for (var t = 0; t < mesh.triangleCount; t++) {
      final i0 = mesh.indices[t * 3];
      final i1 = mesh.indices[t * 3 + 1];
      final i2 = mesh.indices[t * 3 + 2];
      _addEdge(edgeMap, t, i0, i1);
      _addEdge(edgeMap, t, i1, i2);
      _addEdge(edgeMap, t, i2, i0);
    }

    final pairs = <_SharedEdgePair>[];
    for (final entry in edgeMap.entries) {
      if (entry.value.length != 2) {
        continue;
      }
      final a = entry.value[0];
      final b = entry.value[1];
      pairs.add(
        _SharedEdgePair(
          triA: a.triIndex,
          triB: b.triIndex,
          vertex0: a.v0,
          vertex1: a.v1,
        ),
      );
    }
    return pairs;
  }

  static void _addEdge(
    Map<String, List<_EdgeRef>> map,
    int triIndex,
    int va,
    int vb,
  ) {
    final lo = va < vb ? va : vb;
    final hi = va < vb ? vb : va;
    final key = '$lo-$hi';
    (map[key] ??= <_EdgeRef>[]).add(
      _EdgeRef(triIndex: triIndex, v0: lo, v1: hi),
    );
  }

  static ({double srcX, double srcY})? _sourceAtTriangle({
    required TriMesh sourceMesh,
    required TriMesh deformedMesh,
    required int triIndex,
    required double px,
    required double py,
  }) {
    final hit = _barycentricInTriangle(deformedMesh, triIndex, px, py);
    if (hit == null) {
      return null;
    }
    return _sourceFromHit(sourceMesh, hit);
  }

  static BarycentricHit? _barycentricInTriangle(
    TriMesh mesh,
    int t,
    double px,
    double py,
  ) {
    final i0 = mesh.indices[t * 3];
    final i1 = mesh.indices[t * 3 + 1];
    final i2 = mesh.indices[t * 3 + 2];
    final ax = mesh.vertices[i0 * 2];
    final ay = mesh.vertices[i0 * 2 + 1];
    final bx = mesh.vertices[i1 * 2];
    final by = mesh.vertices[i1 * 2 + 1];
    final cxv = mesh.vertices[i2 * 2];
    final cyv = mesh.vertices[i2 * 2 + 1];
    final denom = (by - cyv) * (ax - cxv) + (cxv - bx) * (ay - cyv);
    if (denom.abs() < 1e-12) {
      return null;
    }
    final w0 = ((by - cyv) * (px - cxv) + (cxv - bx) * (py - cyv)) / denom;
    final w1 = ((cyv - ay) * (px - cxv) + (ax - cxv) * (py - cyv)) / denom;
    final w2 = 1.0 - w0 - w1;
    if (w0 < -1e-4 || w1 < -1e-4 || w2 < -1e-4) {
      return null;
    }
    return BarycentricHit(
      i0: i0,
      i1: i1,
      i2: i2,
      w0: w0,
      w1: w1,
      w2: w2,
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

  static String _inferRegion(TriMesh mesh, int triIndex) {
    final i0 = mesh.indices[triIndex * 3];
    final i1 = mesh.indices[triIndex * 3 + 1];
    final i2 = mesh.indices[triIndex * 3 + 2];
    final verts = {i0, i1, i2};

    MeshRegion? best;
    var bestScore = 0;
    for (final entry in mesh.regionBuffers.entries) {
      final bufSet = entry.value.toSet();
      final score = verts.where(bufSet.contains).length;
      if (score > bestScore) {
        bestScore = score;
        best = entry.key;
      }
    }
    return best?.name ?? 'unknown';
  }

  static void _writeSeamImages({
    required int width,
    required int height,
    required List<_ProblematicEdge> problematicEdges,
    required String seamsPath,
    required String heatmapPath,
  }) {
    final seams = img.Image(width: width, height: height);
    img.fill(seams, color: img.ColorRgb8(0, 0, 0));

    final heatmap = img.Image(width: width, height: height);
    img.fill(heatmap, color: img.ColorRgb8(0, 0, 0));

    var maxDelta = 1.0;
    for (final e in problematicEdges) {
      if (e.maxDelta > maxDelta) {
        maxDelta = e.maxDelta;
      }
    }

    for (final e in problematicEdges) {
      final x0 = e.dest0.dx.round().clamp(0, width - 1);
      final y0 = e.dest0.dy.round().clamp(0, height - 1);
      final x1 = e.dest1.dx.round().clamp(0, width - 1);
      final y1 = e.dest1.dy.round().clamp(0, height - 1);

      img.drawLine(
        seams,
        x1: x0,
        y1: y0,
        x2: x1,
        y2: y1,
        color: img.ColorRgb8(255, 60, 60),
        thickness: 2,
      );

      final t = (e.maxDelta / maxDelta).clamp(0.0, 1.0);
      final r = (255 * t).round().clamp(0, 255);
      final g = (255 * (1.0 - t)).round().clamp(0, 255);
      img.drawLine(
        heatmap,
        x1: x0,
        y1: y0,
        x2: x1,
        y2: y1,
        color: img.ColorRgb8(r, g, 0),
        thickness: 3,
      );
    }

    File(seamsPath).writeAsBytesSync(img.encodePng(seams));
    File(heatmapPath).writeAsBytesSync(img.encodePng(heatmap));
  }

  static Uint8List _rasterizeEdgeMask({
    required int width,
    required int height,
    required List<_ProblematicEdge> edges,
    required int radius,
  }) {
    final mask = Uint8List(width * height);
    for (final e in edges) {
      _stampLineMask(
        mask,
        width,
        height,
        x0: e.dest0.dx,
        y0: e.dest0.dy,
        x1: e.dest1.dx,
        y1: e.dest1.dy,
        radius: radius,
      );
    }
    return mask;
  }

  static void _stampLineMask(
    Uint8List mask,
    int width,
    int height, {
    required double x0,
    required double y0,
    required double x1,
    required double y1,
    required int radius,
  }) {
    final steps = (math.max(
              (x1 - x0).abs(),
              (y1 - y0).abs(),
            ) *
            2)
        .ceil()
        .clamp(1, 4096);
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final cx = (x0 + t * (x1 - x0)).round();
      final cy = (y0 + t * (y1 - y0)).round();
      for (var dy = -radius; dy <= radius; dy++) {
        for (var dx = -radius; dx <= radius; dx++) {
          if (dx * dx + dy * dy > radius * radius) {
            continue;
          }
          final x = cx + dx;
          final y = cy + dy;
          if (x < 0 || y < 0 || x >= width || y >= height) {
            continue;
          }
          mask[y * width + x] = 1;
        }
      }
    }
  }

  static ({
    double max,
    double p95,
  }) _rgbHorizontalDiscontinuity(
    Uint8List rgba,
    int width,
    int height,
    int x0,
    int y0,
    int x1,
    int y1,
  ) {
    final samples = <double>[];
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x < x1; x++) {
        final p0 = (y * width + x) * 4;
        final p1 = (y * width + x + 1) * 4;
        final dr = (rgba[p1] - rgba[p0]).abs();
        final dg = (rgba[p1 + 1] - rgba[p0 + 1]).abs();
        final db = (rgba[p1 + 2] - rgba[p0 + 2]).abs();
        samples.add(math.max(dr, math.max(dg, db)).toDouble());
      }
    }
    samples.sort();
    return (
      max: samples.isEmpty ? 0.0 : samples.last,
      p95: _percentile(samples, 0.95),
    );
  }

  static ({
    double max,
    double p95,
  }) _rgbHorizontalDiscontinuityMasked(
    Uint8List rgba,
    int width,
    int height,
    Uint8List mask,
  ) {
    final samples = <double>[];
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width - 1; x++) {
        final p = y * width + x;
        if (mask[p] == 0 && mask[p + 1] == 0) {
          continue;
        }
        final p0 = p * 4;
        final p1 = (p + 1) * 4;
        final dr = (rgba[p1] - rgba[p0]).abs();
        final dg = (rgba[p1 + 1] - rgba[p0 + 1]).abs();
        final db = (rgba[p1 + 2] - rgba[p0 + 2]).abs();
        samples.add(math.max(dr, math.max(dg, db)).toDouble());
      }
    }
    samples.sort();
    return (
      max: samples.isEmpty ? 0.0 : samples.last,
      p95: _percentile(samples, 0.95),
    );
  }

  static ({
    double maxHoriz,
    double p95Horiz,
    double maxVert,
    double p95Vert,
  }) _sourceCoordNeighborDiscontinuity({
    required Float32List srcXField,
    required Float32List srcYField,
    required Uint8List hitMask,
    required int width,
    required int height,
    required int x0,
    required int y0,
    required int x1,
    required int y1,
  }) {
    final horiz = <double>[];
    final vert = <double>[];

    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x < x1; x++) {
        final p0 = y * width + x;
        final p1 = y * width + x + 1;
        if (hitMask[p0] == 0 || hitMask[p1] == 0) {
          continue;
        }
        final dx = srcXField[p1] - srcXField[p0];
        final dy = srcYField[p1] - srcYField[p0];
        if (dx.isNaN || dy.isNaN) {
          continue;
        }
        horiz.add(math.sqrt(dx * dx + dy * dy));
      }
    }

    for (var y = y0; y < y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final p0 = y * width + x;
        final p1 = (y + 1) * width + x;
        if (hitMask[p0] == 0 || hitMask[p1] == 0) {
          continue;
        }
        final dx = srcXField[p1] - srcXField[p0];
        final dy = srcYField[p1] - srcYField[p0];
        if (dx.isNaN || dy.isNaN) {
          continue;
        }
        vert.add(math.sqrt(dx * dx + dy * dy));
      }
    }

    horiz.sort();
    vert.sort();
    return (
      maxHoriz: horiz.isEmpty ? 0.0 : horiz.last,
      p95Horiz: _percentile(horiz, 0.95),
      maxVert: vert.isEmpty ? 0.0 : vert.last,
      p95Vert: _percentile(vert, 0.95),
    );
  }

  static ({
    double correlation,
    int highJumpPixels,
    int highJumpNearSeamPixels,
  }) _seamRgbJumpCorrelation({
    required Uint8List rgba,
    required int width,
    required int height,
    required Uint8List seamMask,
    required int jumpThreshold,
  }) {
    var highJump = 0;
    var highJumpNearSeam = 0;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width - 1; x++) {
        final p = y * width + x;
        final p0 = p * 4;
        final p1 = (p + 1) * 4;
        final dr = (rgba[p1] - rgba[p0]).abs();
        final dg = (rgba[p1 + 1] - rgba[p0 + 1]).abs();
        final db = (rgba[p1 + 2] - rgba[p0 + 2]).abs();
        final jump = math.max(dr, math.max(dg, db));
        if (jump < jumpThreshold) {
          continue;
        }
        highJump++;
        if (seamMask[p] == 1 || seamMask[p + 1] == 1) {
          highJumpNearSeam++;
        }
      }
    }

    return (
      correlation: highJump > 0 ? highJumpNearSeam / highJump : 0.0,
      highJumpPixels: highJump,
      highJumpNearSeamPixels: highJumpNearSeam,
    );
  }

  static List<int> _sampleBilinear(
    Uint8List rgba,
    int width,
    int height,
    double x,
    double y,
  ) {
    if (x < 0 || y < 0 || x >= width - 1 || y >= height - 1) {
      final cx = x.clamp(0, width - 1).round();
      final cy = y.clamp(0, height - 1).round();
      final idx = (cy * width + cx) * 4;
      return [rgba[idx], rgba[idx + 1], rgba[idx + 2], rgba[idx + 3]];
    }

    final x0 = x.floor();
    final y0 = y.floor();
    final tx = x - x0;
    final ty = y - y0;

    final c00 = _pixel(rgba, width, x0, y0);
    final c10 = _pixel(rgba, width, x0 + 1, y0);
    final c01 = _pixel(rgba, width, x0, y0 + 1);
    final c11 = _pixel(rgba, width, x0 + 1, y0 + 1);

    return List.generate(4, (c) {
      final v = _lerp(
        _lerp(c00[c].toDouble(), c10[c].toDouble(), tx),
        _lerp(c01[c].toDouble(), c11[c].toDouble(), tx),
        ty,
      );
      return v.round().clamp(0, 255);
    });
  }

  static List<int> _pixel(Uint8List rgba, int width, int x, int y) {
    final idx = (y * width + x) * 4;
    return [rgba[idx], rgba[idx + 1], rgba[idx + 2], rgba[idx + 3]];
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

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

  static void _writeRgbaPng(String path, Uint8List rgba, int width, int height) {
    final image = img.Image(width: width, height: height);
    var offset = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.setPixelRgba(
          x,
          y,
          rgba[offset],
          rgba[offset + 1],
          rgba[offset + 2],
          rgba[offset + 3],
        );
        offset += 4;
      }
    }
    File(path).writeAsBytesSync(img.encodePng(image));
  }
}

class _EdgeRef {
  const _EdgeRef({
    required this.triIndex,
    required this.v0,
    required this.v1,
  });

  final int triIndex;
  final int v0;
  final int v1;
}

class _SharedEdgePair {
  const _SharedEdgePair({
    required this.triA,
    required this.triB,
    required this.vertex0,
    required this.vertex1,
  });

  final int triA;
  final int triB;
  final int vertex0;
  final int vertex1;
}

class _ProblematicEdge {
  const _ProblematicEdge({
    required this.triA,
    required this.triB,
    required this.vertex0,
    required this.vertex1,
    required this.source0,
    required this.source1,
    required this.dest0,
    required this.dest1,
    required this.maxDelta,
    required this.maxLocateDelta,
    required this.side,
    required this.region,
    required this.samples,
  });

  final int triA;
  final int triB;
  final int vertex0;
  final int vertex1;
  final Offset source0;
  final Offset source1;
  final Offset dest0;
  final Offset dest1;
  final double maxDelta;
  final double maxLocateDelta;
  final String side;
  final String region;
  final List<Map<String, dynamic>> samples;
}
