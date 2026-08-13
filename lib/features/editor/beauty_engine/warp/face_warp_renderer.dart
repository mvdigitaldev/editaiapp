import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../body_reshape/maps/influence_map.dart';
import '../debug/agent_debug_log.dart';
import '../filters/face/face_warp_utils.dart';
import '../mesh/tri_mesh_spatial_index.dart';
import '../models/tri_mesh.dart';
import '../segment/person_mask.dart';
import 'anatomy/constrained_vertex_field.dart';
import 'anatomy/vertex_role_map.dart';
import 'face_mesh_forward_warp.dart';
import 'face_warp_render_contract.dart';

/// Geometric Support — atenua magnitude do coreDelta (preserva direção).
abstract final class GeometricSupport {
  GeometricSupport._();

  /// `effectiveDelta(v) = coreDelta(v) × supportWeight(v)`
  static Float32List computeWeights({
    required TriMesh mesh,
    required ConstrainedVertexField coreField,
    required InfluenceMap influenceMap,
    required DeformationSupportParams params,
    required int imageWidth,
    required int imageHeight,
    PersonMask? personMask,
  }) {
    final count = FaceWarpFieldMetrics.safeVertexCount(
      field: coreField,
      mesh: mesh,
    );
    final weights = Float32List(count);
    final contour = orderedContourPoints(mesh);
    if (contour.length < 3) {
      weights.fillRange(0, count, 1.0);
      return weights;
    }

    final center = contourCentroid(contour);
    const coreInnerNorm = 0.58;
    final fadeEnd = 1.0 + params.supportWidthNorm * 4.5;
    final targets = Float32List(count);

    for (var i = 0; i < count; i++) {
      final pos = FaceWarpUtils.vertexAt(mesh, i);
      if (pos == null) {
        continue;
      }

      final nx = (pos.dx / imageWidth).clamp(0.0, 1.0);
      final ny = (pos.dy / imageHeight).clamp(0.0, 1.0);

      if (personMask != null && personMask.bytes.isNotEmpty) {
        if (personMask.sampleNormalized(nx, ny) < 0.08) {
          targets[i] = 0;
          continue;
        }
      }

      final influence = influenceMap.sampleNormalized(nx, ny);

      final theta = math.atan2(pos.dy - center.dy, pos.dx - center.dx);
      final distFromCenter = (pos - center).distance;
      final contourR = contourRadiusAt(contour, center, theta);
      if (contourR <= 1e-6) {
        targets[i] = 0;
        continue;
      }

      final radialNorm = distFromCenter / contourR;
      var weight = radialNorm <= coreInnerNorm
          ? 1.0
          : 1.0 -
              _smoothstep(
                coreInnerNorm,
                fadeEnd,
                radialNorm,
              ).clamp(0.0, 1.0);

      if (radialNorm > 0.85) {
        final outerT =
            ((radialNorm - 0.85) / 0.20).clamp(0.0, 1.0);
        weight *= math.pow(1.0 - outerT, 1.2).toDouble();
      }

      targets[i] = (weight * influence.clamp(0.0, 1.0)).clamp(0.0, 1.0);
    }

    final smoothed = _smoothMeshWeights(
      targets,
      mesh,
      count,
      passes: 1,
      blend: 0.38,
    );
    _clampExteriorWeights(
      smoothed,
      targets,
      mesh,
      count,
      imageWidth,
      imageHeight,
    );
    final continuous = _enforceEdgeContinuity(
      smoothed,
      mesh,
      count,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
    _clampExteriorWeights(
      continuous,
      targets,
      mesh,
      count,
      imageWidth,
      imageHeight,
    );
    return continuous;
  }

  static void _clampExteriorWeights(
    Float32List weights,
    Float32List targets,
    TriMesh mesh,
    int count,
    int imageWidth,
    int imageHeight,
  ) {
    for (var i = 0; i < count; i++) {
      final radial = radialNormAt(
        mesh: mesh,
        vertexIndex: i,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
      if (radial >= 0.95) {
        weights[i] = math.min(weights[i], targets[i]);
      }
    }
  }

  /// Limita saltos de supportWeight entre vértices adjacentes (Support→Zero contínuo).
  static Float32List _enforceEdgeContinuity(
    Float32List weights,
    TriMesh mesh,
    int count, {
    double maxJump = 0.54,
    int imageWidth = 1,
    int imageHeight = 1,
  }) {
    if (count <= 1 || mesh.indices.isEmpty) {
      return weights;
    }

    var current = Float32List.fromList(weights);
    for (var iter = 0; iter < 3; iter++) {
      final next = Float32List.fromList(current);
      final seen = <int>{};
      for (var t = 0; t < mesh.indices.length; t += 3) {
        final pairs = [
          (mesh.indices[t], mesh.indices[t + 1]),
          (mesh.indices[t + 1], mesh.indices[t + 2]),
          (mesh.indices[t + 2], mesh.indices[t]),
        ];
        for (final pair in pairs) {
          if (pair.$1 >= count || pair.$2 >= count) {
            continue;
          }
          final key = pair.$1 < pair.$2
              ? pair.$1 * count + pair.$2
              : pair.$2 * count + pair.$1;
          if (seen.contains(key)) {
            continue;
          }
          seen.add(key);

          final a = pair.$1;
          final b = pair.$2;
          final diff = next[a] - next[b];
          final absDiff = diff.abs();
          if (absDiff <= maxJump) {
            continue;
          }
          final shrink = absDiff - maxJump;
          final radialA = radialNormAt(
            mesh: mesh,
            vertexIndex: a,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
          );
          final radialB = radialNormAt(
            mesh: mesh,
            vertexIndex: b,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
          );
          if (radialA <= radialB) {
            next[a] -= shrink;
          } else {
            next[b] -= shrink;
          }
        }
      }
      current = next;
    }
    return current;
  }

  /// Suavização leve ao longo das arestas — evita saltos binários Support→Zero.
  static Float32List _smoothMeshWeights(
    Float32List weights,
    TriMesh mesh,
    int count, {
    required int passes,
    required double blend,
  }) {
    if (count <= 1 || mesh.indices.isEmpty || blend <= 0) {
      return weights;
    }

    final neighbors = List.generate(count, (_) => <int>{});
    for (var t = 0; t < mesh.indices.length; t += 3) {
      final i0 = mesh.indices[t];
      final i1 = mesh.indices[t + 1];
      final i2 = mesh.indices[t + 2];
      if (i0 >= count || i1 >= count || i2 >= count) {
        continue;
      }
      neighbors[i0].addAll([i1, i2]);
      neighbors[i1].addAll([i0, i2]);
      neighbors[i2].addAll([i0, i1]);
    }

    var current = Float32List.fromList(weights);
    for (var pass = 0; pass < passes; pass++) {
      final next = Float32List.fromList(current);
      for (var i = 0; i < count; i++) {
        final nbs = neighbors[i];
        if (nbs.isEmpty) {
          continue;
        }
        var sum = 0.0;
        for (final j in nbs) {
          sum += current[j];
        }
        final avg = sum / nbs.length;
        next[i] = current[i] * (1.0 - blend) + avg * blend;
      }
      current = next;
    }
    return current;
  }

  static double _smoothstep(double edge0, double edge1, double x) {
    if (edge1 <= edge0) {
      return x >= edge1 ? 1.0 : 0.0;
    }
    final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
  }

  static List<Offset> orderedContourPoints(TriMesh mesh) {
    final points = <Offset>[];
    for (final index in VertexRoleMap.skullContour) {
      final p = FaceWarpUtils.vertexAt(mesh, index);
      if (p != null) {
        points.add(p);
      }
    }
    if (points.length < 3) {
      return points;
    }
    final cx =
        points.map((p) => p.dx).reduce((a, b) => a + b) / points.length;
    final cy =
        points.map((p) => p.dy).reduce((a, b) => a + b) / points.length;
    points.sort((a, b) {
      final aa = math.atan2(a.dy - cy, a.dx - cx);
      final bb = math.atan2(b.dy - cy, b.dx - cx);
      return aa.compareTo(bb);
    });
    return points;
  }

  static Offset contourCentroid(List<Offset> contour) {
    var sx = 0.0;
    var sy = 0.0;
    for (final p in contour) {
      sx += p.dx;
      sy += p.dy;
    }
    return Offset(sx / contour.length, sy / contour.length);
  }

  static double contourRadiusAt(
    List<Offset> contour,
    Offset center,
    double theta,
  ) {
    var maxR = 0.0;
    for (final p in contour) {
      final pt = math.atan2(p.dy - center.dy, p.dx - center.dx);
      if ((pt - theta).abs() < 0.35 ||
          (pt - theta).abs() > math.pi * 2 - 0.35) {
        maxR = math.max(maxR, (p - center).distance);
      }
    }
    if (maxR <= 1e-6) {
      for (final p in contour) {
        maxR = math.max(maxR, (p - center).distance);
      }
    }
    return maxR;
  }

  /// Distância radial normalizada ao contorno (1.0 ≈ borda do oval).
  static double radialNormAt({
    required TriMesh mesh,
    required int vertexIndex,
    required int imageWidth,
    required int imageHeight,
  }) {
    final pos = FaceWarpUtils.vertexAt(mesh, vertexIndex);
    if (pos == null) {
      return 0;
    }
    final contour = orderedContourPoints(mesh);
    if (contour.length < 3) {
      return 0;
    }
    final center = contourCentroid(contour);
    final theta = math.atan2(pos.dy - center.dy, pos.dx - center.dx);
    final contourR = contourRadiusAt(contour, center, theta);
    if (contourR <= 1e-6) {
      return 0;
    }
    return (pos - center).distance / contourR;
  }
}

/// Renderer V3 Fase 2 — Support + backward piecewise (sem boundary/inpaint).
abstract final class FaceWarpRenderer {
  FaceWarpRenderer._();

  static FaceWarpRenderResult render({
    required FaceWarpRenderRequest request,
    String runId = 'mesh-backward-preview',
    bool enableDebugDump = kDebugMode,
  }) {
    final width = request.imageSize.width.round();
    final height = request.imageSize.height.round();
    final rgba = request.sourceRgba;
    final mesh = request.sourceMesh;
    final vf = request.vertexField;

    if (vf.maxDisplacementMagnitude() <= 0.05 || rgba.isEmpty) {
      return FaceWarpRenderResult(
        rgba: rgba,
        metrics: const FaceWarpBoundaryMetrics(
          requestedDisplacement: 0,
          effectiveDisplacement: 0,
        ),
      );
    }

    final vertexCount = FaceWarpFieldMetrics.safeVertexCount(
      field: vf,
      mesh: mesh,
    );

    final supportWeights = GeometricSupport.computeWeights(
      mesh: mesh,
      coreField: vf,
      influenceMap: request.influenceMap,
      params: request.supportParams,
      imageWidth: width,
      imageHeight: height,
      personMask: request.personMask,
    );

    final fieldMetrics = FaceWarpFieldMetrics.computeFieldMetrics(
      coreField: vf,
      mesh: mesh,
      supportWeights: supportWeights,
      rigidIndices: VertexRoleMap.eyeLeft,
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

    var minX = width;
    var minY = height;
    var maxX = 0;
    var maxY = 0;
    for (var i = 0; i < deformedVerts.length; i += 2) {
      final x = deformedVerts[i];
      final y = deformedVerts[i + 1];
      minX = math.min(minX, x.floor());
      minY = math.min(minY, y.floor());
      maxX = math.max(maxX, x.ceil());
      maxY = math.max(maxY, y.ceil());
    }
    const margin = 3;
    final x0 = (minX - margin).clamp(0, width - 1);
    final y0 = (minY - margin).clamp(0, height - 1);
    final x1 = (maxX + margin).clamp(0, width - 1);
    final y1 = (maxY + margin).clamp(0, height - 1);

    final output = Uint8List.fromList(rgba);
    final coverage = Float32List(width * height);
    final sourceHitBuckets = Uint8List(
      ((width + 15) ~/ 16) * ((height + 15) ~/ 16),
    );

    var meshHitPx = 0;
    final roiPixels = (x1 - x0 + 1) * (y1 - y0 + 1);

    final rowTris = List<int?>.filled(x1 - x0 + 1, null);
    final rowSrcX = List<double?>.filled(x1 - x0 + 1, null);
    final rowSrcY = List<double?>.filled(x1 - x0 + 1, null);
    final topSrcX = List<double?>.filled(x1 - x0 + 1, null);
    final topSrcY = List<double?>.filled(x1 - x0 + 1, null);

    for (var y = y0; y <= y1; y++) {
      final py = y + 0.5;
      int? rowTri;
      for (var x = x0; x <= x1; x++) {
        final px = x + 0.5;
        final col = x - x0;
        final tri = spatialIndex.locateTriangleIndex(
          px,
          py,
          coherenceTriangle: rowTri,
          verticalCoherenceTriangle: rowTris[col],
          sourceMesh: mesh,
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

        final s0 = FaceWarpUtils.vertexAt(mesh, hit.i0);
        final s1 = FaceWarpUtils.vertexAt(mesh, hit.i1);
        final s2 = FaceWarpUtils.vertexAt(mesh, hit.i2);
        if (s0 == null || s1 == null || s2 == null) {
          continue;
        }

        final srcX =
            hit.w0 * s0.dx + hit.w1 * s1.dx + hit.w2 * s2.dx;
        final srcY =
            hit.w0 * s0.dy + hit.w1 * s1.dy + hit.w2 * s2.dy;
        rowSrcX[col] = srcX;
        rowSrcY[col] = srcY;
        final rgb = _sampleBilinear(rgba, width, height, srcX, srcY);

        final p = y * width + x;
        final o = p * 4;
        output[o] = rgb[0];
        output[o + 1] = rgb[1];
        output[o + 2] = rgb[2];
        coverage[p] = 1.0;
        meshHitPx++;

        final bx = (srcX / 16).floor().clamp(0, (width + 15) ~/ 16 - 1);
        final by = (srcY / 16).floor().clamp(0, (height + 15) ~/ 16 - 1);
        sourceHitBuckets[by * ((width + 15) ~/ 16) + bx] = 1;
      }
      for (var col = 0; col < rowTris.length; col++) {
        topSrcX[col] = rowSrcX[col];
        topSrcY[col] = rowSrcY[col];
      }
    }

    final destinationCoverage =
        roiPixels > 0 ? meshHitPx / roiPixels : 0.0;
    final uncoveredRatio =
        roiPixels > 0 ? 1.0 - destinationCoverage : 0.0;
    var sourceBucketsHit = 0;
    for (var i = 0; i < sourceHitBuckets.length; i++) {
      if (sourceHitBuckets[i] == 1) {
        sourceBucketsHit++;
      }
    }
    final sourceCoverage = sourceHitBuckets.isEmpty
        ? 0.0
        : sourceBucketsHit / sourceHitBuckets.length;

    final metrics = FaceWarpBoundaryMetrics(
      requestedDisplacement: fieldMetrics.requestedDisplacement,
      effectiveDisplacement: fieldMetrics.effectiveDisplacement,
      displacementRetentionRatio: fieldMetrics.displacementRetentionRatio,
      displacementContinuityError: fieldMetrics.displacementContinuityError,
      sourceCoverage: sourceCoverage,
      destinationCoverage: destinationCoverage,
      uncoveredRatio: uncoveredRatio,
      coverageRatio: destinationCoverage,
      maxDisplacementPx: fieldMetrics.maxDisplacementPx,
      maxRigidDisplacementPx: fieldMetrics.maxRigidDisplacementPx,
    );

    if (enableDebugDump) {
      FaceWarpFieldDebug.dumpField(
        mesh: mesh,
        coreField: vf,
        supportWeights: supportWeights,
        imageWidth: width,
        imageHeight: height,
        runId: runId,
      );
    }

    AgentDebugLog.writePhase2Metrics(
      location: 'face_warp_renderer.dart:render',
      runId: runId,
      metrics: metrics,
      landmarkCount: vf.landmarkCount,
      meshVertexCount: mesh.vertices.length ~/ 2,
      meshHitPx: meshHitPx,
    );

    return FaceWarpRenderResult(
      rgba: output,
      coverage: coverage,
      metrics: metrics,
    );
  }

  static FaceWarpRenderResult renderFromPayload({
    required Uint8List rgba,
    required int width,
    required int height,
    required FaceMeshForwardPayload payload,
    String runId = 'mesh-backward-preview',
    DeformationSupportParams supportParams = const DeformationSupportParams(),
  }) {
    return render(
      request: FaceWarpRenderRequest(
        sourceRgba: rgba,
        imageSize: Size(width.toDouble(), height.toDouble()),
        sourceMesh: payload.mesh,
        vertexField: payload.vertexField,
        influenceMap: payload.influenceMap,
        personMask: payload.personMask,
        parameters: const {'face_slim': 1.0},
        mode: FaceWarpRenderMode.preview,
        supportParams: supportParams,
      ),
      runId: runId,
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
}

/// Ferramenta de desenvolvimento — heatmap de supportWeight / |coreDelta|.
abstract final class FaceWarpFieldDebug {
  FaceWarpFieldDebug._();

  static const _dumpPath =
      '/Users/leonardo/Documents/Projetos/editaiapp/.cursor/debug-face-warp-field.ppm';

  static void dumpField({
    required TriMesh mesh,
    required ConstrainedVertexField coreField,
    required Float32List supportWeights,
    required int imageWidth,
    required int imageHeight,
    required String runId,
  }) {
    if (!kDebugMode) {
      return;
    }
    try {
      final count = FaceWarpFieldMetrics.safeVertexCount(
        field: coreField,
        mesh: mesh,
      );
      final samples = <Map<String, dynamic>>[];
      for (var i = 0; i < count; i++) {
        final pos = FaceWarpUtils.vertexAt(mesh, i);
        if (pos == null) {
          continue;
        }
        final core = coreField.displacementAt(i);
        final w = supportWeights[i];
        final eff = FaceWarpFieldMetrics.effectiveDelta(core, w);
        if (core.distance < 0.01 && w >= 0.99) {
          continue;
        }
        samples.add({
          'i': i,
          'x': pos.dx,
          'y': pos.dy,
          'coreMag': core.distance,
          'supportWeight': w,
          'effectiveMag': eff.distance,
        });
      }

      AgentDebugLog.write(
        location: 'face_warp_field_debug.dart:dumpField',
        message: 'phase2_field_debug',
        hypothesisId: 'P2D',
        runId: runId,
        phase: '2',
        data: {
          'sampleCount': samples.length,
          'samples': samples.take(48).toList(),
        },
      );

      _writeWeightHeatmapPpm(
        mesh: mesh,
        supportWeights: supportWeights,
        width: imageWidth,
        height: imageHeight,
      );
    } catch (_) {}
  }

  static void _writeWeightHeatmapPpm({
    required TriMesh mesh,
    required Float32List supportWeights,
    required int width,
    required int height,
  }) {
    final rgb = Uint8List(width * height * 3);
    final count = math.min(supportWeights.length, mesh.vertices.length ~/ 2);

    for (var i = 0; i < count; i++) {
      final pos = FaceWarpUtils.vertexAt(mesh, i);
      if (pos == null) {
        continue;
      }
      final x = pos.dx.round().clamp(0, width - 1);
      final y = pos.dy.round().clamp(0, height - 1);
      final w = supportWeights[i].clamp(0.0, 1.0);
      final o = (y * width + x) * 3;
      rgb[o] = (w * 255).round();
      rgb[o + 1] = ((1.0 - w) * 128).round();
      rgb[o + 2] = 64;
    }

    final sb = StringBuffer('P6\n$width $height\n255\n');
    final bytes = Uint8List(sb.length + rgb.length);
    bytes.setAll(0, sb.toString().codeUnits);
    bytes.setAll(sb.length, rgb);
    File(_dumpPath).writeAsBytesSync(bytes);
  }
}
