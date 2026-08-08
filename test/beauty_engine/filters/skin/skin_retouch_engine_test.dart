import 'dart:math' as math;
import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/color/color_science.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/skin/guided_filter.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/skin/skin_retouch_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Testes de invariantes das fichas do Grupo A
/// (`docs/beauty/13-visual-quality-targets.md`).
void main() {
  const width = 96;
  const height = 96;
  const pixels = width * height;
  const faceEdgePx = 600.0;

  /// Patch de "pele": tom base + poros (alta frequência) + mancha suave
  /// (média frequência) + opcionalmente uma faixa de fundo intocável.
  Uint8List skinPatch({
    bool withBlemish = false,
    bool withShine = false,
    bool withDarkUnderEye = false,
  }) {
    final rgba = Uint8List(pixels * 4);
    final random = math.Random(42);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        // Tom de pele base com gradiente de iluminação suave.
        var r = 208.0 + x * 0.08;
        var g = 165.0 + x * 0.06;
        var b = 145.0 + x * 0.05;

        // Poros: alta frequência de baixa amplitude.
        final pore = (random.nextDouble() - 0.5) * 9;
        r += pore;
        g += pore;
        b += pore;

        // Blotch de média frequência (região mais escura e larga).
        if (withBlemish) {
          final d = math.sqrt(math.pow(x - 48, 2) + math.pow(y - 48, 2));
          if (d < 9) {
            final falloff = 1 - d / 9;
            r -= 26 * falloff;
            g -= 20 * falloff;
            b -= 16 * falloff;
          }
        }

        if (withShine) {
          final d = math.sqrt(math.pow(x - 30, 2) + math.pow(y - 30, 2));
          if (d < 12) {
            final falloff = 1 - d / 12;
            r += 44 * falloff;
            g += 44 * falloff;
            b += 40 * falloff;
          }
        }

        if (withDarkUnderEye && y >= 60 && y < 76) {
          r -= 34;
          g -= 30;
          b -= 24;
        }

        rgba[i] = r.round().clamp(0, 255);
        rgba[i + 1] = g.round().clamp(0, 255);
        rgba[i + 2] = b.round().clamp(0, 255);
        rgba[i + 3] = 255;
      }
    }
    return rgba;
  }

  /// Pele em toda a imagem, exceto uma faixa "não-pele" (cílios/fundo) à
  /// direita, usada para provar que nada vaza fora da máscara.
  Uint8List skinWeights({int nonSkinFromX = 80}) {
    final weights = Uint8List(pixels);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        weights[y * width + x] = x < nonSkinFromX ? 255 : 0;
      }
    }
    return weights;
  }

  Uint8List underEyeWeights() {
    final weights = Uint8List(pixels);
    for (var y = 60; y < 76; y++) {
      for (var x = 0; x < 80; x++) {
        weights[y * width + x] = 255;
      }
    }
    return weights;
  }

  SkinRetouchRequest request(
    Uint8List rgba,
    SkinRetouchParams params, {
    Uint8List? weights,
    Uint8List? underEye,
  }) {
    return SkinRetouchRequest(
      rgba: rgba,
      width: width,
      height: height,
      skinWeights: weights ?? skinWeights(),
      underEyeWeights: underEye ?? Uint8List(pixels),
      params: params,
      // O patch representa um recorte de um rosto de ~600px: os raios do
      // filtro são proporcionais ao rosto, não ao tamanho do buffer.
      faceEdgePx: faceEdgePx,
    );
  }

  group('A1 — Suavizar pele', () {
    test('não altera nenhum pixel fora da máscara de pele', () {
      final input = skinPatch(withBlemish: true);
      final output = SkinRetouchEngine.run(
        request(input, const SkinRetouchParams(smooth: 1)),
      );

      for (var y = 0; y < height; y++) {
        for (var x = 80; x < width; x++) {
          final i = (y * width + x) * 4;
          expect(output[i], input[i], reason: 'R em ($x,$y)');
          expect(output[i + 1], input[i + 1], reason: 'G em ($x,$y)');
          expect(output[i + 2], input[i + 2], reason: 'B em ($x,$y)');
        }
      }
    });

    test('preserva >=70% da alta frequência (poros) no slider máximo', () {
      final input = skinPatch();
      final output = SkinRetouchEngine.run(
        request(input, const SkinRetouchParams(smooth: 1)),
      );

      final before = _highFrequencyStd(input, width, height);
      final after = _highFrequencyStd(output, width, height);

      expect(after / before, greaterThanOrEqualTo(0.70));
      expect(after / before, lessThan(1.05));
    });

    test('atenua a banda média (manchas/blotches)', () {
      final input = skinPatch(withBlemish: true);
      final output = SkinRetouchEngine.run(
        request(input, const SkinRetouchParams(smooth: 1)),
      );

      final before = _midFrequencyStd(input, width, height);
      final after = _midFrequencyStd(output, width, height);

      expect(after, lessThan(before * 0.6));
    });

    test('não escurece nem clareia a pele (luminância média estável)', () {
      final input = skinPatch(withBlemish: true);
      final output = SkinRetouchEngine.run(
        request(input, const SkinRetouchParams(smooth: 1)),
      );

      final before = _meanLuma(input, width, height, maxX: 80);
      final after = _meanLuma(output, width, height, maxX: 80);
      expect(after, closeTo(before, before * 0.02));
    });

    test('intensidade 0 devolve a imagem intacta', () {
      final input = skinPatch(withBlemish: true);
      final output = SkinRetouchEngine.run(
        request(input, const SkinRetouchParams()),
      );
      expect(output, input);
    });

    test('slider intermediário fica entre original e máximo', () {
      final input = skinPatch(withBlemish: true);
      final half = SkinRetouchEngine.run(
        request(input, const SkinRetouchParams(smooth: 0.5)),
      );
      final full = SkinRetouchEngine.run(
        request(input, const SkinRetouchParams(smooth: 1)),
      );

      final midHalf = _midFrequencyStd(half, width, height);
      final midFull = _midFrequencyStd(full, width, height);
      final midOriginal = _midFrequencyStd(input, width, height);

      expect(midHalf, lessThan(midOriginal));
      expect(midHalf, greaterThan(midFull));
    });
  });

  group('A2 — Remover acne/manchas', () {
    test('clareia a mancha em direção à pele vizinha', () {
      final input = skinPatch(withBlemish: true);
      final output = SkinRetouchEngine.run(
        request(input, const SkinRetouchParams(acne: 1)),
      );

      const center = (48 * width + 48) * 4;
      const neighbour = (48 * width + 20) * 4;

      final blemishBefore = input[center];
      final blemishAfter = output[center];
      expect(blemishAfter, greaterThan(blemishBefore));

      // A pele ao redor da mancha permanece praticamente igual.
      expect((output[neighbour] - input[neighbour]).abs(), lessThanOrEqualTo(3));
    });

    test('não inventa mancha em pele limpa', () {
      final input = skinPatch();
      final output = SkinRetouchEngine.run(
        request(input, const SkinRetouchParams(acne: 1)),
      );

      final before = _meanLuma(input, width, height, maxX: 80);
      final after = _meanLuma(output, width, height, maxX: 80);
      expect(after, closeTo(before, before * 0.02));
    });
  });

  group('A3 — Remover olheiras', () {
    test('clareia a região sob os olhos sem passar do tom da bochecha', () {
      final input = skinPatch(withDarkUnderEye: true);
      final output = SkinRetouchEngine.run(
        request(
          input,
          const SkinRetouchParams(darkCircles: 1),
          underEye: underEyeWeights(),
        ),
      );

      final underEyeBefore = _meanLuma(input, width, height,
          maxX: 80, minY: 62, maxY: 74);
      final underEyeAfter = _meanLuma(output, width, height,
          maxX: 80, minY: 62, maxY: 74);
      final cheekAfter =
          _meanLuma(output, width, height, maxX: 80, minY: 20, maxY: 40);

      expect(underEyeAfter, greaterThan(underEyeBefore));
      // Invariante: nunca mais claro que a referência de pele.
      expect(underEyeAfter, lessThanOrEqualTo(cheekAfter * 1.02));
    });

    test('não altera pele fora da região de olheira', () {
      final input = skinPatch(withDarkUnderEye: true);
      final output = SkinRetouchEngine.run(
        request(
          input,
          const SkinRetouchParams(darkCircles: 1),
          underEye: underEyeWeights(),
        ),
      );

      for (var y = 0; y < 55; y++) {
        for (var x = 0; x < width; x++) {
          final i = (y * width + x) * 4;
          expect(output[i], input[i], reason: 'R em ($x,$y)');
        }
      }
    });
  });

  group('A4 — Reduzir brilho', () {
    test('comprime highlight especular na pele', () {
      final input = skinPatch(withShine: true);
      final output = SkinRetouchEngine.run(
        request(input, const SkinRetouchParams(shine: 1)),
      );

      const highlight = (30 * width + 30) * 4;
      expect(output[highlight], lessThan(input[highlight]));

      // Região sem brilho quase inalterada.
      const plain = (70 * width + 15) * 4;
      expect((output[plain] - input[plain]).abs(), lessThanOrEqualTo(3));
    });

    test('não escurece abaixo do tom base da pele', () {
      final input = skinPatch(withShine: true);
      final output = SkinRetouchEngine.run(
        request(input, const SkinRetouchParams(shine: 1)),
      );

      const highlight = (30 * width + 30) * 4;
      const reference = (70 * width + 30) * 4;
      expect(output[highlight], greaterThanOrEqualTo(output[reference] - 2));
    });

    test('brilho fora da máscara de pele é preservado', () {
      final input = skinPatch(withShine: true);
      final output = SkinRetouchEngine.run(
        request(input, const SkinRetouchParams(shine: 1)),
      );

      for (var y = 0; y < height; y++) {
        for (var x = 80; x < width; x++) {
          final i = (y * width + x) * 4;
          expect(output[i], input[i]);
        }
      }
    });
  });

  group('Robustez', () {
    test('máscara de tamanho inconsistente não altera a imagem', () {
      final input = skinPatch();
      final output = SkinRetouchEngine.run(
        SkinRetouchRequest(
          rgba: input,
          width: width,
          height: height,
          skinWeights: Uint8List(10),
          underEyeWeights: Uint8List(0),
          params: const SkinRetouchParams(smooth: 1),
          faceEdgePx: width.toDouble(),
        ),
      );
      expect(output, input);
    });

    test('pele escura: mancha também é corrigida (limiar relativo)', () {
      // Mesma cena com tom de pele muito mais escuro — limiar absoluto
      // falharia aqui (cap. 16: calibração por tom de pele).
      final input = Uint8List(pixels * 4);
      final random = math.Random(3);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final i = (y * width + x) * 4;
          var value = 62.0 + (random.nextDouble() - 0.5) * 6;
          final d = math.sqrt(math.pow(x - 48, 2) + math.pow(y - 48, 2));
          if (d < 9) {
            value -= 14 * (1 - d / 9);
          }
          input[i] = value.round().clamp(0, 255);
          input[i + 1] = (value * 0.78).round().clamp(0, 255);
          input[i + 2] = (value * 0.66).round().clamp(0, 255);
          input[i + 3] = 255;
        }
      }

      final output = SkinRetouchEngine.run(
        request(input, const SkinRetouchParams(acne: 1)),
      );

      const center = (48 * width + 48) * 4;
      expect(output[center], greaterThan(input[center]));
    });
  });
}

