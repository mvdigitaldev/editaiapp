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
import 'face_warp_renderer.dart' show GeometricSupport, FaceWarpFieldMetrics;

/// Resultado do diagnóstico de locate (Fase 3).
class TriMeshLocateDiagnosticResult {
  const TriMeshLocateDiagnosticResult({
    required this.implementationDoc,
    required this.fullScanComparison,
    required this.epsilonSweep,
    required this.neighborDiscontinuities,
    required this.candidatesJsonl,
    required this.locateBugPng,
    required this.locateDiscontinuitiesPng,
    required this.pureRemapMetrics,
  });

  final Map<String, dynamic> implementationDoc;
  final Map<String, dynamic> fullScanComparison;
  final Map<String, dynamic> epsilonSweep;
  final Map<String, dynamic> neighborDiscontinuities;
  final String candidatesJsonl;
  final String locateBugPng;
  final String locateDiscontinuitiesPng;
  final Map<String, dynamic> pureRemapMetrics;
}

/// Diagnóstico Fase 3 — locate vs fullScan, candidatos, vizinhança, epsilons.
abstract final class TriMeshLocateDiagnostic {
  TriMeshLocateDiagnostic._();

  static const _defaultOutputDir =
      '/Users/leonardo/Documents/Projetos/editaiapp/.cursor';

  static Future<TriMeshLocateDiagnosticResult?> run({
    required Uint8List sourceRgba,
    required int width,
    required int height,
    required FaceMeshForwardPayload payload,
    String runId = 'locate-diagnostic-90',
    String? outputDirectory,
  }) async {
    if (!kDebugMode || sourceRgba.isEmpty) {
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
      final spatialIndex = built.spatialIndex;
      final legacyIndex = _LegacyTriMeshSpatialIndex(
        built.deformedMesh,
        imageWidth: width.toDouble(),
        imageHeight: height.toDouble(),
      );
      final roi = built.roi;

      final implDoc = _documentImplementation(spatialIndex);

      final fullScan = _compareLocateVsFullScan(
        spatialIndex: spatialIndex,
        legacyIndex: legacyIndex,
        sourceMesh: built.sourceMesh,
        roi: roi,
        width: width,
        height: height,
      );

      final epsilonSweep = _epsilonSweep(
        spatialIndex: spatialIndex,
        roi: roi,
        width: width,
        height: height,
      );

      final neighbor = _analyzeNeighborDiscontinuities(
        spatialIndex: spatialIndex,
        sourceMesh: built.sourceMesh,
        roi: roi,
        width: width,
        height: height,
      );

      final candidatesJsonl = '$outDir/debug-locate-candidates.jsonl';
      final locateBugPng = '$outDir/debug-face-slim-locate-bug.png';
      _writeCandidateRecords(
        path: candidatesJsonl,
        bugPngPath: locateBugPng,
        spatialIndex: spatialIndex,
        legacyIndex: legacyIndex,
        sourceMesh: built.sourceMesh,
        fullScanComparison: fullScan,
        width: width,
        height: height,
      );

      final discontinuitiesPng = '$outDir/debug-face-slim-locate-discontinuities.png';
      _writeDiscontinuityImage(
        path: discontinuitiesPng,
        width: width,
        height: height,
        events: neighbor.events,
      );

      final pureRemap = _pureRemapMetrics(
        spatialIndex: spatialIndex,
        sourceMesh: built.sourceMesh,
        sourceRgba: sourceRgba,
        roi: roi,
        width: width,
        height: height,
      );

      AgentDebugLog.write(
        location: 'tri_mesh_locate_diagnostic.dart:run',
        message: 'phase3_locate_diagnostic',
        hypothesisId: 'P3LOC',
        runId: runId,
        phase: '3',
        data: {
          'implementationDoc': implDoc,
          'fullScanComparison': fullScan,
          'epsilonSweep': epsilonSweep,
          'neighborDiscontinuities': {
            'countGt5px': neighbor.countGt5px,
            'maxSourceDelta': neighbor.maxSourceDelta,
            'p95SourceDelta': neighbor.p95SourceDelta,
          },
          'pureRemapMetrics': pureRemap,
          'candidatesJsonl': candidatesJsonl,
          'locateBugPng': locateBugPng,
          'locateDiscontinuitiesPng': discontinuitiesPng,
        },
      );

      return TriMeshLocateDiagnosticResult(
        implementationDoc: implDoc,
        fullScanComparison: fullScan,
        epsilonSweep: epsilonSweep,
        neighborDiscontinuities: {
          'countGt5px': neighbor.countGt5px,
          'maxSourceDelta': neighbor.maxSourceDelta,
          'p95SourceDelta': neighbor.p95SourceDelta,
          'sampleCount': neighbor.events.length,
        },
        candidatesJsonl: candidatesJsonl,
        locateBugPng: locateBugPng,
        locateDiscontinuitiesPng: discontinuitiesPng,
        pureRemapMetrics: pureRemap,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('TriMeshLocateDiagnostic failed: $e\n$st');
      }
      return null;
    }
  }

