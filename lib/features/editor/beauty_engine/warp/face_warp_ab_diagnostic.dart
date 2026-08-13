import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../body_reshape/maps/influence_map.dart';
import '../debug/agent_debug_log.dart';
import '../filters/face/face_warp_utils.dart';
import '../mesh/tri_mesh_spatial_index.dart';
import '../models/tri_mesh.dart';
import '../segment/person_mask.dart';
import 'face_mesh_forward_warp.dart';
import 'face_warp_render_contract.dart';
import 'face_warp_renderer.dart';

/// Resultado do experimento A/B/C — isolamento backward vs pós-processamento.
class FaceWarpAbDiagnosticResult {
  const FaceWarpAbDiagnosticResult({
    required this.experimentA,
    required this.experimentB,
    required this.experimentC,
    required this.rawBackwardPpm,
    required this.rawBackwardPng,
    required this.currentPipelinePpm,
    required this.currentPipelinePng,
    required this.postprocessDiffPpm,
    required this.postprocessDiffPng,
    required this.verdict,
  });

  final Map<String, dynamic> experimentA;
  final Map<String, dynamic> experimentB;
  final Map<String, dynamic> experimentC;
  final String rawBackwardPpm;
  final String rawBackwardPng;
  final String currentPipelinePpm;
  final String currentPipelinePng;
  final String postprocessDiffPpm;
  final String postprocessDiffPng;
  final String verdict;
}

/// Diagnóstico A/B temporário — backward raw vs pipeline atual vs diff.
///
/// Não altera algoritmos de produção. Somente [kDebugMode].
abstract final class FaceWarpAbDiagnostic {
  FaceWarpAbDiagnostic._();

  static const _defaultOutputDir =
      '/Users/leonardo/Documents/Projetos/editaiapp/.cursor';

