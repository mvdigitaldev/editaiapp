import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/filters/body/body_warp_chain.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/segment/person_mask.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/backward_bilinear_warp.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/body_arms/body_arms_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/displacement_field.dart';
import 'package:flutter_test/flutter_test.dart';

const _w = 300;
const _h = 400;
const _size = Size(300, 400);

/// Braço 11→13→15 esticado para a direita da foto (bordas livres, y 90–110);
/// braço 12→14→16 pendurado à esquerda, encostado ao tronco (x 90–110).
PoseResult _pose({bool wrists = true}) {
  final points = <int, Offset>{
    11: const Offset(190, 100),
    12: const Offset(110, 100),
    13: const Offset(240, 100),
    14: const Offset(100, 190),
    if (wrists) 15: const Offset(285, 100),
    if (wrists) 16: const Offset(100, 270),
  };
  return PoseResult(
    landmarks: [
      for (var i = 0; i < PoseResult.expectedLandmarkCount; i++)
        PoseLandmark(
          index: i,
          normalized: points.containsKey(i)
              ? Offset(points[i]!.dx / _w, points[i]!.dy / _h)
              : const Offset(0.5, 0.5),
          visibility: points.containsKey(i) ? 0.95 : 0.2,
        ),
    ],
    boundingBox: const Rect.fromLTWH(0.2, 0.1, 0.7, 0.8),
  );
}

PersonMask _mask() {
  final bytes = Uint8List(_w * _h);
  void fill(int x0, int x1, int y0, int y1) {
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        bytes[y * _w + x] = 255;
      }
    }
  }

  fill(110, 190, 90, 300); // tronco
  fill(185, 292, 90, 110); // braço esticado
  fill(90, 110, 100, 285); // braço pendurado, colado ao tronco
  return PersonMask(bytes: bytes, width: _w, height: _h);
}

Uint8List _rgba(PersonMask mask) {
  final out = Uint8List(_w * _h * 4);
  for (var i = 0; i < _w * _h; i++) {
    final v = mask.bytes[i] > 127 ? 255 : 0;
    out[i * 4] = v;
    out[i * 4 + 1] = v;
    out[i * 4 + 2] = v;
    out[i * 4 + 3] = 255;
  }
  return out;
}

double _columnWidth(Uint8List rgba, int x, int y0, int y1) {
  var sum = 0.0;
  for (var y = y0; y < y1; y++) {
    sum += rgba[(y * _w + x) * 4] / 255.0;
  }
  return sum;
}

double _rowWidth(Uint8List rgba, int y, int x0, int x1) {
  var sum = 0.0;
  for (var x = x0; x < x1; x++) {
    sum += rgba[(y * _w + x) * 4] / 255.0;
  }
  return sum;
}

double _minDetJ(DisplacementField f) {
  var minDet = double.infinity;
  for (var y = 1; y < _h - 1; y++) {
    for (var x = 1; x < _w - 1; x++) {
      final i = y * _w + x;
      final dxx = (f.dx[i + 1] - f.dx[i - 1]) / 2;
      final dxy = (f.dx[i + _w] - f.dx[i - _w]) / 2;
      final dyx = (f.dy[i + 1] - f.dy[i - 1]) / 2;
      final dyy = (f.dy[i + _w] - f.dy[i - _w]) / 2;
      final det = (1 - dxx) * (1 - dyy) - dxy * dyx;
      if (det < minDet) {
        minDet = det;
      }
    }
  }
  return minDet;
}