  /// Métricas de remap puro com locate corrigido (sem FaceWarpRenderer).
  static Map<String, dynamic> pureRemapMetricsFromPayload({
    required FaceMeshForwardPayload payload,
    required int width,
    required int height,
    required Uint8List sourceRgba,
  }) {
    final built = _buildDeformedContext(
      payload: payload,
      width: width,
      height: height,
    );
    return _pureRemapMetrics(
      spatialIndex: built.spatialIndex,
      sourceMesh: built.sourceMesh,
      sourceRgba: sourceRgba,
      roi: built.roi,
      width: width,
      height: height,
    );
  }

  static Map<String, dynamic> _documentImplementation(
    TriMeshSpatialIndex index,
  ) {
    return {
      'cellSize': index.cellSize,
      'bucketMarginCells': 1,
      'queryRadii': [1, 2, 3],
      'barycentricEpsilon': TriMeshSpatialIndex.defaultBarycentricEpsilon,
      'bucketCalculation':
          'floor(minCoord/cell)-margin .. floor(maxCoord/cell)+margin per triangle AABB',
      'candidateFilter':
          'barycentric w0,w1,w2 >= -epsilon; pick max(min(w0,w1,w2)), tie-break lower tri index',
      'selectionRule': 'maxMinBarycentric_not_firstHit',
      'fullScanAvailable': true,
      'legacyBehavior':
          'Set iteration first-valid, 3x3 buckets, no AABB margin, epsilon 1e-4',
    };
  }

