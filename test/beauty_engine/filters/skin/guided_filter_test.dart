import 'dart:math' as math;
import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/filters/face/skin/guided_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GuidedFilter.boxMean', () {
    test('imagem constante permanece constante', () {
      final src = Float32List(16 * 16)..fillRange(0, 256, 0.37);
      final mean =
          GuidedFilter.boxMean(src, width: 16, height: 16, radius: 3);
      for (final value in mean) {
        expect(value, closeTo(0.37, 1e-6));
      }
    });

    test('média confere com cálculo direto (inclusive nas bordas)', () {
      const w = 9;
      const h = 7;
      const radius = 2;
      final src = Float32List(w * h);
      for (var i = 0; i < src.length; i++) {
        src[i] = (i % 13) / 13;
      }

      final mean = GuidedFilter.boxMean(src, width: w, height: h, radius: radius);

      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          var sum = 0.0;
          var count = 0;
          for (var dy = -radius; dy <= radius; dy++) {
            for (var dx = -radius; dx <= radius; dx++) {
              final sx = x + dx;
              final sy = y + dy;
              if (sx < 0 || sy < 0 || sx >= w || sy >= h) continue;
              sum += src[sy * w + sx];
              count++;
            }
          }
          expect(mean[y * w + x], closeTo(sum / count, 1e-5),
              reason: 'pixel ($x,$y)');
        }
      }
    });
  });

  group('GuidedFilter.filterSelf', () {
    test('remove ruído em região homogênea', () {
      const size = 48;
      final random = math.Random(7);
      final noisy = Float32List(size * size);
      for (var i = 0; i < noisy.length; i++) {
        noisy[i] = (0.45 + (random.nextDouble() - 0.5) * 0.06).clamp(0.0, 1.0);
      }

      // eps precisa ficar acima da variância do ruído para removê-lo: aqui o
      // ruído tem variância ~3e-4, então eps 1e-3 o atenua fortemente.
      final filtered = GuidedFilter.filterSelf(
        noisy,
        width: size,
        height: size,
        radius: 4,
        eps: 1e-3,
      );

      expect(_std(filtered), lessThan(_std(noisy) * 0.5));
      // A média se mantém: suavizar não pode escurecer/clarear a região.
      expect(_mean(filtered), closeTo(_mean(noisy), 5e-3));
    });

    test('preserva borda melhor que box blur (sem halo)', () {
      const w = 64;
      const h = 32;
      final step = Float32List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          step[y * w + x] = x < w ~/ 2 ? 0.2 : 0.8;
        }
      }

      final guided = GuidedFilter.filterSelf(
        step,
        width: w,
        height: h,
        radius: 6,
        eps: 1e-4,
      );
      final blurred = GuidedFilter.boxMean(step, width: w, height: h, radius: 6);

      // Contraste através da borda: guided mantém, box blur derrete.
      final guidedJump = guided[16 * w + w ~/ 2] - guided[16 * w + w ~/ 2 - 1];
      final blurJump = blurred[16 * w + w ~/ 2] - blurred[16 * w + w ~/ 2 - 1];
      expect(guidedJump, greaterThan(blurJump * 3));

      // Sem overshoot (halo): nada abaixo do mínimo nem acima do máximo.
      for (final value in guided) {
        expect(value, greaterThanOrEqualTo(0.2 - 1e-3));
        expect(value, lessThanOrEqualTo(0.8 + 1e-3));
      }
    });

    test('eps maior suaviza mais', () {
      const size = 40;
      final random = math.Random(11);
      final src = Float32List(size * size);
      for (var i = 0; i < src.length; i++) {
        src[i] = (0.5 + (random.nextDouble() - 0.5) * 0.2).clamp(0.0, 1.0);
      }

      final soft = GuidedFilter.filterSelf(
        src,
        width: size,
        height: size,
        radius: 3,
        eps: 1e-2,
      );
      final sharp = GuidedFilter.filterSelf(
        src,
        width: size,
        height: size,
        radius: 3,
        eps: 1e-5,
      );

      expect(_std(soft), lessThan(_std(sharp)));
    });

    test('radius 0 é no-op', () {
      final src = Float32List.fromList([0.1, 0.9, 0.4, 0.6]);
      final out =
          GuidedFilter.filterSelf(src, width: 2, height: 2, radius: 0, eps: 1e-4);
      expect(out, src);
    });
  });
}

double _mean(Float32List values) {
  var sum = 0.0;
  for (final value in values) {
    sum += value;
  }
  return sum / values.length;
}

double _std(Float32List values) {
  final mean = _mean(values);
  var sum = 0.0;
  for (final value in values) {
    final d = value - mean;
    sum += d * d;
  }
  return math.sqrt(sum / values.length);
}