void main() {
  final pose = _pose();
  final mask = _mask();
  final source = _rgba(mask);

  DisplacementField arms(double t, [BodyArmsFieldRuntime? runtime]) =>
      BodyArmsField.build(
        pose: pose,
        imageSize: _size,
        mask: mask,
        t: t,
        runtime: runtime,
      )!;

  Uint8List warp(DisplacementField f) => BackwardBilinearWarp.apply(
        WarpRequest(sourceRgba: source, width: _w, height: _h, field: f),
      ).rgba;

  /// Antebraço esticado (S ≈ 0.68) e braço pendurado (S ≈ 0.4).
  const forearmX = 255;
  const hangingY = 170;

  test('mede os dois braços na máscara', () {
    final g = BodyArmsField.measure(pose: pose, imageSize: _size, mask: mask)!;
    expect(g.fromMask, isTrue);
    expect(g.arms, hasLength(2));
  });

  test('direita afina, esquerda engrossa', () {
    final before = _columnWidth(source, forearmX, 80, 120);
    expect(
      _columnWidth(warp(arms(1)), forearmX, 80, 120),
      lessThan(before - 1),
    );
    expect(
      _columnWidth(warp(arms(-1)), forearmX, 80, 120),
      greaterThan(before + 1),
    );
  });

  test('braço solto: as duas bordas andam o mesmo, e pouco', () {
    final f = arms(1);
    final top = f.dy[90 * _w + forearmX];
    final bottom = f.dy[109 * _w + forearmX];
    // source = dest − D: afinar vai buscar fundo de fora.
    expect(top, greaterThan(0));
    expect(bottom, lessThan(0));
    // A borda da máscara mede-se ao px: ±15%.
    expect((top.abs() - bottom.abs()).abs(), lessThan(0.15 * top.abs()));
    // ≈ 0.08 × meia-largura (10 px).
    expect(top.abs(), inInclusiveRange(0.4, 1.2));
  });

  test('braço colado ao tronco: o lado de contacto e o tronco ficam', () {
    final f = arms(1);
    // O lado colado escala em volta da linha de contacto (estimada): quase
    // parado face ao lado livre.
    final contact = f.dx[hangingY * _w + 109].abs();
    final free = f.dx[hangingY * _w + 90].abs();
    expect(free, greaterThan(0.6));
    expect(contact, lessThan(0.35 * free));
    final before = _rowWidth(source, hangingY, 80, 112);
    expect(_rowWidth(warp(f), hangingY, 80, 112), lessThan(before - 0.6));
    for (final x in [120, 150, 180]) {
      expect(f.dx[hangingY * _w + x], 0, reason: 'tronco x=$x');
      expect(f.dy[hangingY * _w + x], 0, reason: 'tronco x=$x');
    }
  });

  test('mão e ombro não se mexem', () {
    final f = arms(1);
    for (final (x, y) in [(289, 100), (291, 95), (100, 282), (150, 95)]) {
      expect(f.dx[y * _w + x].abs(), lessThan(1e-6), reason: '($x, $y)');
      expect(f.dy[y * _w + x].abs(), lessThan(1e-6), reason: '($x, $y)');
    }
  });

  test('não dobra nos dois extremos', () {
    for (final t in [-1.0, 1.0]) {
      expect(_minDetJ(arms(t)), greaterThan(0.5), reason: 't=$t');
    }
  });

  test('sem pulsos não há braço; sem pose, ferramenta indisponível', () {
    expect(
      BodyArmsField.isAvailable(pose: _pose(wrists: false), imageSize: _size),
      isFalse,
    );
    expect(BodyArmsField.isAvailable(pose: pose, imageSize: _size), isTrue);
    expect(
      BodyWarpChain.unavailableKeys(pose: null, imageSize: _size),
      contains(BodyWarpChain.armsKey),
    );
    expect(
      BodyWarpChain.unavailableKeys(
          pose: _pose(wrists: false), imageSize: _size),
      contains(BodyWarpChain.armsKey),
    );
  });

  group('braço levantado e cheio, dobrado no cotovelo (como a body-p04)', () {
    // Ombros a 100 px: meia-largura estimada 14 px, braço real 25 px.
    final raised = PoseResult(
      landmarks: [
        for (var i = 0; i < PoseResult.expectedLandmarkCount; i++)
          PoseLandmark(
            index: i,
            normalized: switch (i) {
              11 => const Offset(200 / _w, 250 / _h),
              12 => const Offset(100 / _w, 250 / _h),
              14 => const Offset(91 / _w, 115 / _h),
              16 => const Offset(190 / _w, 115 / _h),
              _ => const Offset(0.5, 0.5),
            },
            visibility: const {11, 12, 14, 16}.contains(i) ? 0.95 : 0.2,
          ),
      ],
      boundingBox: const Rect.fromLTWH(0.2, 0.1, 0.7, 0.8),
    );
    final bytes = Uint8List(_w * _h);
    void fill(int x0, int x1, int y0, int y1) {
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          bytes[y * _w + x] = 255;
        }
      }
    }

    fill(100, 200, 250, 390); // tronco
    fill(66, 116, 95, 262); // braço, para cima
    fill(66, 200, 95, 135); // antebraço, por cima da cabeça
    final raisedMask = PersonMask(bytes: bytes, width: _w, height: _h);
    DisplacementField field(double t) => BodyArmsField.build(
          pose: raised,
          imageSize: _size,
          mask: raisedMask,
          t: t,
        )!;

    test('a borda de fora do braço cheio mexe', () {
      final f = field(1);
      // Borda de fora em x=66; o braço vai de y≈250 (ombro) a 115.
      expect(f.dx[200 * _w + 66], greaterThan(1.2));
      expect(f.dx[200 * _w + 115], lessThan(-1.2));
    });

    test('sem degrau na bissectriz do cotovelo', () {
      for (final t in [-1.0, 1.0]) {
        final f = field(t);
        var step = 0.0;
        for (var y = 60; y < 300; y++) {
          for (var x = 30; x < 240; x++) {
            final i = y * _w + x;
            for (final j in [i + 1, i + _w]) {
              step = math.max(step, (f.dx[i] - f.dx[j]).abs());
              step = math.max(step, (f.dy[i] - f.dy[j]).abs());
            }
          }
        }
        expect(step, lessThan(0.35), reason: 't=$t');
        expect(_minDetJ(f), greaterThan(0.5), reason: 't=$t');
      }
    });
  });

  test('o slider só reescala o campo em cache', () {
    final runtime = BodyArmsFieldRuntime();
    arms(0.3, runtime);
    final cached = arms(0.9, runtime);
    final fresh = arms(0.9);
    for (var i = 0; i < _w * _h; i++) {
      expect(cached.dx[i], closeTo(fresh.dx[i], 1e-5));
      expect(cached.dy[i], closeTo(fresh.dy[i], 1e-5));
    }
  });
}
