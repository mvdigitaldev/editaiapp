import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/backward_bilinear_warp.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/cheekbones/cheekbones_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/chin/chin_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/displacement_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/jaw_angle/jaw_angle_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/jaw_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/v_chin/v_chin_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/v_shape/v_shape_field.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../filters/skin/mvp_benchmark_faces.dart';

/// Alvo de alto contraste com detalhe ao limite de Nyquist. É o pior caso da
/// compressão e aproxima a textura do cabelo junto à silhueta, que é onde o
/// serrilhado se vê.
Uint8List _fineDetail(int width, int height) {
  final rgba = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final value = ((x ~/ 2) + (y ~/ 2)).isEven ? 245 : 20;
      final i = (y * width + x) * 4;
      rgba[i] = value;
      rgba[i + 1] = value;
      rgba[i + 2] = value;
      rgba[i + 3] = 255;
    }
  }
  return rgba;
}

double _fieldAt(
  Float32List component,
  int width,
  int height,
  double px,
  double py,
) {
  if (px < 0 || py < 0 || px > width - 1 || py > height - 1) {
    return 0;
  }
  final x0 = px.floor();
  final y0 = py.floor();
  final x1 = x0 + 1 < width ? x0 + 1 : x0;
  final y1 = y0 + 1 < height ? y0 + 1 : y0;
  final tx = px - x0;
  final ty = py - y0;
  final top = component[y0 * width + x0] +
      (component[y0 * width + x1] - component[y0 * width + x0]) * tx;
  final bottom = component[y1 * width + x0] +
      (component[y1 * width + x1] - component[y1 * width + x0]) * tx;
  return top + (bottom - top) * ty;
}

/// Verdade de referência: filtro de área do pixel com 8×8 sub-amostras. É o que
/// o remap devia devolver se o custo não contasse.
double _areaReference(
  Uint8List source,
  DisplacementField field,
  int width,
  int height,
  int x,
  int y,
) {
  const perAxis = 8;
  const step = 1.0 / perAxis;
  var sum = 0.0;
  var taken = 0;
  for (var sy = 0; sy < perAxis; sy++) {
    final py = y + (sy + 0.5) * step - 0.5;
    for (var sx = 0; sx < perAxis; sx++) {
      final px = x + (sx + 0.5) * step - 0.5;
      final srcX = px - _fieldAt(field.dx, width, height, px, py);
      final srcY = py - _fieldAt(field.dy, width, height, px, py);
      if (srcX < 0 || srcY < 0 || srcX > width - 1 || srcY > height - 1) {
        continue;
      }
      final x0 = srcX.floor();
      final y0 = srcY.floor();
      final x1 = x0 + 1 < width ? x0 + 1 : x0;
      final y1 = y0 + 1 < height ? y0 + 1 : y0;
      final tx = srcX - x0;
      final ty = srcY - y0;
      double at(int ax, int ay) => source[(ay * width + ax) * 4].toDouble();
      final top = at(x0, y0) + (at(x1, y0) - at(x0, y0)) * tx;
      final bottom = at(x0, y1) + (at(x1, y1) - at(x0, y1)) * tx;
      sum += top + (bottom - top) * ty;
      taken++;
    }
  }
  return taken == 0 ? 0 : sum / taken;
}

/// Índices onde o remap comprime, isto é onde o maior valor singular de
/// `I − JD` passa de um e a bilinear já não chega.
List<int> _compressedPixels(DisplacementField f, int width, int height) {
  final out = <int>[];
  for (var y = 1; y + 1 < height; y++) {
    for (var x = 1; x + 1 < width; x++) {
      final i = y * width + x;
      if (f.dx[i].abs() < 1e-9 && f.dy[i].abs() < 1e-9) {
        continue;
      }
      final a = 1 - (f.dx[i + 1] - f.dx[i - 1]) * 0.5;
      final b = -(f.dx[i + width] - f.dx[i - width]) * 0.5;
      final c = -(f.dy[i + 1] - f.dy[i - 1]) * 0.5;
      final d = 1 - (f.dy[i + width] - f.dy[i - width]) * 0.5;
      final frobenius = a * a + b * b + c * c + d * d;
      final determinant = a * d - b * c;
      final disc = frobenius * frobenius - 4 * determinant * determinant;
      final root = disc > 0 ? math.sqrt(disc) : 0.0;
      if (math.sqrt((frobenius + root) * 0.5) > 1.05) {
        out.add(i);
      }
    }
  }
  return out;
}