Float32List _luma(Uint8List rgba, int width, int height) {
  return ColorScience.lumaFromRgba(rgba, width, height);
}

/// As bandas são medidas com a MESMA decomposição do engine, para que as
/// asserções batam com as constantes das fichas.
Float32List _fineBand(Float32List luma, int width, int height) {
  return GuidedFilter.filterSelf(
    luma,
    width: width,
    height: height,
    radius: SkinRetouchEngine.fineRadiusFor(600),
    eps: SkinRetouchEngine.fineEps,
  );
}

/// Desvio padrão da banda de alta frequência (poros), medido só na área de
/// pele para não misturar a faixa não-pele.
double _highFrequencyStd(Uint8List rgba, int width, int height) {
  final luma = _luma(rgba, width, height);
  final fine = _fineBand(luma, width, height);
  return _stdOfDifference(luma, fine, width, height, maxX: 80);
}

/// Banda média: entre a banda fina e a larga — onde vivem manchas e blotches.
double _midFrequencyStd(Uint8List rgba, int width, int height) {
  final luma = _luma(rgba, width, height);
  final fine = _fineBand(luma, width, height);
  final coarse = GuidedFilter.filterSelf(
    luma,
    width: width,
    height: height,
    radius: SkinRetouchEngine.coarseRadiusFor(600),
    eps: SkinRetouchEngine.coarseEps,
  );
  return _stdOfDifference(fine, coarse, width, height, maxX: 80);
}

double _stdOfDifference(
  Float32List a,
  Float32List b,
  int width,
  int height, {
  required int maxX,
}) {
  var sum = 0.0;
  var count = 0;
  for (var y = 4; y < height - 4; y++) {
    for (var x = 4; x < maxX - 4; x++) {
      sum += a[y * width + x] - b[y * width + x];
      count++;
    }
  }
  final mean = sum / count;
  var variance = 0.0;
  for (var y = 4; y < height - 4; y++) {
    for (var x = 4; x < maxX - 4; x++) {
      final d = (a[y * width + x] - b[y * width + x]) - mean;
      variance += d * d;
    }
  }
  return math.sqrt(variance / count);
}

double _meanLuma(
  Uint8List rgba,
  int width,
  int height, {
  required int maxX,
  int minY = 0,
  int? maxY,
}) {
  final luma = _luma(rgba, width, height);
  final endY = maxY ?? height;
  var sum = 0.0;
  var count = 0;
  for (var y = minY; y < endY; y++) {
    for (var x = 0; x < maxX; x++) {
      sum += luma[y * width + x];
      count++;
    }
  }
  return sum / count;
}
