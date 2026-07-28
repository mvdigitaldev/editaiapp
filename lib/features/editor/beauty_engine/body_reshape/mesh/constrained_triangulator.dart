import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Resultado bruto de uma triangulação restrita ao domínio interior.
class TriangulationResult {
  final Float32List vertices;
  final Uint32List indices;

  const TriangulationResult({
    required this.vertices,
    required this.indices,
  });

  int get vertexCount => vertices.length ~/ 2;
  int get triangleCount => indices.length ~/ 3;
}

/// Triangulador por subdivisão adaptativa de células retangulares.
///
/// Vértices são soldados por quantização; triângulos cujos centróides estão
/// fora do domínio são descartados. Adequado a milhares de vértices.
class ConstrainedTriangulator {
  const ConstrainedTriangulator({
    this.quantizeDecimals = 2,
  });

  final int quantizeDecimals;

  TriangulationResult triangulate({
    required Rect bounds,
    required bool Function(Offset point) isInside,
    required double Function(Offset point) cellSizeAt,
    required int maxVertices,
    List<Offset> seededPoints = const [],
  }) {
    if (bounds.isEmpty || bounds.width <= 0 || bounds.height <= 0) {
      return TriangulationResult(
        vertices: Float32List(0),
        indices: Uint32List(0),
      );
    }

    final vertexIndex = <int, int>{};
    final vertices = <double>[];
    final indices = <int>[];

    int ensureVertex(Offset point) {
      final key = _quantizeKey(point);
      final existing = vertexIndex[key];
      if (existing != null) {
        return existing;
      }
      if (vertices.length ~/ 2 >= maxVertices) {
        if (vertices.isEmpty) {
          final index = 0;
          vertexIndex[key] = index;
          vertices
            ..add(point.dx)
            ..add(point.dy);
          return index;
        }
        return _nearestExisting(vertices, point);
      }
      final index = vertices.length ~/ 2;
      vertexIndex[key] = index;
      vertices
        ..add(point.dx)
        ..add(point.dy);
      return index;
    }

    for (final seed in seededPoints) {
      if (isInside(seed)) {
        ensureVertex(seed);
      }
    }

    _subdivide(
      left: bounds.left,
      top: bounds.top,
      width: bounds.width,
      height: bounds.height,
      isInside: isInside,
      cellSizeAt: cellSizeAt,
      ensureVertex: ensureVertex,
      emitTriangle: (a, b, c) {
        if (!_isValidTriangle(vertices, a, b, c)) {
          return;
        }
        final centroid = Offset(
          (vertices[a * 2] + vertices[b * 2] + vertices[c * 2]) / 3,
          (vertices[a * 2 + 1] + vertices[b * 2 + 1] + vertices[c * 2 + 1]) /
              3,
        );
        if (!isInside(centroid)) {
          return;
        }
        final area2 = _area2(vertices, a, b, c);
        if (area2 < 0) {
          indices.addAll([a, c, b]);
        } else {
          indices.addAll([a, b, c]);
        }
      },
      depth: 0,
      maxDepth: 16,
    );

    return TriangulationResult(
      vertices: Float32List.fromList(vertices),
      indices: Uint32List.fromList(indices),
    );
  }

  void _subdivide({
    required double left,
    required double top,
    required double width,
    required double height,
    required bool Function(Offset point) isInside,
    required double Function(Offset point) cellSizeAt,
    required int Function(Offset point) ensureVertex,
    required void Function(int a, int b, int c) emitTriangle,
    required int depth,
    required int maxDepth,
  }) {
    if (width <= 1e-6 || height <= 1e-6) {
      return;
    }

    final right = left + width;
    final bottom = top + height;
    final corners = <Offset>[
      Offset(left, top),
      Offset(right, top),
      Offset(right, bottom),
      Offset(left, bottom),
    ];
    final center = Offset(left + width * 0.5, top + height * 0.5);
    final anyInside = isInside(center) ||
        corners.any(isInside) ||
        _sampleCellInterior(left, top, width, height, isInside);

    if (!anyInside) {
      return;
    }

    final target = cellSizeAt(center);
    final maxSide = math.max(width, height);
    final shouldRefine = maxSide > target * 1.15 && depth < maxDepth;

    if (shouldRefine) {
      final halfW = width * 0.5;
      final halfH = height * 0.5;
      _subdivide(
        left: left,
        top: top,
        width: halfW,
        height: halfH,
        isInside: isInside,
        cellSizeAt: cellSizeAt,
        ensureVertex: ensureVertex,
        emitTriangle: emitTriangle,
        depth: depth + 1,
        maxDepth: maxDepth,
      );
      _subdivide(
        left: left + halfW,
        top: top,
        width: halfW,
        height: halfH,
        isInside: isInside,
        cellSizeAt: cellSizeAt,
        ensureVertex: ensureVertex,
        emitTriangle: emitTriangle,
        depth: depth + 1,
        maxDepth: maxDepth,
      );
      _subdivide(
        left: left,
        top: top + halfH,
        width: halfW,
        height: halfH,
        isInside: isInside,
        cellSizeAt: cellSizeAt,
        ensureVertex: ensureVertex,
        emitTriangle: emitTriangle,
        depth: depth + 1,
        maxDepth: maxDepth,
      );
      _subdivide(
        left: left + halfW,
        top: top + halfH,
        width: halfW,
        height: halfH,
        isInside: isInside,
        cellSizeAt: cellSizeAt,
        ensureVertex: ensureVertex,
        emitTriangle: emitTriangle,
        depth: depth + 1,
        maxDepth: maxDepth,
      );
      return;
    }

    final i0 = ensureVertex(corners[0]);
    final i1 = ensureVertex(corners[1]);
    final i2 = ensureVertex(corners[2]);
    final i3 = ensureVertex(corners[3]);
    emitTriangle(i0, i1, i2);
    emitTriangle(i0, i2, i3);
  }

  /// Amostra interior da célula para não perder silhuetas finas.
  bool _sampleCellInterior(
    double left,
    double top,
    double width,
    double height,
    bool Function(Offset point) isInside,
  ) {
    const steps = 3;
    for (var iy = 0; iy <= steps; iy++) {
      for (var ix = 0; ix <= steps; ix++) {
        final point = Offset(
          left + width * (ix / steps),
          top + height * (iy / steps),
        );
        if (isInside(point)) {
          return true;
        }
      }
    }
    return false;
  }

  int _quantizeKey(Offset point) {
    final scale = math.pow(10, quantizeDecimals).toDouble();
    final x = (point.dx * scale).round();
    final y = (point.dy * scale).round();
    return Object.hash(x, y);
  }

  int _nearestExisting(List<double> vertices, Offset point) {
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < vertices.length; i += 2) {
      final dx = vertices[i] - point.dx;
      final dy = vertices[i + 1] - point.dy;
      final d = dx * dx + dy * dy;
      if (d < bestDist) {
        bestDist = d;
        best = i ~/ 2;
      }
    }
    return best;
  }

  bool _isValidTriangle(List<double> vertices, int a, int b, int c) {
    if (a == b || b == c || a == c) {
      return false;
    }
    return _area2(vertices, a, b, c).abs() > 1e-6;
  }

  double _area2(List<double> vertices, int a, int b, int c) {
    final ax = vertices[a * 2];
    final ay = vertices[a * 2 + 1];
    final bx = vertices[b * 2];
    final by = vertices[b * 2 + 1];
    final cx = vertices[c * 2];
    final cy = vertices[c * 2 + 1];
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
  }
}