  static Map<String, dynamic> _compareLocateVsFullScan({
    required TriMeshSpatialIndex spatialIndex,
    required _LegacyTriMeshSpatialIndex legacyIndex,
    required TriMesh sourceMesh,
    required ({int x0, int y0, int x1, int y1}) roi,
    required int width,
    required int height,
  }) {
    var mismatched = 0;
    var legacyMismatch = 0;
    var roiPixels = 0;
    var bothHit = 0;
    final sourceDiffs = <double>[];
    final legacySourceDiffs = <double>[];
    var gt1 = 0;
    var gt5 = 0;
    var gt10 = 0;
    var legacyGt1 = 0;

    for (var y = roi.y0; y <= roi.y1; y++) {
      final py = y + 0.5;
      for (var x = roi.x0; x <= roi.x1; x++) {
        final px = x + 0.5;
        roiPixels++;

        final triLocate = spatialIndex.locateTriangleIndex(px, py);
        final triFull = spatialIndex.locateTriangleIndexFullScan(px, py);
        final triLegacy = legacyIndex.locateTriangleIndex(px, py);

        if (triLocate == null && triFull == null) {
          continue;
        }
        bothHit++;

        if (triLocate != triFull) {
          mismatched++;
        }
        if (triLegacy != triFull) {
          legacyMismatch++;
        }

        final srcLocate = _sourceFromTriangle(sourceMesh, spatialIndex, px, py);
        final srcFull = _sourceFromTriangleIndex(
          sourceMesh,
          spatialIndex,
          triFull,
          px,
          py,
        );
        if (srcLocate != null && srcFull != null) {
          final d = _dist(
            srcLocate.srcX,
            srcLocate.srcY,
            srcFull.srcX,
            srcFull.srcY,
          );
          sourceDiffs.add(d);
          if (d > 1) {
            gt1++;
          }
          if (d > 5) {
            gt5++;
          }
          if (d > 10) {
            gt10++;
          }
        }

        final srcLegacy = _sourceFromTriangleIndex(
          sourceMesh,
          spatialIndex,
          triLegacy,
          px,
          py,
        );
        if (srcLegacy != null && srcFull != null) {
          legacySourceDiffs.add(
            _dist(
              srcLegacy.srcX,
              srcLegacy.srcY,
              srcFull.srcX,
              srcFull.srcY,
            ),
          );
          if (_dist(
                srcLegacy.srcX,
                srcLegacy.srcY,
                srcFull.srcX,
                srcFull.srcY,
              ) >
              1) {
            legacyGt1++;
          }
        }
      }
    }

    sourceDiffs.sort();
    legacySourceDiffs.sort();

    return {
      'roiPixels': roiPixels,
      'bothHitPixels': bothHit,
      'mismatchedTrianglePixels': mismatched,
      'mismatchRatio': bothHit > 0 ? mismatched / bothHit : 0.0,
      'legacyMismatchedTrianglePixels': legacyMismatch,
      'legacyMismatchRatio': bothHit > 0 ? legacyMismatch / bothHit : 0.0,
      'maxSourceCoordDifference':
          sourceDiffs.isEmpty ? 0.0 : sourceDiffs.last,
      'p95SourceCoordDifference': _percentile(sourceDiffs, 0.95),
      'mismatchPixelsGt1px': gt1,
      'mismatchPixelsGt5px': gt5,
      'mismatchPixelsGt10px': gt10,
      'legacyMaxSourceCoordDifference':
          legacySourceDiffs.isEmpty ? 0.0 : legacySourceDiffs.last,
      'legacyMismatchPixelsGt1px': legacyGt1,
    };
  }

  static Map<String, dynamic> _epsilonSweep({
    required TriMeshSpatialIndex spatialIndex,
    required ({int x0, int y0, int x1, int y1}) roi,
    required int width,
    required int height,
  }) {
    const epsilons = [1e-8, 1e-7, 1e-6, 1e-5, 1e-4];
    final results = <String, dynamic>{};

    for (final eps in epsilons) {
      var mismatched = 0;
      var bothHit = 0;
      for (var y = roi.y0; y <= roi.y1; y++) {
        final py = y + 0.5;
        for (var x = roi.x0; x <= roi.x1; x++) {
          final px = x + 0.5;
          final triBucket = spatialIndex.locateTriangleIndex(px, py);
          final triFull = spatialIndex.locateTriangleIndexFullScan(
            px,
            py,
            epsilon: eps,
          );
          if (triBucket == null && triFull == null) {
            continue;
          }
          bothHit++;
          if (triBucket != triFull) {
            mismatched++;
          }
        }
      }
      results[eps.toString()] = {
        'bothHitPixels': bothHit,
        'mismatchedTrianglePixels': mismatched,
        'mismatchRatio': bothHit > 0 ? mismatched / bothHit : 0.0,
      };
    }
    return results;
  }

