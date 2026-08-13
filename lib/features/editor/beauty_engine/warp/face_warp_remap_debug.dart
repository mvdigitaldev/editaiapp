import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../debug/agent_debug_log.dart';
import '../filters/face/face_warp_utils.dart';
import '../mesh/tri_mesh_spatial_index.dart';
import '../models/tri_mesh.dart';
import 'face_mesh_forward_warp.dart';
import 'face_warp_render_contract.dart';
import 'face_warp_renderer.dart';

/// Caminhos dos mapas PPM gerados por [FaceWarpRemapDebug].
class FaceWarpRemapDebugPaths {
  const FaceWarpRemapDebugPaths({
    required this.coveragePpm,
    required this.sourceCoordPpm,
    required this.displacementPpm,
    required this.magnitudePpm,
  });

  final String coveragePpm;
  final String sourceCoordPpm;
  final String displacementPpm;
  final String magnitudePpm;
}

/// Instrumentação visual temporária — backward piecewise-affine em pixel space.
///
/// Usa **exatamente** `TriMeshSpatialIndex.locate()` + baricêntricas sobre
/// vértices source, igual ao loop do [FaceWarpRenderer].
///
/// Não altera output RGBA. Somente [kDebugMode].
abstract final class FaceWarpRemapDebug {
  FaceWarpRemapDebug._();

  static const _defaultOutputDir =
      '/Users/leonardo/Documents/Projetos/editaiapp/.cursor';

