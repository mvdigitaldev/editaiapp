import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/filters/body/body_warp_chain.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/segment/person_mask.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/backward_bilinear_warp.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/body_shoulders/body_shoulders_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/displacement_field.dart';
import 'package:flutter_test/flutter_test.dart';

const _w = 300;
const _h = 400;
const _size = Size(300, 400);

/// Ombros a 100 px na linha y = 120; silhueta dos ombros a 62 px do eixo.
PoseResult _pose({
  Offset left = const Offset(200, 120),
  Offset right = const Offset(100, 120),
  bool shoulders = true,
}) {
  final points = <int, Offset>{
    if (shoulders) 11: left,
    if (shoulders) 12: right,
    23: const Offset(190, 300),
    24: const Offset(110, 300),
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

  fill(135, 165, 40, 125); // cabeça e pescoço
  fill(88, 212, 110, 330); // ombros e tronco
  return PersonMask(bytes: bytes, width: _w, height: _h);
}

Uint8List _rgba(PersonMask mask) {
  final out = Uint8List(_w * _h * 4);
  for (var i = 0; i < _w * _h; i++) {
    final v = mask.bytes[i];
    out[i * 4] = v;
    out[i * 4 + 1] = v;
    out[i * 4 + 2] = v;
    out[i * 4 + 3] = 255;
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
  final mask = _mask();
  final source = _rgba(mask);

  DisplacementField shoulders(double t, [BodyShouldersFieldRuntime? rt]) =>
      BodyShouldersField.build(
        pose: pose,
        imageSize: _size,
        mask: mask,
        t: t,
        runtime: rt,
      )!;

  Uint8List warp(DisplacementField f) => BackwardBilinearWarp.apply(
        WarpRequest(sourceRgba: source, width: _w, height: _h, field: f),
      ).rgba;

  test('borda dos ombros medida na máscara', () {
    final g = BodyShouldersField.measure(
      pose: pose,
      imageSize: _size,
      mask: mask,
    )!;
    expect(g.fromMask, isTrue);
    expect(g.edgeLeft, closeTo(62, 1.5));
    expect(g.edgeRight, closeTo(62, 1.5));
  });

  test('direita alarga, esquerda estreita, as duas pontas por igual', () {
    // ≈ 0.035 × 100 px por ponta no extremo.
    final before = _rowWidth(source, 135);
    expect(_rowWidth(warp(shoulders(1)), 135), greaterThan(before + 5));
    expect(_rowWidth(warp(shoulders(-1)), 135), lessThan(before - 5));
    final f = shoulders(1);
    final left = f.dx[135 * _w + 88];
    final right = f.dx[135 * _w + 211];
    expect(left, lessThan(0));
    expect(right, greaterThan(0));
    expect((left.abs() - right.abs()).abs(), lessThan(0.15));
  });

  test('pescoço, cabeça e busto ficam parados', () {
    final f = shoulders(1);
    for (final (x, y) in [(150, 100), (140, 118), (160, 130), (150, 60)]) {
      expect(f.dx[y * _w + x], 0, reason: '($x, $y)');
      expect(f.dy[y * _w + x], 0, reason: '($x, $y)');
    }
    final wide = warp(f);
    for (final y in [185, 250]) {
      expect(_rowWidth(wide, y), closeTo(_rowWidth(source, y), 1e-6));
    }
  });

  test('não dobra nos dois extremos', () {
    for (final t in [-1.0, 1.0]) {
      expect(_minDetJ(shoulders(t)), greaterThan(0.75), reason: 't=$t');
    }
  });

  test('sem ombros ou de perfil, indisponível', () {
    expect(
      BodyShouldersField.isAvailable(
        pose: _pose(shoulders: false),
        imageSize: _size,
      ),
      isFalse,
    );
    expect(
      BodyShouldersField.isAvailable(
        pose: _pose(
          left: const Offset(165, 120),
          right: const Offset(135, 120),
        ),
        imageSize: _size,
      ),
      isFalse,
    );
    expect(
      BodyShouldersField.isAvailable(pose: pose, imageSize: _size),
      isTrue,
    );
    expect(
      BodyWarpChain.unavailableKeys(pose: null, imageSize: _size),
      contains(BodyWarpChain.shouldersKey),
    );
  });

  test('o slider só reescala o campo em cache', () {
    final runtime = BodyShouldersFieldRuntime();
    shoulders(0.3, runtime);
    final cached = shoulders(-0.7, runtime);
    final fresh = shoulders(-0.7);
    for (var i = 0; i < _w * _h; i++) {
      expect(cached.dx[i], closeTo(fresh.dx[i], 1e-5));
      expect(cached.dy[i], closeTo(fresh.dy[i], 1e-5));
    }
  });
}