  static ({
    int countGt5px,
    double maxSourceDelta,
    double p95SourceDelta,
    List<_NeighborEvent> events,
  }) _analyzeNeighborDiscontinuities({
    required TriMeshSpatialIndex spatialIndex,
    required TriMesh sourceMesh,
    required ({int x0, int y0, int x1, int y1}) roi,
    required int width,
    required int height,
  }) {
    final events = <_NeighborEvent>[];
    final deltas = <double>[];

    for (var y = roi.y0; y <= roi.y1; y++) {
      final py = y + 0.5;
      for (var x = roi.x0; x <= roi.x1; x++) {
        final px = x + 0.5;
        final hit = spatialIndex.locate(px, py);
        if (hit == null) {
          continue;
        }
        final src = _sourceFromHit(sourceMesh, hit);
        if (src == null) {
          continue;
        }

        const neighbors = [
          (-1, 0),
          (1, 0),
          (0, -1),
          (0, 1),
        ];
        for (final (dx, dy) in neighbors) {
          final nx = x + dx;
          final ny = y + dy;
          if (nx < roi.x0 || nx > roi.x1 || ny < roi.y0 || ny > roi.y1) {
            continue;
          }
          final nHit = spatialIndex.locate(nx + 0.5, ny + 0.5);
          if (nHit == null) {
            continue;
          }
          final nSrc = _sourceFromHit(sourceMesh, nHit);
          if (nSrc == null) {
            continue;
          }
          final delta = _dist(src.srcX, src.srcY, nSrc.srcX, nSrc.srcY);
          if (delta <= 5) {
            continue;
          }
          deltas.add(delta);
          events.add(
            _NeighborEvent(
              x: x,
              y: y,
              nx: nx,
              ny: ny,
              triA: spatialIndex.locateTriangleIndex(px, py),
              triB: spatialIndex.locateTriangleIndex(nx + 0.5, ny + 0.5),
              srcA: src,
              srcB: nSrc,
              hitA: hit,
              hitB: nHit,
              delta: delta,
            ),
          );
        }
      }
    }

    deltas.sort();
    return (
      countGt5px: events.length,
      maxSourceDelta: deltas.isEmpty ? 0.0 : deltas.last,
      p95SourceDelta: _percentile(deltas, 0.95),
      events: events,
    );
  }

  static void _writeCandidateRecords({
    required String path,
    required String bugPngPath,
    required TriMeshSpatialIndex spatialIndex,
    required _LegacyTriMeshSpatialIndex legacyIndex,
    required TriMesh sourceMesh,
    required Map<String, dynamic> fullScanComparison,
    required int width,
    required int height,
  }) {
    final file = File(path);
    if (file.existsSync()) {
      file.deleteSync();
    }
    final sink = file.openWrite(mode: FileMode.writeOnlyAppend);

    final bugImg = img.Image(width: width, height: height);
    img.fill(bugImg, color: img.ColorRgb8(0, 0, 0));

    // Re-scan ROI for legacy locate delta > 1px vs fullScan source
    final roi = _roiFromDeformedMesh(spatialIndex.mesh, width, height);
    var recordCount = 0;

    for (var y = roi.y0; y <= roi.y1; y++) {
      final py = y + 0.5;
      for (var x = roi.x0; x <= roi.x1; x++) {
        final px = x + 0.5;
        final triLegacy = legacyIndex.locateTriangleIndex(px, py);
        final triFull = spatialIndex.locateTriangleIndexFullScan(px, py);
        if (triLegacy == null || triFull == null) {
          continue;
        }

        final srcLegacy = _sourceFromTriangleIndex(
          sourceMesh,
          spatialIndex,
          triLegacy,
          px,
          py,
        );
        final srcFull = _sourceFromTriangleIndex(
          sourceMesh,
          spatialIndex,
          triFull,
          px,
          py,
        );
        if (srcLegacy == null || srcFull == null) {
          continue;
        }

        final delta = _dist(
          srcLegacy.srcX,
          srcLegacy.srcY,
          srcFull.srcX,
          srcFull.srcY,
        );
        if (delta <= 1.0) {
          continue;
        }

        recordCount++;
        final cell = spatialIndex.queryCell(px, py);
        final candidates = spatialIndex.collectCandidates(px, py, radius: 1);
        final candidateDetails = <Map<String, dynamic>>[];

        for (final t in candidates) {
          final hit = spatialIndex.barycentricInTriangle(t, px, py);
          final aabb = spatialIndex.triangleAabb(t);
          final src = hit == null
              ? null
              : _sourceFromHit(sourceMesh, hit);
          candidateDetails.add({
            'triIndex': t,
            'valid': hit != null,
            'barycentric': hit == null
                ? null
                : {'w0': hit.w0, 'w1': hit.w1, 'w2': hit.w2},
            'minBarycentric': hit?.minWeight,
            'source': src == null ? null : {'x': src.srcX, 'y': src.srcY},
            'aabb': {
              'minX': aabb.minX,
              'minY': aabb.minY,
              'maxX': aabb.maxX,
              'maxY': aabb.maxY,
            },
          });
        }

        sink.writeln(
          jsonEncode({
            'destinationX': px,
            'destinationY': py,
            'pixelX': x,
            'pixelY': y,
            'legacyTriangle': triLegacy,
            'fullScanTriangle': triFull,
            'currentLocateTriangle':
                spatialIndex.locateTriangleIndex(px, py),
            'sourceDeltaLegacyVsFull': delta,
            'queryCell': {'cx': cell.cx, 'cy': cell.cy},
            'candidateCount': candidates.length,
            'candidates': candidateDetails,
          }),
        );

        bugImg.setPixelRgb(x, y, 255, 40, 40);
      }
    }

    sink.close();
    File(bugPngPath).writeAsBytesSync(img.encodePng(bugImg));

    fullScanComparison['candidateRecordCount'] = recordCount;
  }

