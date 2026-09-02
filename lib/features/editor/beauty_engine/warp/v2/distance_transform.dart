import 'dart:math' as math;
import 'dart:typed_data';

/// Transformada de distância euclidiana exacta (Felzenszwalb & Huttenlocher),
/// separável, O(width × height). Só grid do campo: sem RGBA, sem landmarks.
///
/// Substitui o chamfer de duas passagens com 4 vizinhos e custo 1, que media em
/// L1: as isolinhas saíam em losango a 45° e em passos inteiros, o que imprimia
/// escada nas rampas assentes em silhuetas oblíquas.
abstract final class EuclideanDistanceTransform {
  EuclideanDistanceTransform._();

  /// Sentinela para «sem semente». Fica acima de qualquer distância² real num
  /// grid de foto e ainda longe da perda de precisão do `double`.
  static const _unreachable = 1e15;

  /// Distância de cada pixel ao zero mais próximo (`mask[i] == 0`).
  static Float32List toZeroOf(Uint8List mask, int width, int height) =>
      _transform(mask, width, height, seedOnZero: true);

  /// Distância de cada pixel ao pixel não nulo mais próximo (`mask[i] != 0`).
  static Float32List toNonZeroOf(Uint8List mask, int width, int height) =>
      _transform(mask, width, height, seedOnZero: false);

  static Float32List _transform(
    Uint8List mask,
    int width,
    int height, {
    required bool seedOnZero,
  }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('edt_invalid_size: ${width}x$height');
    }
    final pixelCount = width * height;
    if (mask.length != pixelCount) {
      throw ArgumentError(
        'edt_mask_size_mismatch: got ${mask.length}, expected $pixelCount',
      );
    }

    final sq = Float64List(pixelCount);
    for (var i = 0; i < pixelCount; i++) {
      final seed = seedOnZero ? mask[i] == 0 : mask[i] != 0;
      sq[i] = seed ? 0.0 : _unreachable;
    }

    final span = math.max(width, height);
    final f = Float64List(span);
    final d = Float64List(span);
    final v = Int32List(span);
    final z = Float64List(span + 1);

    for (var x = 0; x < width; x++) {
      for (var y = 0; y < height; y++) {
        f[y] = sq[y * width + x];
      }
      _lowerEnvelope(f, d, v, z, height);
      for (var y = 0; y < height; y++) {
        sq[y * width + x] = d[y];
      }
    }

    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        f[x] = sq[row + x];
      }
      _lowerEnvelope(f, d, v, z, width);
      for (var x = 0; x < width; x++) {
        sq[row + x] = d[x];
      }
    }

    final out = Float32List(pixelCount);
    for (var i = 0; i < pixelCount; i++) {
      out[i] = math.sqrt(sq[i]);
    }
    return out;
  }

  /// Envolvente inferior das parábolas `f[q] + (x - q)²` sobre uma linha de
  /// [n] amostras. `v` guarda os vértices e `z` as fronteiras entre eles.
  static void _lowerEnvelope(
    Float64List f,
    Float64List d,
    Int32List v,
    Float64List z,
    int n,
  ) {
    var k = 0;
    v[0] = 0;
    z[0] = -_unreachable;
    z[1] = _unreachable;
    for (var q = 1; q < n; q++) {
      var s = _intersect(f, v[k], q);
      while (s <= z[k]) {
        k--;
        s = _intersect(f, v[k], q);
      }
      k++;
      v[k] = q;
      z[k] = s;
      z[k + 1] = _unreachable;
    }
    k = 0;
    for (var q = 0; q < n; q++) {
      while (z[k + 1] < q) {
        k++;
      }
      final delta = q - v[k];
      d[q] = delta * delta + f[v[k]];
    }
  }

  static double _intersect(Float64List f, int p, int q) =>
      ((f[q] + q * q) - (f[p] + p * p)) / (2 * q - 2 * p);
}
