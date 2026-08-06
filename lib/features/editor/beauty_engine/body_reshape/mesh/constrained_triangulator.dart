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
/// Usa fila breadth-first para não esgotar o orçamento de vértices num único
/// lado do corpo. Células que não cabem no orçamento são emitidas no nível
/// corrente (nunca soldadas a vértices distantes).
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

    int? ensureVertex(Offset point) {
      final key = _quantizeKey(point);
      final existing = vertexIndex[key];
      if (existing != null) {
        return existing;
      }
      if (vertices.length ~/ 2 >= maxVertices) {
        // NÃO soldar a um vértice distante — isso colapsava um lado do corpo.
        return null;
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

    // Breadth-first: cobre o domínio inteiro antes de refinar um canto.
    final queue = <_Cell>[
      _Cell(
        left: bounds.left,
        top: bounds.top,
        width: bounds.width,
        height: bounds.height,
        depth: 0,
      ),
    ];
    const maxDepth = 16;

    while (queue.isNotEmpty) {
      final cell = queue.removeAt(0);
      if (cell.width <= 1e-6 || cell.height <= 1e-6) {
        continue;
      }

      final right = cell.left + cell.width;
      final bottom = cell.top + cell.height;
      final corners = <Offset>[
        Offset(cell.left, cell.top),
        Offset(right, cell.top),
        Offset(right, bottom),
        Offset(cell.left, bottom),
      ];
      final center = Offset(
        cell.left + cell.width * 0.5,
        cell.top + cell.height * 0.5,
      );
      final anyInside = isInside(center) ||
          corners.any(isInside) ||
          _sampleCellInterior(
            cell.left,
            cell.top,
            cell.width,
            cell.height,
            isInside,
          );
      if (!anyInside) {
        continue;
      }

      final target = cellSizeAt(center);
      final maxSide = math.max(cell.width, cell.height);
      final budgetLeft = maxVertices - vertices.length ~/ 2;
      // Só refina se ainda há orçamento para os 4 filhos (~4 cantos novos).
      final shouldRefine = maxSide > target * 1.15 &&
          cell.depth < maxDepth &&
          budgetLeft > 8;

      if (shouldRefine) {
        final halfW = cell.width * 0.5;
        final halfH = cell.height * 0.5;
        // Ordem em Z: NW, NE, SW, SE — mas a fila BFS equilibra os lados.
        queue
          ..add(
            _Cell(
              left: cell.left,
              top: cell.top,
              width: halfW,
              height: halfH,
              depth: cell.depth + 1,
            ),
          )
          ..add(
            _Cell(
              left: cell.left + halfW,
              top: cell.top,
              width: halfW,
              height: halfH,
              depth: cell.depth + 1,
            ),
          )
          ..add(
            _Cell(
              left: cell.left,
              top: cell.top + halfH,
              width: halfW,
              height: halfH,
              depth: cell.depth + 1,
            ),
          )
          ..add(
            _Cell(
              left: cell.left + halfW,
              top: cell.top + halfH,
              width: halfW,
              height: halfH,
              depth: cell.depth + 1,
            ),
          );
        continue;
      }

      final i0 = ensureVertex(corners[0]);
      final i1 = ensureVertex(corners[1]);
      final i2 = ensureVertex(corners[2]);
      final i3 = ensureVertex(corners[3]);
      if (i0 == null || i1 == null || i2 == null || i3 == null) {
        continue;
      }
      _emitTriangle(vertices, indices, i0, i1, i2, isInside);
      _emitTriangle(vertices, indices, i0, i2, i3, isInside);
    }

    return TriangulationResult(
      vertices: Float32List.fromList(vertices),
      indices: Uint32List.fromList(indices),
    );
  }

  void _emitTriangle(
    List<double> vertices,
    List<int> indices,
    int a,
    int b,
    int c,
    bool Function(Offset point) isInside,
  ) {
    if (a == b || b == c || a == c) {
      return;
    }
    final area2 = _area2(vertices, a, b, c);
    if (area2.abs() <= 1e-6) {
      return;
    }
    final centroid = Offset(
      (vertices[a * 2] + vertices[b * 2] + vertices[c * 2]) / 3,
      (vertices[a * 2 + 1] + vertices[b * 2 + 1] + vertices[c * 2 + 1]) / 3,
    );
    if (!isInside(centroid)) {
      return;
    }
    if (area2 < 0) {
      indices.addAll([a, c, b]);
    } else {
      indices.addAll([a, b, c]);
    }
  }

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

class _Cell {
  const _Cell({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.depth,
  });

  final double left;
  final double top;
  final double width;
  final double height;
  final int depth;
}