  static void _writeDiscontinuityImage({
    required String path,
    required int width,
    required int height,
    required List<_NeighborEvent> events,
  }) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(0, 0, 0));

    var maxDelta = 5.0;
    for (final e in events) {
      if (e.delta > maxDelta) {
        maxDelta = e.delta;
      }
    }

    for (final e in events) {
      final t = ((e.delta - 5) / (maxDelta - 5)).clamp(0.0, 1.0);
      final r = (255 * t).round();
      image.setPixelRgb(e.x, e.y, r, 40, 40);
      image.setPixelRgb(e.nx, e.ny, r, 40, 40);
    }

    File(path).writeAsBytesSync(img.encodePng(image));
  }

  static Map<String, dynamic> _pureRemapMetrics({
    required TriMeshSpatialIndex spatialIndex,
    required TriMesh sourceMesh,
    required Uint8List sourceRgba,
    required ({int x0, int y0, int x1, int y1}) roi,
    required int width,
    required int height,
  }) {
    final pixelCount = width * height;
    final srcXField =
        Float32List(pixelCount)..fillRange(0, pixelCount, double.nan);
    final srcYField =
        Float32List(pixelCount)..fillRange(0, pixelCount, double.nan);
    final hitMask = Uint8List(pixelCount);
    var meshHitPx = 0;
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
        srcXField[p] = src.srcX;
        srcYField[p] = src.srcY;
        hitMask[p] = 1;
        meshHitPx++;
      }
      for (var col = 0; col < rowTris.length; col++) {
        topSrcX[col] = rowSrcX[col];
        topSrcY[col] = rowSrcY[col];
      }
    }

    final roiPixels = (roi.x1 - roi.x0 + 1) * (roi.y1 - roi.y0 + 1);
    final disc = _sourceCoordNeighborDiscontinuity(
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

    return {
      'meshHitPx': meshHitPx,
      'coverageRatio': roiPixels > 0 ? meshHitPx / roiPixels : 0.0,
      'sourceCoordMaxHorizJump': disc.maxHoriz,
      'sourceCoordP95HorizJump': disc.p95Horiz,
      'sourceCoordMaxVertJump': disc.maxVert,
      'sourceCoordP95VertJump': disc.p95Vert,
    };
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

  static ({double srcX, double srcY})? _sourceFromTriangle(
    TriMesh sourceMesh,
    TriMeshSpatialIndex index,
    double px,
    double py,
  ) {
    final hit = index.locate(px, py);
    if (hit == null) {
      return null;
    }
    return _sourceFromHit(sourceMesh, hit);
  }

  static ({double srcX, double srcY})? _sourceFromTriangleIndex(
    TriMesh sourceMesh,
    TriMeshSpatialIndex index,
    int? tri,
    double px,
    double py,
  ) {
    if (tri == null) {
      return null;
    }
    final hit = index.barycentricInTriangle(tri, px, py);
    if (hit == null) {
      return null;
    }
    return _sourceFromHit(sourceMesh, hit);
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

class _NeighborEvent {
  const _NeighborEvent({
    required this.x,
    required this.y,
    required this.nx,
    required this.ny,
    required this.triA,
    required this.triB,
    required this.srcA,
    required this.srcB,
    required this.hitA,
    required this.hitB,
    required this.delta,
  });

  final int x;
  final int y;
  final int nx;
  final int ny;
  final int? triA;
  final int? triB;
  final ({double srcX, double srcY}) srcA;
  final ({double srcX, double srcY}) srcB;
  final BarycentricHit hitA;
  final BarycentricHit hitB;
  final double delta;
}

/// Comportamento legado (pré-Fase 3) — somente diagnóstico.
class _LegacyTriMeshSpatialIndex {
  _LegacyTriMeshSpatialIndex(
    this._mesh, {
    required this.imageWidth,
    required this.imageHeight,
  }) {
    final cell = math.max(
      6.0,
      math.min(imageWidth, imageHeight) / 48,
    );
    _cellSize = cell;
    for (var t = 0; t < _mesh.triangleCount; t++) {
      final i0 = _mesh.indices[t * 3];
      final i1 = _mesh.indices[t * 3 + 1];
      final i2 = _mesh.indices[t * 3 + 2];
      final ax = _mesh.vertices[i0 * 2];
      final ay = _mesh.vertices[i0 * 2 + 1];
      final bx = _mesh.vertices[i1 * 2];
      final by = _mesh.vertices[i1 * 2 + 1];
      final cx = _mesh.vertices[i2 * 2];
      final cy = _mesh.vertices[i2 * 2 + 1];
      final minX = math.min(ax, math.min(bx, cx));
      final maxX = math.max(ax, math.max(bx, cx));
      final minY = math.min(ay, math.min(by, cy));
      final maxY = math.max(ay, math.max(by, cy));
      final x0 = (minX / cell).floor();
      final x1 = (maxX / cell).floor();
      final y0 = (minY / cell).floor();
      final y1 = (maxY / cell).floor();
      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          (_triBuckets[SpatialHash2D.pack(x, y)] ??= <int>[]).add(t);
        }
      }
    }
  }

  final TriMesh _mesh;
  final double imageWidth;
  final double imageHeight;
  late final double _cellSize;
  final Map<int, List<int>> _triBuckets = {};

  int? locateTriangleIndex(double px, double py) {
    final cx = (px / _cellSize).floor();
    final cy = (py / _cellSize).floor();
    final candidates = <int>{};
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final bucket = _triBuckets[SpatialHash2D.pack(cx + dx, cy + dy)];
        if (bucket != null) {
          candidates.addAll(bucket);
        }
      }
    }
    for (final t in candidates) {
      if (_barycentricInTriangle(t, px, py) != null) {
        return t;
      }
    }
    return null;
  }

  BarycentricHit? _barycentricInTriangle(int t, double px, double py) {
    final i0 = _mesh.indices[t * 3];
    final i1 = _mesh.indices[t * 3 + 1];
    final i2 = _mesh.indices[t * 3 + 2];
    final ax = _mesh.vertices[i0 * 2];
    final ay = _mesh.vertices[i0 * 2 + 1];
    final bx = _mesh.vertices[i1 * 2];
    final by = _mesh.vertices[i1 * 2 + 1];
    final cxv = _mesh.vertices[i2 * 2];
    final cyv = _mesh.vertices[i2 * 2 + 1];
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
}