  /// Gera coverage / source-coord / displacement / magnitude PPM + NDJSON.
  ///
  /// [coverage] deve ser o array produzido pelo backward renderer (pré hole-fill).
  static FaceWarpRemapDebugPaths? dump({
    required TriMesh sourceMesh,
    required TriMesh deformedMesh,
    required int imageWidth,
    required int imageHeight,
    required TriMeshSpatialIndex spatialIndex,
    required Float32List coverage,
    required String tag,
    String runId = 'remap-debug',
    String? outputDirectory,
  }) {
    if (!kDebugMode) {
      return null;
    }

    try {
      final roi = _roiFromDeformedMesh(deformedMesh, imageWidth, imageHeight);
      final pixelCount = imageWidth * imageHeight;

      final coverageRgb = Uint8List(pixelCount * 3);
      final sourceCoordRgb = Uint8List(pixelCount * 3);
      final displacementRgb = Uint8List(pixelCount * 3);
      final magnitudeRgb = Uint8List(pixelCount * 3);

      final dxField = Float32List(pixelCount)..fillRange(0, pixelCount, double.nan);
      final dyField = Float32List(pixelCount)..fillRange(0, pixelCount, double.nan);
      final srcXField = Float32List(pixelCount)..fillRange(0, pixelCount, double.nan);
      final srcYField = Float32List(pixelCount)..fillRange(0, pixelCount, double.nan);
      final hitMask = Uint8List(pixelCount);

      var hitPixels = 0;
      var missPixels = 0;
      var maxDx = 0.0;
      var maxDy = 0.0;
      var maxMagnitude = 0.0;
      var sumMagnitude = 0.0;
      final magnitudes = <double>[];

      for (var y = roi.y0; y <= roi.y1; y++) {
        final destY = y + 0.5;
        for (var x = roi.x0; x <= roi.x1; x++) {
          final destX = x + 0.5;
          final p = y * imageWidth + x;

          if (coverage[p] <= 0.5) {
            missPixels++;
            continue;
          }

          final hit = spatialIndex.locate(destX, destY);
          if (hit == null) {
            missPixels++;
            continue;
          }

          final src = _sourceCoordFromHit(sourceMesh, hit);
          if (src == null) {
            missPixels++;
            continue;
          }

          final dx = src.srcX - destX;
          final dy = src.srcY - destY;
          final magnitude = math.sqrt(dx * dx + dy * dy);

          hitMask[p] = 1;
          hitPixels++;
          dxField[p] = dx;
          dyField[p] = dy;
          srcXField[p] = src.srcX;
          srcYField[p] = src.srcY;
          sumMagnitude += magnitude;
          magnitudes.add(magnitude);

          if (dx.abs() > maxDx) {
            maxDx = dx.abs();
          }
          if (dy.abs() > maxDy) {
            maxDy = dy.abs();
          }
          if (magnitude > maxMagnitude) {
            maxMagnitude = magnitude;
          }
        }
      }

      for (var p = 0; p < pixelCount; p++) {
        final o = p * 3;
        if (coverage[p] > 0.5) {
          coverageRgb[o] = 255;
          coverageRgb[o + 1] = 255;
          coverageRgb[o + 2] = 255;
        }
      }

      final dispScale = math.max(math.max(maxDx, maxDy), 1e-6);
      final magScale = math.max(maxMagnitude, 1e-6);

      for (var p = 0; p < pixelCount; p++) {
        if (hitMask[p] == 0) {
          continue;
        }
        final o = p * 3;

        sourceCoordRgb[o] =
            ((srcXField[p] / imageWidth).clamp(0.0, 1.0) * 255).round();
        sourceCoordRgb[o + 1] =
            ((srcYField[p] / imageHeight).clamp(0.0, 1.0) * 255).round();

        final dx = dxField[p];
        final dy = dyField[p];
        displacementRgb[o] = (((dx / dispScale) * 0.5 + 0.5) * 255)
            .round()
            .clamp(0, 255);
        displacementRgb[o + 1] = (((dy / dispScale) * 0.5 + 0.5) * 255)
            .round()
            .clamp(0, 255);

        final mag = math.sqrt(dx * dx + dy * dy);
        magnitudeRgb[o] = ((mag / magScale) * 255).round().clamp(0, 255);
      }

      magnitudes.sort();
      final meanMagnitude =
          hitPixels > 0 ? sumMagnitude / hitPixels : 0.0;
      final roiPixels = (roi.x1 - roi.x0 + 1) * (roi.y1 - roi.y0 + 1);
      final coverageRatio = roiPixels > 0 ? hitPixels / roiPixels : 0.0;

      final discontinuities = _collectDiscontinuities(
        dxField: dxField,
        dyField: dyField,
        hitMask: hitMask,
        width: imageWidth,
        height: imageHeight,
        x0: roi.x0,
        y0: roi.y0,
        x1: roi.x1,
        y1: roi.y1,
      );

      final outputDir = outputDirectory ?? _defaultOutputDir;
      final prefix = '$outputDir/debug-remap-$tag';
      final paths = FaceWarpRemapDebugPaths(
        coveragePpm: '$prefix-coverage.ppm',
        sourceCoordPpm: '$prefix-source-coord.ppm',
        displacementPpm: '$prefix-displacement.ppm',
        magnitudePpm: '$prefix-magnitude.ppm',
      );

      _writePpm(paths.coveragePpm, imageWidth, imageHeight, coverageRgb);
      _writePpm(paths.sourceCoordPpm, imageWidth, imageHeight, sourceCoordRgb);
      _writePpm(
        paths.displacementPpm,
        imageWidth,
        imageHeight,
        displacementRgb,
      );
      _writePpm(paths.magnitudePpm, imageWidth, imageHeight, magnitudeRgb);

      AgentDebugLog.write(
        location: 'face_warp_remap_debug.dart:dump',
        message: 'phase2_remap_debug',
        hypothesisId: 'P2R',
        runId: runId,
        phase: '2',
        data: {
          'tag': tag,
          'imageWidth': imageWidth,
          'imageHeight': imageHeight,
          'roiX0': roi.x0,
          'roiY0': roi.y0,
          'roiX1': roi.x1,
          'roiY1': roi.y1,
          'hitPixels': hitPixels,
          'missPixels': missPixels,
          'coverageRatio': coverageRatio,
          'maxDx': maxDx,
          'maxDy': maxDy,
          'maxMagnitude': maxMagnitude,
          'meanMagnitude': meanMagnitude,
          'p50Magnitude': _percentile(magnitudes, 0.50),
          'p95Magnitude': _percentile(magnitudes, 0.95),
          'p99Magnitude': _percentile(magnitudes, 0.99),
          'discontinuityX': discontinuities.discontinuityX,
          'discontinuityY': discontinuities.discontinuityY,
          'maxDiscontinuity': discontinuities.maxDiscontinuity,
          'p95Discontinuity': discontinuities.p95Discontinuity,
          'coveragePpm': paths.coveragePpm,
          'sourceCoordPpm': paths.sourceCoordPpm,
          'displacementPpm': paths.displacementPpm,
          'magnitudePpm': paths.magnitudePpm,
        },
      );

      return paths;
    } catch (_) {
      return null;
    }
  }

