import 'dart:typed_data';

/// Utilitarios de validacao e manipulacao de malha.
abstract class MeshUtils {
  /// Retorna buffer de indices sem triangulos degenerados (area ~0).
  static Uint32List filterDegenerateTriangles(Float32List vertices, Uint32List indices) {
    if (indices.isEmpty) {
      return indices;
    }

    final kept = <int>[];
    const epsilon = 1e-8;

    for (var t = 0; t < indices.length; t += 3) {
      final a = indices[t];
      final b = indices[t + 1];
      final c = indices[t + 2];

      if (a == b || b == c || a == c) {
        continue;
      }

      final ax = vertices[a * 2];
      final ay = vertices[a * 2 + 1];
      final bx = vertices[b * 2];
      final by = vertices[b * 2 + 1];
      final cx = vertices[c * 2];
      final cy = vertices[c * 2 + 1];

      final area2 = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
      if (area2.abs() > epsilon) {
        kept.addAll([a, b, c]);
      }
    }

    return Uint32List.fromList(kept);
  }

  /// Quantiza coordenadas para hash de cache (3 casas decimais).
  static int quantizeHash(double value) => (value * 1000).round();
}
