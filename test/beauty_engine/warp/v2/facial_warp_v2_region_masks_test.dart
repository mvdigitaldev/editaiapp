import 'dart:math' as math;
import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/warp/v2/distance_transform.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/region_catalog.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/region_masks.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../filters/skin/mvp_benchmark_faces.dart';

/// Rasterização ponto a ponto, que é a definição que [RegionMaskRaster] tem de
/// reproduzir. Percorre o anel inteiro em cada pixel.
Uint8List _byDefinition(int width, int height, List<Offset> ring) {
  final mask = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (RegionMaskRaster.pointInPolygon(x + 0.5, y + 0.5, ring)) {
        mask[y * width + x] = 255;
      }
    }
  }
  return mask;
}

/// Dilatação por distância medida na imagem inteira, sem janela.
Uint8List _dilateByDefinition(
  Uint8List mask,
  int width,
  int height,
  int radius,
) {
  final out = Uint8List.fromList(mask);
  final dist = EuclideanDistanceTransform.toNonZeroOf(mask, width, height);
  for (var i = 0; i < out.length; i++) {
    if (dist[i] <= radius) {
      out[i] = 255;
    }
  }
  return out;
}

void main() {
  group('RegionMaskRaster.fillPolygon', () {
    test('coincide com a definição ponto a ponto', () {
      const width = 90;
      const height = 70;
      final cases = <String, List<Offset>>{
        // Vértices em coordenada inteira e em meio pixel: o meio pixel cai
        // exactamente na linha de amostragem, que é o caso degenerado.
        'triângulo': const [Offset(10, 8), Offset(70, 20), Offset(30, 60)],
        'vértice na linha de amostra': const [
          Offset(10, 10.5),
          Offset(70, 10.5),
          Offset(40, 50.5),
        ],
        'côncavo em U': const [
          Offset(10, 10),
          Offset(80, 10),
          Offset(80, 60),
          Offset(60, 60),
          Offset(60, 30),
          Offset(30, 30),
          Offset(30, 60),
          Offset(10, 60),
        ],
        'auto-intersectante': const [
          Offset(10, 10),
          Offset(80, 60),
          Offset(80, 10),
          Offset(10, 60),
        ],
        'aresta horizontal': const [
          Offset(15, 15),
          Offset(75, 15),
          Offset(75, 45),
          Offset(15, 45),
        ],
        'fora da imagem': const [
          Offset(-20, -10),
          Offset(50, -10),
          Offset(50, 30),
          Offset(-20, 30),
        ],
      };
      for (final entry in cases.entries) {
        final mask = RegionMaskRaster.zeros(width, height);
        RegionMaskRaster.fillPolygon(mask, width, height, entry.value);
        expect(mask, _byDefinition(width, height, entry.value),
            reason: entry.key);
      }
    });

    test('coincide no oval de uma cara real', () {
      final sample = loadAvailableRealBenchmarkFaces().first;
      final size = sample.imageSize;
      final width = size.width.round();
      final height = size.height.round();
      final ring = <Offset>[];
      for (final id in V2RegionCatalog.faceOval) {
        for (final lm in sample.face.landmarks) {
          if (lm.index == id) {
            ring.add(
              Offset(lm.normalized.dx * width, lm.normalized.dy * height),
            );
            break;
          }
        }
      }
      expect(ring.length, greaterThan(20));
      final mask = RegionMaskRaster.zeros(width, height);
      RegionMaskRaster.fillPolygon(mask, width, height, ring);
      expect(mask, _byDefinition(width, height, ring));
      var filled = 0;
      for (final v in mask) {
        if (v != 0) filled++;
      }
      expect(filled, greaterThan(1000));
    });
  });

  group('RegionMaskRaster.dilate', () {
    test('coincide com a distância medida na imagem inteira', () {
      const width = 120;
      const height = 100;
      for (final radius in [1, 7, 30]) {
        final seed = RegionMaskRaster.zeros(width, height);
        RegionMaskRaster.fillDisk(
          seed,
          width,
          height,
          const Offset(58, 44),
          9,
        );
        // Segunda semente encostada à borda, para exercitar o recorte.
        RegionMaskRaster.fillDisk(seed, width, height, const Offset(2, 96), 4);
        final windowed = Uint8List.fromList(seed);
        RegionMaskRaster.dilate(windowed, width, height, radius);
        expect(
          windowed,
          _dilateByDefinition(seed, width, height, radius),
          reason: 'radius=$radius',
        );
      }
    });

    test('máscara vazia continua vazia', () {
      final mask = RegionMaskRaster.zeros(20, 20);
      RegionMaskRaster.dilate(mask, 20, 20, 5);
      expect(mask, everyElement(0));
    });

    test('cresce mesmo, e só até ao raio', () {
      const width = 60;
      const height = 60;
      final mask = RegionMaskRaster.zeros(width, height);
      mask[30 * width + 30] = 255;
      RegionMaskRaster.dilate(mask, width, height, 6);
      expect(mask[30 * width + 36], 255);
      expect(mask[30 * width + 37], 0);
      var filled = 0;
      for (final v in mask) {
        if (v != 0) filled++;
      }
      // Área de um disco de raio 6 medido do centro do pixel.
      expect(filled, closeTo(math.pi * 36, math.pi * 36 * 0.25));
    });
  });
}