  /// Harness **isolado** — uma renderização + mapas. Não usar no pipeline do editor.
  static FaceWarpRemapDebugPaths? dumpFromPayloadHarness({
    required Uint8List rgba,
    required int width,
    required int height,
    required FaceMeshForwardPayload payload,
    required String tag,
    String runId = 'remap-debug-harness',
    DeformationSupportParams supportParams = const DeformationSupportParams(),
    String? outputDirectory,
  }) {
    if (!kDebugMode) {
      return null;
    }

    final renderResult = FaceWarpRenderer.renderFromPayload(
      rgba: rgba,
      width: width,
      height: height,
      payload: payload,
      runId: runId,
      supportParams: supportParams,
    );
    final coverage = renderResult.coverage;
    if (coverage == null) {
      return null;
    }

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
      params: supportParams,
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

    return dump(
      sourceMesh: mesh,
      deformedMesh: deformedMesh,
      imageWidth: width,
      imageHeight: height,
      spatialIndex: spatialIndex,
      coverage: coverage,
      tag: tag,
      runId: runId,
      outputDirectory: outputDirectory,
    );
  }

  static ({double srcX, double srcY})? _sourceCoordFromHit(
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

  static ({
    double discontinuityX,
    double discontinuityY,
    double maxDiscontinuity,
    double p95Discontinuity,
  }) _collectDiscontinuities({
    required Float32List dxField,
    required Float32List dyField,
    required Uint8List hitMask,
    required int width,
    required int height,
    required int x0,
    required int y0,
    required int x1,
    required int y1,
  }) {
    final samples = <double>[];
    var maxDiscX = 0.0;
    var maxDiscY = 0.0;

    void addSample(double value, {required bool horizontal}) {
      if (value.isNaN) {
        return;
      }
      samples.add(value);
      if (horizontal) {
        if (value > maxDiscX) {
          maxDiscX = value;
        }
      } else if (value > maxDiscY) {
        maxDiscY = value;
      }
    }

    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x < x1; x++) {
        final p0 = y * width + x;
        final p1 = y * width + x + 1;
        if (hitMask[p0] == 0 || hitMask[p1] == 0) {
          continue;
        }
        addSample((dxField[p1] - dxField[p0]).abs(), horizontal: true);
        addSample((dyField[p1] - dyField[p0]).abs(), horizontal: true);
      }
    }

    for (var y = y0; y < y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final p0 = y * width + x;
        final p1 = (y + 1) * width + x;
        if (hitMask[p0] == 0 || hitMask[p1] == 0) {
          continue;
        }
        addSample((dxField[p1] - dxField[p0]).abs(), horizontal: false);
        addSample((dyField[p1] - dyField[p0]).abs(), horizontal: false);
      }
    }

    samples.sort();
    final maxDisc = samples.isEmpty ? 0.0 : samples.last;
    return (
      discontinuityX: maxDiscX,
      discontinuityY: maxDiscY,
      maxDiscontinuity: maxDisc,
      p95Discontinuity: _percentile(samples, 0.95),
    );
  }

  static double _percentile(List<double> sorted, double p) {
    if (sorted.isEmpty) {
      return 0.0;
    }
    final idx = ((sorted.length - 1) * p).round().clamp(0, sorted.length - 1);
    return sorted[idx];
  }

  static void _writePpm(
    String path,
    int width,
    int height,
    Uint8List rgb,
  ) {
    final sb = StringBuffer('P6\n$width $height\n255\n');
    final bytes = Uint8List(sb.length + rgb.length);
    bytes.setAll(0, sb.toString().codeUnits);
    bytes.setAll(sb.length, rgb);
    File(path).writeAsBytesSync(bytes);
  }
}