  static Future<FaceWarpAbDiagnosticResult?> run({
    required Uint8List sourceRgba,
    required int width,
    required int height,
    required FaceMeshForwardPayload payload,
    String runId = 'ab-diagnostic-real-90',
    String? outputDirectory,
  }) async {
    if (!kDebugMode || sourceRgba.isEmpty) {
      return null;
    }

    try {
      final outDir = outputDirectory ?? _defaultOutputDir;
      Directory(outDir).createSync(recursive: true);

      final renderResult = FaceWarpRenderer.renderFromPayload(
        rgba: sourceRgba,
        width: width,
        height: height,
        payload: payload,
        runId: '$runId-raw',
      );
      final coverage =
          renderResult.coverage ?? Float32List(width * height);
      final rawBackward = Uint8List.fromList(renderResult.rgba);

      final backwardField = _analyzeBackwardField(
        sourceMesh: payload.mesh,
        payload: payload,
        width: width,
        height: height,
        coverage: coverage,
      );

      final expA = {
        'meshHitPx': coverage.where((v) => v > 0.5).length,
        'missPixels': backwardField.missPixels,
        'coverageRatio': backwardField.coverageRatio,
        'changedPixels': _countChangedVsSource(
          sourceRgba,
          rawBackward,
          threshold: 0,
        ),
        'maxDiscontinuity': backwardField.maxDiscontinuity,
        'p95Discontinuity': backwardField.p95Discontinuity,
        'outputRgbMaxHorizJump': _rgbHorizontalDiscontinuity(
          rawBackward,
          width,
          height,
        ).max,
        'outputRgbP95HorizJump': _rgbHorizontalDiscontinuity(
          rawBackward,
          width,
          height,
        ).p95,
      };

      final rawPpm = '$outDir/debug-face-slim-raw-backward.ppm';
      final rawPng = '$outDir/debug-face-slim-raw-backward.png';
      _writeRgbaPpm(rawPpm, sourceRgba, rawBackward, width, height);
      _writeRgbaPng(rawPng, rawBackward, width, height);

      final pipeline = FaceMeshForwardWarp.apply(
        rgba: sourceRgba,
        width: width,
        height: height,
        payload: payload,
        runId: '$runId-pipeline',
      );

      final pipelineLog = _readLastMeshBackwardWarpLog();
      final expB = {
        'holeFillPx': pipelineLog?['holeFillPx'],
        'seamImputePx': pipelineLog?['seamImputePx'],
        'bgFillPx': pipelineLog?['bgFillPx'],
        'lateralGhostPx': pipelineLog?['lateralGhostPx'],
        'meshHitPx': pipelineLog?['meshHitPx'],
        'changedPixels': _countChangedVsSource(
          sourceRgba,
          pipeline,
          threshold: 0,
        ),
        'maxDiscontinuity': backwardField.maxDiscontinuity,
        'p95Discontinuity': backwardField.p95Discontinuity,
        'outputRgbMaxHorizJump': _rgbHorizontalDiscontinuity(
          pipeline,
          width,
          height,
        ).max,
        'outputRgbP95HorizJump': _rgbHorizontalDiscontinuity(
          pipeline,
          width,
          height,
        ).p95,
      };

      final pipePpm = '$outDir/debug-face-slim-current-pipeline.ppm';
      final pipePng = '$outDir/debug-face-slim-current-pipeline.png';
      _writeRgbaPpm(pipePpm, sourceRgba, pipeline, width, height);
      _writeRgbaPng(pipePng, pipeline, width, height);

      final diffStats = _buildPostprocessDiff(
        sourceRgba: sourceRgba,
        rawBackward: rawBackward,
        pipeline: pipeline,
        width: width,
        height: height,
        influence: payload.influenceMap,
        personMask: payload.personMask,
      );

      final diffPpm = '$outDir/debug-face-slim-postprocess-diff.ppm';
      final diffPng = '$outDir/debug-face-slim-postprocess-diff.png';
      _writeRgbPpm(diffPpm, diffStats.diffRgb, width, height);
      File(diffPng).writeAsBytesSync(
        img.encodePng(
          _rgbBytesToImage(diffStats.diffRgb, width, height),
        ),
      );

      final expC = diffStats.metrics;
      final verdict = _computeVerdict(
        experimentA: expA,
        experimentC: expC,
      );

      AgentDebugLog.write(
        location: 'face_warp_ab_diagnostic.dart:run',
        message: 'phase2_ab_diagnostic',
        hypothesisId: 'P2AB',
        runId: runId,
        phase: '2',
        data: {
          'experimentA': expA,
          'experimentB': expB,
          'experimentC': expC,
          'verdict': verdict,
          'rawBackwardPpm': rawPpm,
          'rawBackwardPng': rawPng,
          'currentPipelinePpm': pipePpm,
          'currentPipelinePng': pipePng,
          'postprocessDiffPpm': diffPpm,
          'postprocessDiffPng': diffPng,
        },
      );

      return FaceWarpAbDiagnosticResult(
        experimentA: expA,
        experimentB: expB,
        experimentC: expC,
        rawBackwardPpm: rawPpm,
        rawBackwardPng: rawPng,
        currentPipelinePpm: pipePpm,
        currentPipelinePng: pipePng,
        postprocessDiffPpm: diffPpm,
        postprocessDiffPng: diffPng,
        verdict: verdict,
      );
    } catch (_) {
      return null;
    }
  }

  static String _computeVerdict({
    required Map<String, dynamic> experimentA,
    required Map<String, dynamic> experimentC,
  }) {
    final rawRgbJump = experimentA['outputRgbMaxHorizJump'] as num? ?? 0;
    final postChanged = experimentC['totalChangedPixels'] as int? ?? 0;
    final cheekPct = experimentC['changedInCheeksPct'] as num? ?? 0;
    final postGt10 = experimentC['changedPixelsGt10'] as int? ?? 0;

    if (rawRgbJump >= 40 && postChanged < 500) {
      return 'BACKWARD_REMAP';
    }
    if (postChanged > 2000 && cheekPct > 0.45) {
      return 'POST_PROCESSING';
    }
    if (rawRgbJump >= 25 && postGt10 < rawRgbJump * 0.3) {
      return 'BACKWARD_REMAP';
    }
    if (postChanged > 500) {
      return 'POST_PROCESSING';
    }
    return 'MIXED_OR_INCONCLUSIVE';
  }

