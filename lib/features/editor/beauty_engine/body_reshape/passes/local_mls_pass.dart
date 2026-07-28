import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../models/mesh_region.dart';
import '../../models/warp_field.dart';
import '../../warp/mls_solver.dart';
import '../../warp/models/control_point.dart';
import 'body_reshape_pass.dart';
import 'pass_profiler.dart';

/// MLS local com índice espacial — não avalia todos os CPs por célula.
class LocalMlsPass implements BodyReshapePass {
  const LocalMlsPass({
    this.gridWidth = 64,
    this.gridHeight = 64,
    this.queryRadiusFactor = 0.18,
    this.minNeighbors = 3,
    this.mlsIterations = 5,
    this.blendWithPrevious = 0.35,
  });

  final int gridWidth;
  final int gridHeight;
  final double queryRadiusFactor;
  final int minNeighbors;
  final int mlsIterations;
  final double blendWithPrevious;

  @override
  String get id => 'local_mls';

  @override
  bool isEnabled(BodyMultiPassConfig config) => config.localMls;

  @override
  WarpField run(BodyPassContext context) {
    final points = context.controlPoints;
    if (points.isEmpty) {
      return context.field ??
          WarpField.identity(
            imageSize: context.imageSize,
            region: context.region,
          );
    }

    final result = buildField(
      controlPoints: points,
      imageSize: context.imageSize,
      region: context.region,
      intensity: context.plan?.maxIntensity ?? context.field?.intensity ?? 1.0,
      previous: context.field,
      gridWidth: gridWidth,
      gridHeight: gridHeight,
    );
    context.field = result.field;
    context.intermediateBuffers['local_mls_query_avg'] =
        Float32List.fromList([result.averageNeighborsQueried]);
    return result.field;
  }

  LocalMlsBuildResult buildField({
    required List<ControlPoint> controlPoints,
    required Size imageSize,
    required MeshRegion region,
    required double intensity,
    WarpField? previous,
    int? gridWidth,
    int? gridHeight,
  }) {
    final gw = gridWidth ?? this.gridWidth;
    final gh = gridHeight ?? this.gridHeight;
    if (intensity <= 0 || controlPoints.isEmpty) {
      return LocalMlsBuildResult(
        field: WarpField.identity(imageSize: imageSize, region: region),
        averageNeighborsQueried: 0,
        maxNeighborsQueried: 0,
        totalControlPoints: controlPoints.length,
      );
    }

    final index = ControlPointSpatialIndex(
      points: controlPoints,
      imageSize: imageSize,
    );
    final radius = math.max(
      24.0,
      math.min(imageSize.width, imageSize.height) * queryRadiusFactor,
    );

    final cellCount = gw * gh;
    final disp = Float32List(cellCount * 2);
    final mask = Float32List(cellCount);
    var neighborSum = 0;
    var neighborMax = 0;
    var samples = 0;
    var active = 0;

    for (var gy = 0; gy < gh; gy++) {
      for (var gx = 0; gx < gw; gx++) {
        final px = (gx / (gw - 1)) * imageSize.width;
        final py = (gy / (gh - 1)) * imageSize.height;
        final target = Offset(px, py);
        final local = index.queryNearby(
          target,
          radius: radius,
          minCount: minNeighbors,
        );
        neighborSum += local.length;
        neighborMax = math.max(neighborMax, local.length);
        samples++;

        if (local.length < 2) {
          continue;
        }

        // Mesma convenção do WarpFieldBuilder: source = inverse(target).
        final source = MlsSolver.inverse(
          local,
          target,
          iterations: mlsIterations,
        );
        var dx = source.dx - px;
        var dy = source.dy - py;

        if (previous != null && !previous.isIdentity && blendWithPrevious > 0) {
          final n = Offset(px / imageSize.width, py / imageSize.height);
          final pd = previous.sampleDisplacement(n);
          final pm = previous.sampleMask(n);
          final t = blendWithPrevious.clamp(0.0, 1.0);
          dx = dx * (1 - t) + pd.dx * pm * t;
          dy = dy * (1 - t) + pd.dy * pm * t;
        }

        final idx = gy * gw + gx;
        disp[idx * 2] = dx;
        disp[idx * 2 + 1] = dy;
        final mag = math.sqrt(dx * dx + dy * dy);
        mask[idx] = mag <= 1e-6 ? 0.0 : 1.0;
        if (mask[idx] > 0) {
          active++;
        }
      }
    }

    final avg = samples == 0 ? 0.0 : neighborSum / samples;
    final field = WarpField(
      gridWidth: gw,
      gridHeight: gh,
      displacement: disp,
      mask: mask,
      imageSize: imageSize,
      region: region,
      controlPoints: controlPoints,
      intensity: intensity.clamp(0.0, 1.0),
      passId: id,
      activeCellCount: active,
    );

    return LocalMlsBuildResult(
      field: field,
      averageNeighborsQueried: avg,
      maxNeighborsQueried: neighborMax,
      totalControlPoints: controlPoints.length,
    );
  }
}

class LocalMlsBuildResult {
  const LocalMlsBuildResult({
    required this.field,
    required this.averageNeighborsQueried,
    required this.maxNeighborsQueried,
    required this.totalControlPoints,
  });

  final WarpField field;
  final double averageNeighborsQueried;
  final int maxNeighborsQueried;
  final int totalControlPoints;

  /// Critério de aceite: consulta local << total de CPs.
  bool get usedLocalNeighborhood =>
      totalControlPoints <= 4 ||
      averageNeighborsQueried < totalControlPoints * 0.75;
}

/// Índice espacial de control points para MLS local.
class ControlPointSpatialIndex {
  ControlPointSpatialIndex({
    required List<ControlPoint> points,
    required Size imageSize,
    double? cellSize,
  })  : _points = points,
        _hash = SpatialHash2D(
          cellSize: cellSize ??
              math.max(
                16.0,
                math.min(imageSize.width, imageSize.height) / 24,
              ),
          originX: 0,
          originY: 0,
        ) {
    for (var i = 0; i < points.length; i++) {
      _hash.insert(i, points[i].source.dx, points[i].source.dy);
    }
  }

  final List<ControlPoint> _points;
  final SpatialHash2D _hash;
  int _lastQueryCount = 0;

  int get lastQueryCount => _lastQueryCount;
  int get pointCount => _points.length;

  List<ControlPoint> queryNearby(
    Offset point, {
    required double radius,
    int minCount = 3,
  }) {
    var ids = _hash.query(point.dx, point.dy, radius);
    _lastQueryCount = ids.length;

    if (ids.length < minCount && ids.length < _points.length) {
      var expanded = radius;
      for (var i = 0; i < 4 && ids.length < minCount; i++) {
        expanded *= 1.6;
        ids = _hash.query(point.dx, point.dy, expanded);
        _lastQueryCount = ids.length;
      }
    }

    if (ids.isEmpty) {
      return const [];
    }

    final result = <ControlPoint>[];
    final r2 = radius * radius * 4;
    for (final id in ids) {
      final cp = _points[id];
      final dx = cp.source.dx - point.dx;
      final dy = cp.source.dy - point.dy;
      if (dx * dx + dy * dy <= r2 || ids.length <= minCount) {
        result.add(cp);
      }
    }
    if (result.isEmpty) {
      for (final id in ids) {
        result.add(_points[id]);
      }
    }
    return result;
  }
}
