import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:editaiapp/features/editor/beauty_engine/warp/v2/distance_transform.dart';

/// Distância ao vizinho semente mais próximo por força bruta. Referência lenta
/// mas indiscutível para grids pequenos.
Float32List _bruteForce(
  Uint8List mask,
  int width,
  int height, {
  required bool seedOnZero,
}) {
  final seeds = <int>[];
  for (var i = 0; i < mask.length; i++) {
    final seed = seedOnZero ? mask[i] == 0 : mask[i] != 0;
    if (seed) {
      seeds.add(i);
    }
  }
  final out = Float32List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var best = double.infinity;
      for (final s in seeds) {
        final dx = (x - s % width).toDouble();
        final dy = (y - s ~/ width).toDouble();
        final d2 = dx * dx + dy * dy;
        if (d2 < best) {
          best = d2;
        }
      }
      out[y * width + x] = math.sqrt(best);
    }
  }
  return out;
}

void main() {
  group('EuclideanDistanceTransform', () {
    test('mede em euclidiana exacta, não em L1', () {
      const width = 21;
      const height = 21;
      final mask = Uint8List(width * height)..fillRange(0, width * height, 255);
      mask[10 * width + 10] = 0;

      final dist = EuclideanDistanceTransform.toZeroOf(mask, width, height);

      expect(dist[10 * width + 10], 0);
      // 3-4-5: o chamfer L1 devolvia 7 aqui.
      expect(dist[14 * width + 13], closeTo(5.0, 1e-4));
      expect(dist[10 * width + 15], closeTo(5.0, 1e-4));
      expect(dist[6 * width + 6], closeTo(4 * math.sqrt2, 1e-4));
    });

    test('coincide com a força bruta em máscara irregular', () {
      const width = 23;
      const height = 17;
      final rng = math.Random(7);
      final mask = Uint8List(width * height);
      for (var i = 0; i < mask.length; i++) {
        mask[i] = rng.nextDouble() < 0.12 ? 0 : 255;
      }

      final dist = EuclideanDistanceTransform.toZeroOf(mask, width, height);
      final reference = _bruteForce(mask, width, height, seedOnZero: true);

      for (var i = 0; i < mask.length; i++) {
        expect(dist[i], closeTo(reference[i], 1e-3), reason: 'pixel $i');
      }
    });

    test('toNonZeroOf semeia no não nulo e coincide com a força bruta', () {
      const width = 19;
      const height = 19;
      final mask = Uint8List(width * height);
      mask[3 * width + 4] = 255;
      mask[15 * width + 12] = 255;

      final dist = EuclideanDistanceTransform.toNonZeroOf(mask, width, height);
      final reference = _bruteForce(mask, width, height, seedOnZero: false);

      expect(dist[3 * width + 4], 0);
      expect(dist[15 * width + 12], 0);
      for (var i = 0; i < mask.length; i++) {
        expect(dist[i], closeTo(reference[i], 1e-3), reason: 'pixel $i');
      }
    });

    test('é 1-Lipschitz entre vizinhos ortogonais (rampa sem degrau duplo)', () {
      const width = 40;
      const height = 40;
      // Semiplano oblíquo: a fronteira que fazia escada no chamfer L1.
      final mask = Uint8List(width * height);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          mask[y * width + x] = (y > 0.6 * x + 5) ? 255 : 0;
        }
      }

      final dist = EuclideanDistanceTransform.toZeroOf(mask, width, height);

      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final i = y * width + x;
          if (x + 1 < width) {
            expect((dist[i + 1] - dist[i]).abs(), lessThanOrEqualTo(1 + 1e-4));
          }
          if (y + 1 < height) {
            expect(
              (dist[i + width] - dist[i]).abs(),
              lessThanOrEqualTo(1 + 1e-4),
            );
          }
        }
      }
    });

    test('sem semente satura a rampa em vez de devolver NaN', () {
      const width = 9;
      const height = 9;
      final mask = Uint8List(width * height)..fillRange(0, width * height, 255);

      final dist = EuclideanDistanceTransform.toZeroOf(mask, width, height);

      for (final d in dist) {
        expect(d.isFinite, isTrue);
        expect(math.min(1.0, d / 12.0), 1.0);
      }
    });

    test('rejeita tamanho inválido e máscara desalinhada', () {
      expect(
        () => EuclideanDistanceTransform.toZeroOf(Uint8List(0), 0, 4),
        throwsArgumentError,
      );
      expect(
        () => EuclideanDistanceTransform.toZeroOf(Uint8List(10), 4, 4),
        throwsArgumentError,
      );
    });
  });
}
