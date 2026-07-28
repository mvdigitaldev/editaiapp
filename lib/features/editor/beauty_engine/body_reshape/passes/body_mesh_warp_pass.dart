import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../models/mesh_region.dart';
import '../../models/warp_field.dart';
import '../../warp/models/control_point.dart';
import '../deformation/body_mesh_deformer.dart';
import '../mesh/adaptive_body_mesh.dart';
import '../mesh/mesh_optimizer.dart';
import 'body_reshape_pass.dart';
import 'pass_profiler.dart';

/// Rasteriza deslocamentos de malha adaptativa em um [WarpField] de grade.
///
/// Não usa control points MLS — amostra barycentric por triângulo com hash espacial.
class BodyMeshWarpPass implements BodyReshapePass {
  const BodyMeshWarpPass({
    this.deformer = const BodyMeshDeformer(),
    this.gridWidth = 64,
    this.gridHeight = 64,
    this.minDisplacementPx = 0.05,
  });

  final BodyMeshDeformer deformer;
  final int gridWidth;
  final int gridHeight;
  final double minDisplacementPx;

  @override
  String get id => 'body_mesh_warp';

  @override
  bool isEnabled(BodyMultiPassConfig config) => config.bodyMeshWarp;

  @override
  WarpField run(BodyPassContext context) {
    final mesh = context.sourceMesh;
    final assets = context.assets;
    final plan = context.plan;
    if (mesh == null || assets == null || plan == null || plan.isIdentity) {
      context.field ??= WarpField.identity(
        imageSize: context.imageSize,
        region: context.region,
      );
      return context.requireField;
    }

    final optimized = deformer.deform(mesh: mesh, assets: assets, plan: plan);
    context.optimizedMesh = optimized.mesh;
    context.vertexDisplacements = optimized.displacements;
    context.controlPoints = controlPointsFromDisplacements(
      source: mesh,
      displacements: optimized.displacements,
      minDisplacementPx: minDisplacementPx,
    );

    final field = rasterize(
      source: mesh,
      displacements: optimized.displacements,
      imageSize: context.imageSize,
      region: context.region,
      intensity: plan.maxIntensity,
      gridWidth: gridWidth,
      gridHeight: gridHeight,
    );
    context.field = field;
    context.intermediateBuffers['mesh_disp'] =
        Float32List.fromList(optimized.displacements.deltas);
    return field;
  }

  /// Converte vértices com deslocamento significativo em CPs esparsos (LocalMls).
  static List<ControlPoint> controlPointsFromDisplacements({
    required AdaptiveBodyMesh source,
    required VertexDisplacementField displacements,
    double minDisplacementPx = 0.05,
    int maxPoints = 256,
  }) {
    final scored = <({int index, double mag})>[];
    for (var i = 0; i < source.vertexCount; i++) {
      final mag = displacements.magnitudeAt(i);
      if (mag >= minDisplacementPx) {
        scored.add((index: i, mag: mag));
      }
    }
    scored.sort((a, b) => b.mag.compareTo(a.mag));
    final take = math.min(maxPoints, scored.length);
    final points = <ControlPoint>[];
    for (var i = 0; i < take; i++) {
      final idx = scored[i].index;
      final sx = source.vertices[idx * 2];
      final sy = source.vertices[idx * 2 + 1];
      final d = displacements.deltaAt(idx);
      points.add(
        ControlPoint(
          source: Offset(sx, sy),
          target: Offset(sx + d.dx, sy + d.dy),
        ),
      );
    }
    return points;
  }

  /// Amostra barycentric do campo de vértice na grade regular.
  static WarpField rasterize({
    required AdaptiveBodyMesh source,
    required VertexDisplacementField displacements,
    required Size imageSize,
    required MeshRegion region,
    required double intensity,
    int gridWidth = 64,
    int gridHeight = 64,
  }) {
    if (displacements.isIdentity || source.triangleCount == 0) {
      return WarpField.identity(imageSize: imageSize, region: region);
    }

    final cellCount = gridWidth * gridHeight;
    final disp = Float32List(cellCount * 2);
    final mask = Float32List(cellCount);
    final index = TriangleSpatialIndex(source);
    var active = 0;

    for (var gy = 0; gy < gridHeight; gy++) {
      for (var gx = 0; gx < gridWidth; gx++) {
        final px = (gx / (gridWidth - 1)) * imageSize.width;
        final py = (gy / (gridHeight - 1)) * imageSize.height;
        final hit = index.locate(px, py);
        if (hit == null) {
          continue;
        }
        final d0 = displacements.deltaAt(hit.i0);
        final d1 = displacements.deltaAt(hit.i1);
        final d2 = displacements.deltaAt(hit.i2);
        final dx = d0.dx * hit.w0 + d1.dx * hit.w1 + d2.dx * hit.w2;
        final dy = d0.dy * hit.w0 + d1.dy * hit.w1 + d2.dy * hit.w2;
        final idx = gy * gridWidth + gx;
        disp[idx * 2] = dx;
        disp[idx * 2 + 1] = dy;
        final mag = math.sqrt(dx * dx + dy * dy);
        mask[idx] = mag <= 1e-6 ? 0.0 : 1.0;
        if (mask[idx] > 0) {
          active++;
        }
      }
    }

    return WarpField(
      gridWidth: gridWidth,
      gridHeight: gridHeight,
      displacement: disp,
      mask: mask,
      imageSize: imageSize,
      region: region,
      controlPoints: const [],
      intensity: intensity.clamp(0.0, 1.0),
      passId: 'body_mesh_warp',
      activeCellCount: active,
    );
  }
}

class BarycentricHit {
  const BarycentricHit({
    required this.i0,
    required this.i1,
    required this.i2,
    required this.w0,
    required this.w1,
    required this.w2,
  });

  final int i0;
  final int i1;
  final int i2;
  final double w0;
  final double w1;
  final double w2;
}

/// Índice espacial de triângulos para localização O(k) por consulta.
class TriangleSpatialIndex {
  TriangleSpatialIndex(AdaptiveBodyMesh mesh) : _mesh = mesh {
    final cell = math.max(
      8.0,
      math.min(mesh.imageSize.width, mesh.imageSize.height) / 32,
    );
    _cellSize = cell;
    for (var t = 0; t < mesh.triangleCount; t++) {
      final i0 = mesh.indices[t * 3];
      final i1 = mesh.indices[t * 3 + 1];
      final i2 = mesh.indices[t * 3 + 2];
      final ax = mesh.vertices[i0 * 2];
      final ay = mesh.vertices[i0 * 2 + 1];
      final bx = mesh.vertices[i1 * 2];
      final by = mesh.vertices[i1 * 2 + 1];
      final cx = mesh.vertices[i2 * 2];
      final cy = mesh.vertices[i2 * 2 + 1];
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

  final AdaptiveBodyMesh _mesh;
  late final double _cellSize;
  final Map<int, List<int>> _triBuckets = {};

  BarycentricHit? locate(double px, double py) {
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
        continue;
      }
      final w0 = ((by - cyv) * (px - cxv) + (cxv - bx) * (py - cyv)) / denom;
      final w1 = ((cyv - ay) * (px - cxv) + (ax - cxv) * (py - cyv)) / denom;
      final w2 = 1.0 - w0 - w1;
      if (w0 < -1e-4 || w1 < -1e-4 || w2 < -1e-4) {
        continue;
      }
      return BarycentricHit(i0: i0, i1: i1, i2: i2, w0: w0, w1: w1, w2: w2);
    }
    return null;
  }
}