Map<String, DisplacementField> _fieldsAtExtreme(
  FaceMeshResult face,
  Size size,
) =>
    {
      'jaw': JawField.build(face: face, imageSize: size, t: 1).field,
      'jaw_angle': JawAngleField.build(
        face: face,
        imageSize: size,
        t: 1,
        computeMetrics: false,
      ).field,
      'chin': ChinField.build(
        face: face,
        imageSize: size,
        t: 1,
        computeMetrics: false,
      ).field,
      'v_chin': VChinField.build(
        face: face,
        imageSize: size,
        t: 1,
        computeMetrics: false,
      ).field,
      'v_shape': VShapeField.build(
        face: face,
        imageSize: size,
        t: 1,
        computeMetrics: false,
      ).field,
      'cheekbone': CheekbonesField.build(
        face: face,
        imageSize: size,
        t: 1,
        computeMetrics: false,
      ).field,
    };

void main() {
  final faces = loadAvailableRealBenchmarkFaces();

  group('BackwardBilinearWarp — amostragem sob compressão', () {
    test('translação pura não perde nitidez', () {
      // Campo constante: a compressão é exactamente um, portanto não há razão
      // para filtrar por área e o remap tem de ficar na bilinear pura. Se
      // filtrasse aqui, toda a imagem perdia nitidez a troco de nada.
      const width = 64;
      const height = 64;
      final field = DisplacementField.zeros(width: width, height: height);
      for (var i = 0; i < field.pixelCount; i++) {
        field.dx[i] = -3.5;
        field.dy[i] = 0;
      }
      final source = _fineDetail(width, height);
      final out = BackwardBilinearWarp.apply(
        WarpRequest(
          sourceRgba: source,
          width: width,
          height: height,
          field: field,
        ),
      ).rgba;

      // Deslocamento de meio pixel na horizontal: a bilinear devolve a média
      // exacta de dois vizinhos. Uma média de área devolveria outra coisa.
      for (var y = 4; y < height - 4; y++) {
        for (var x = 8; x < width - 8; x++) {
          final i = y * width + x;
          final srcX = x + 3.5;
          if (srcX > width - 1) {
            continue;
          }
          final x0 = srcX.floor();
          final expected = (source[(y * width + x0) * 4] +
                  source[(y * width + x0 + 1) * 4]) /
              2;
          expect(out[i * 4], closeTo(expected, 1));
        }
      }
    });

    test('compressão uniforme fica junto ao filtro de área', () {
      // `src = x − dx`, portanto com `dx = −0.35 x` cada passo no destino dá
      // 1,35 px na origem: é compressão de 1,35×, a ordem do que os efeitos
      // faciais produzem no extremo.
      const width = 96;
      const height = 96;
      final field = DisplacementField.zeros(width: width, height: height);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          field.dx[y * width + x] = -0.35 * (x - width / 2);
        }
      }
      final source = _fineDetail(width, height);
      final out = BackwardBilinearWarp.apply(
        WarpRequest(
          sourceRgba: source,
          width: width,
          height: height,
          field: field,
        ),
      ).rgba;

      var sumSquares = 0.0;
      var count = 0;
      for (var y = 2; y + 2 < height; y++) {
        for (var x = 2; x + 2 < width; x++) {
          final i = y * width + x;
          final srcX = x - field.dx[i];
          if (srcX < 2 || srcX > width - 3) {
            continue;
          }
          final reference =
              _areaReference(source, field, width, height, x, y);
          final error = out[i * 4] - reference;
          sumSquares += error * error;
          count++;
        }
      }
      expect(count, greaterThan(0));
      // Sem filtro de área o erro andava nos 33 níveis de 255.
      expect(math.sqrt(sumSquares / count), lessThan(8));
    });

    for (final sample in faces) {
      test('nenhum efeito alia onde comprime — ${sample.id}', () {
        final size = sample.imageSize;
        final width = size.width.round();
        final height = size.height.round();
        final source = _fineDetail(width, height);

        for (final entry in _fieldsAtExtreme(sample.face, size).entries) {
          final field = entry.value;
          final compressed = _compressedPixels(field, width, height);
          if (compressed.isEmpty) {
            continue;
          }
          final out = BackwardBilinearWarp.apply(
            WarpRequest(
              sourceRgba: source,
              width: width,
              height: height,
              field: field,
            ),
          ).rgba;

          var sumSquares = 0.0;
          var worst = 0.0;
          for (final i in compressed) {
            final reference = _areaReference(
              source,
              field,
              width,
              height,
              i % width,
              i ~/ width,
            );
            final error = (out[i * 4] - reference).abs();
            sumSquares += error * error;
            worst = math.max(worst, error);
          }
          final rms = math.sqrt(sumSquares / compressed.length);
          // Com bilinear pura estes campos davam 33 de RMS e 57 de pior caso,
          // num alvo que só vai de 20 a 245: era o serrilhado que se via na
          // bochecha com a mandíbula no extremo.
          expect(
            rms,
            lessThan(6),
            reason: '${entry.key} alia sob compressão '
                '(RMS $rms em ${compressed.length} pixels)',
          );
          expect(
            worst,
            lessThan(20),
            reason: '${entry.key} alia sob compressão (pior $worst)',
          );
        }
      });
    }
  });
}
