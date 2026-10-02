import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/filters/body/body_warp_chain.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/backward_bilinear_warp.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/body_neck/body_neck_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/displacement_field.dart';
import 'package:flutter_test/flutter_test.dart';

const _w = 300;
const _h = 400;
const _size = Size(300, 400);

/// Ombros a 100 px em y = 200, boca em (150, 90): eixo de 110 px, pescoço de
/// meia-largura 17 px.
PoseResult _pose({bool face = true}) {
  final points = <int, Offset>{
    11: const Offset(200, 200),
    12: const Offset(100, 200),
    if (face) 0: const Offset(150, 70),
    if (face) 9: const Offset(158, 90),
    if (face) 10: const Offset(142, 90),
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

/// Pescoço branco (x 133–167) entre a cara e os ombros.
Uint8List _scene() {
  final out = Uint8List(_w * _h * 4);
  for (var y = 0; y < _h; y++) {
    for (var x = 0; x < _w; x++) {
      final neck = y >= 100 && y < 200 && x >= 133 && x < 167;
      final v = neck ? 255 : 0;
      final o = (y * _w + x) * 4;
      out[o] = v;
      out[o + 1] = v;
      out[o + 2] = v;
      out[o + 3] = 255;
    }
  }
  return out;
}

double _rowWidth(Uint8List rgba, int y) {
  var sum = 0.0;
  for (var x = 0; x < _w; x++) {
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
      minDet = math.min(minDet, (1 - dxx) * (1 - dyy) - dxy * dyx);
    }
  }
  return minDet;
}

void main() {
  final pose = _pose();
  final source = _scene();

  DisplacementField neck(double t, [BodyNeckFieldRuntime? runtime]) =>
      BodyNeckField.build(
        pose: pose,
        imageSize: _size,
        t: t,
        runtime: runtime,
      )!;

  Uint8List warp(DisplacementField f) => BackwardBilinearWarp.apply(
        WarpRequest(sourceRgba: source, width: _w, height: _h, field: f),
      ).rgba;

  test('eixo dos ombros à boca', () {
    final g = BodyNeckField.measure(pose: pose, imageSize: _size)!;
    expect(g.length, closeTo(110, 1e-6));
    expect(g.halfWidth, closeTo(17, 1e-6));
  });

  test('direita afina, esquerda engrossa', () {
    // v = 0.35 → y ≈ 161; cada borda anda 0.15 × 17 ≈ 2.5 px.
    final before = _rowWidth(source, 161);
    expect(_rowWidth(warp(neck(1)), 161), lessThan(before - 4));
    expect(_rowWidth(warp(neck(-1)), 161), greaterThan(before + 4));
    final f = neck(1);
    expect(f.dx[161 * _w + 133], greaterThan(0));
    expect(f.dx[161 * _w + 166], lessThan(0));
  });

  test('cara, ombros e o que fica ao lado não mexem', () {
    final f = neck(1);
    for (final (x, y) in [(150, 115), (140, 100), (150, 201), (190, 160)]) {
      expect(f.dx[y * _w + x], 0, reason: '($x, $y)');
      expect(f.dy[y * _w + x], 0, reason: '($x, $y)');
    }
  });

  test('não dobra nos dois extremos', () {
    for (final t in [-1.0, 1.0]) {
      expect(_minDetJ(neck(t)), greaterThan(0.6), reason: 't=$t');
    }
  });

  test('sem cara na pose, indisponível', () {
    expect(
      BodyNeckField.isAvailable(pose: _pose(face: false), imageSize: _size),
      isFalse,
    );
    expect(BodyNeckField.isAvailable(pose: pose, imageSize: _size), isTrue);
    expect(
      BodyWarpChain.unavailableKeys(pose: null, imageSize: _size),
      contains(BodyWarpChain.neckKey),
    );
  });

  test('o slider só reescala o campo em cache', () {
    final runtime = BodyNeckFieldRuntime();
    neck(0.3, runtime);
    final cached = neck(-0.6, runtime);
    final fresh = neck(-0.6);
    for (var i = 0; i < _w * _h; i++) {
      expect(cached.dx[i], closeTo(fresh.dx[i], 1e-5));
      expect(cached.dy[i], closeTo(fresh.dy[i], 1e-5));
    }
  });
}