  static ({
    int missPixels,
    double coverageRatio,
    double maxDiscontinuity,
    double p95Discontinuity,
  }) _analyzeBackwardField({
    required TriMesh sourceMesh,
    required FaceMeshForwardPayload payload,
    required int width,
    required int height,
    required Float32List coverage,
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
    final pixelCount = width * height;

    final dxField = Float32List(pixelCount)..fillRange(0, pixelCount, double.nan);
    final dyField = Float32List(pixelCount)..fillRange(0, pixelCount, double.nan);
    final hitMask = Uint8List(pixelCount);

    var hitPixels = 0;
    var missPixels = 0;

    for (var y = roi.y0; y <= roi.y1; y++) {
      final destY = y + 0.5;
      for (var x = roi.x0; x <= roi.x1; x++) {
        final destX = x + 0.5;
        final p = y * width + x;
        if (coverage[p] <= 0.5) {
          missPixels++;
          continue;
        }

        final hit = spatialIndex.locate(destX, destY);
        if (hit == null) {
          missPixels++;
          continue;
        }

        final s0 = FaceWarpUtils.vertexAt(sourceMesh, hit.i0);
        final s1 = FaceWarpUtils.vertexAt(sourceMesh, hit.i1);
        final s2 = FaceWarpUtils.vertexAt(sourceMesh, hit.i2);
        if (s0 == null || s1 == null || s2 == null) {
          missPixels++;
          continue;
        }

        final srcX =
            hit.w0 * s0.dx + hit.w1 * s1.dx + hit.w2 * s2.dx;
        final srcY =
            hit.w0 * s0.dy + hit.w1 * s1.dy + hit.w2 * s2.dy;
        dxField[p] = srcX - destX;
        dyField[p] = srcY - destY;
        hitMask[p] = 1;
        hitPixels++;
      }
    }

    final roiPixels = (roi.x1 - roi.x0 + 1) * (roi.y1 - roi.y0 + 1);
    final disc = _collectDiscontinuities(
      dxField: dxField,
      dyField: dyField,
      hitMask: hitMask,
      width: width,
      height: height,
      x0: roi.x0,
      y0: roi.y0,
      x1: roi.x1,
      y1: roi.y1,
    );

    return (
      missPixels: missPixels,
      coverageRatio: roiPixels > 0 ? hitPixels / roiPixels : 0.0,
      maxDiscontinuity: disc.maxDiscontinuity,
      p95Discontinuity: disc.p95Discontinuity,
    );
  }

  static ({
    Uint8List diffRgb,
    Map<String, dynamic> metrics,
  }) _buildPostprocessDiff({
    required Uint8List sourceRgba,
    required Uint8List rawBackward,
    required Uint8List pipeline,
    required int width,
    required int height,
    required InfluenceMap influence,
    PersonMask? personMask,
  }) {
    final pixelCount = width * height;
    final diffRgb = Uint8List(pixelCount * 3);
    final centerX = width * 0.5;

    var totalChanged = 0;
    var gt2 = 0;
    var gt5 = 0;
    var gt10 = 0;
    var changedInCheeks = 0;
    var changedOutsideFace = 0;
    var changedInFace = 0;
    int? bboxMinX;
    int? bboxMinY;
    int? bboxMaxX;
    int? bboxMaxY;

    for (var p = 0; p < pixelCount; p++) {
      final o4 = p * 4;
      final dr = (rawBackward[o4] - pipeline[o4]).abs();
      final dg = (rawBackward[o4 + 1] - pipeline[o4 + 1]).abs();
      final db = (rawBackward[o4 + 2] - pipeline[o4 + 2]).abs();
      final maxDiff = math.max(dr, math.max(dg, db));

      final o3 = p * 3;
      if (maxDiff <= 0) {
        continue;
      }

      final heat = (maxDiff.clamp(0, 255)).toInt();
      diffRgb[o3] = heat;
      diffRgb[o3 + 1] = heat ~/ 2;
      diffRgb[o3 + 2] = 0;

      totalChanged++;
      if (maxDiff >= 2) {
        gt2++;
      }
      if (maxDiff >= 5) {
        gt5++;
      }
      if (maxDiff >= 10) {
        gt10++;
      }

      final x = p % width;
      final y = p ~/ width;
      bboxMinX = bboxMinX == null ? x : math.min(bboxMinX, x);
      bboxMinY = bboxMinY == null ? y : math.min(bboxMinY, y);
      bboxMaxX = bboxMaxX == null ? x : math.max(bboxMaxX, x);
      bboxMaxY = bboxMaxY == null ? y : math.max(bboxMaxY, y);

      final nx = x / width;
      final ny = y / height;
      final inf = influence.sampleNormalized(nx, ny);
      final lateral = (x - centerX).abs() / (width * 0.5);
      final isCheek = inf >= 0.05 &&
          lateral >= 0.35 &&
          ny >= 0.20 &&
          ny <= 0.68;
      final person = personMask != null && personMask.bytes.isNotEmpty
          ? personMask.sampleNormalized(nx, ny)
          : 1.0;
      final inFace = inf >= 0.12 && person >= 0.22;

      if (isCheek) {
        changedInCheeks++;
      }
      if (inFace) {
        changedInFace++;
      } else {
        changedOutsideFace++;
      }
    }

    return (
      diffRgb: diffRgb,
      metrics: {
        'totalChangedPixels': totalChanged,
        'changedPixelsGt2': gt2,
        'changedPixelsGt5': gt5,
        'changedPixelsGt10': gt10,
        'changedBBoxMinX': bboxMinX,
        'changedBBoxMinY': bboxMinY,
        'changedBBoxMaxX': bboxMaxX,
        'changedBBoxMaxY': bboxMaxY,
        'changedInCheeks': changedInCheeks,
        'changedInFace': changedInFace,
        'changedOutsideFace': changedOutsideFace,
        'changedInCheeksPct':
            totalChanged > 0 ? changedInCheeks / totalChanged : 0.0,
        'changedOutsideFacePct':
            totalChanged > 0 ? changedOutsideFace / totalChanged : 0.0,
      },
    );
  }

  static int _countChangedVsSource(
    Uint8List source,
    Uint8List output, {
    required int threshold,
  }) {
    var count = 0;
    for (var i = 0; i < source.length; i += 4) {
      final dr = (source[i] - output[i]).abs();
      final dg = (source[i + 1] - output[i + 1]).abs();
      final db = (source[i + 2] - output[i + 2]).abs();
      if (math.max(dr, math.max(dg, db)) > threshold) {
        count++;
      }
    }
    return count;
  }

  static ({double max, double p95}) _rgbHorizontalDiscontinuity(
    Uint8List rgba,
    int width,
    int height,
  ) {
    final samples = <double>[];
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width - 1; x++) {
        final p0 = (y * width + x) * 4;
        final p1 = p0 + 4;
        final dr = (rgba[p0] - rgba[p1]).abs();
        final dg = (rgba[p0 + 1] - rgba[p1 + 1]).abs();
        final db = (rgba[p0 + 2] - rgba[p1 + 2]).abs();
        samples.add(math.max(dr, math.max(dg, db)).toDouble());
      }
    }
    samples.sort();
    return (
      max: samples.isEmpty ? 0.0 : samples.last,
      p95: _percentile(samples, 0.95),
    );
  }

  static Map<String, dynamic>? _readLastMeshBackwardWarpLog() {
    try {
      const path =
          '/Users/leonardo/Documents/Projetos/editaiapp/.cursor/debug-13c8af.log';
      final file = File(path);
      if (!file.existsSync()) {
        return null;
      }
      Map<String, dynamic>? last;
      for (final line in file.readAsLinesSync()) {
        if (line.isEmpty) {
          continue;
        }
        final obj = jsonDecode(line) as Map<String, dynamic>;
        if (obj['message'] == 'mesh_backward_warp') {
          last = obj['data'] as Map<String, dynamic>?;
        }
      }
      return last;
    } catch (_) {
      return null;
    }
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
    return (
      discontinuityX: maxDiscX,
      discontinuityY: maxDiscY,
      maxDiscontinuity: samples.isEmpty ? 0.0 : samples.last,
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

  static void _writeRgbaPpm(
    String path,
    Uint8List source,
    Uint8List rgba,
    int width,
    int height,
  ) {
    _writeRgbPpm(path, _rgbaToRgb(rgba), width, height);
  }

  static void _writeRgbaPng(String path, Uint8List rgba, int width, int height) {
    final image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    File(path).writeAsBytesSync(img.encodePng(image));
  }

  static void _writeRgbPpm(
    String path,
    Uint8List rgb,
    int width,
    int height,
  ) {
    final sb = StringBuffer('P6\n$width $height\n255\n');
    final bytes = Uint8List(sb.length + rgb.length);
    bytes.setAll(0, sb.toString().codeUnits);
    bytes.setAll(sb.length, rgb);
    File(path).writeAsBytesSync(bytes);
  }

  static Uint8List _rgbaToRgb(Uint8List rgba) {
    final rgb = Uint8List(rgba.length ~/ 4 * 3);
    var o = 0;
    for (var i = 0; i < rgba.length; i += 4) {
      rgb[o++] = rgba[i];
      rgb[o++] = rgba[i + 1];
      rgb[o++] = rgba[i + 2];
    }
    return rgb;
  }

  static img.Image _rgbBytesToImage(Uint8List rgb, int width, int height) {
    final image = img.Image(width: width, height: height);
    var o = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.setPixelRgb(x, y, rgb[o], rgb[o + 1], rgb[o + 2]);
        o += 3;
      }
    }
    return image;
  }
}
