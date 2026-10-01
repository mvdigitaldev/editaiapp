import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/pose_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/segment/person_mask.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/backward_bilinear_warp.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/body_waist/body_waist_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/displacement_field.dart';
import 'package:flutter_test/flutter_test.dart';

const _w = 200;
const _h = 400;
const _size = Size(200, 400);

/// Tronco 70–130 px, ombros y=100, quadril y=220.
PoseResult _pose() {
  final points = <int, Offset>{
    11: const Offset(70 / _w, 100 / _h),
    12: const Offset(130 / _w, 100 / _h),
    23: const Offset(85 / _w, 220 / _h),
    24: const Offset(115 / _w, 220 / _h),
  };
  return PoseResult(
    landmarks: [
      for (var i = 0; i < PoseResult.expectedLandmarkCount; i++)
        PoseLandmark(
          index: i,
          normalized: points[i] ?? const Offset(0.5, 0.5),
          visibility: points.containsKey(i) ? 0.95 : 0.2,
        ),
    ],
    boundingBox: const Rect.fromLTWH(0.2, 0.1, 0.6, 0.8),
  );
}

PersonMask _mask() {
  final bytes = Uint8List(_w * _h);
  for (var y = 60; y < 380; y++) {
    for (var x = 70; x < 130; x++) {
      bytes[y * _w + x] = 255;
    }
  }
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

int _rowWidth(Uint8List rgba, int y) {
  var count = 0;
  for (var x = 0; x < _w; x++) {
    if (rgba[(y * _w + x) * 4] > 127) {
      count++;
    }
  }
  return count;
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
  final rgba = _rgba(mask);
  const waistRow = 179; // t = 0.66 do eixo 100→220

  test('mede as bordas da silhueta na máscara', () {
    final g = BodyWaistField.measure(pose: pose, imageSize: _size, mask: mask)!;
    expect(g.fromMask, isTrue);
    for (var k = 0; k < g.tSamples.length; k++) {
      expect(g.edgeLeft[k], closeTo(30, 1.5));
      expect(g.edgeRight[k], closeTo(30, 1.5));
    }
  });

  test('direita afina a cintura, esquerda alarga', () {
    final slim = BodyWaistField.build(
      pose: pose,
      imageSize: _size,
      mask: mask,
      t: 1,
    )!;
    final wide = BodyWaistField.build(
      pose: pose,
      imageSize: _size,
      mask: mask,
      t: -1,
    )!;
    final before = _rowWidth(rgba, waistRow);
    final slimRgba = BackwardBilinearWarp.apply(
      WarpRequest(sourceRgba: rgba, width: _w, height: _h, field: slim),
    ).rgba;
    final wideRgba = BackwardBilinearWarp.apply(
      WarpRequest(sourceRgba: rgba, width: _w, height: _h, field: wide),
    ).rgba;
    expect(_rowWidth(slimRgba, waistRow), lessThanOrEqualTo(before - 4));
    expect(_rowWidth(wideRgba, waistRow), greaterThanOrEqualTo(before + 4));
  });

  test('ombros, coxas e cabeça não se mexem', () {
    final f = BodyWaistField.build(
      pose: pose,
      imageSize: _size,
      mask: mask,
      t: 1,
    )!;
    for (final y in [40, 100, 250, 350]) {
      for (var x = 0; x < _w; x++) {
        expect(f.dx[y * _w + x], 0, reason: 'y=$y x=$x');
        expect(f.dy[y * _w + x], 0, reason: 'y=$y x=$x');
      }
    }
  });

  test('não dobra nos dois extremos', () {
    for (final t in [-1.0, 1.0]) {
      final f = BodyWaistField.build(
        pose: pose,
        imageSize: _size,
        mask: mask,
        t: t,
      )!;
      expect(_minDetJ(f), greaterThan(0.5), reason: 't=$t');
    }
  });

  test('o slider só reescala o campo em cache', () {
    final runtime = BodyWaistFieldRuntime();
    BodyWaistField.build(
      pose: pose,
      imageSize: _size,
      mask: mask,
      t: 0.3,
      runtime: runtime,
    );
    final cached = BodyWaistField.build(
      pose: pose,
      imageSize: _size,
      mask: mask,
      t: 0.8,
      runtime: runtime,
    )!;
    final fresh = BodyWaistField.build(
      pose: pose,
      imageSize: _size,
      mask: mask,
      t: 0.8,
    )!;
    for (var i = 0; i < _w * _h; i++) {
      expect(cached.dx[i], closeTo(fresh.dx[i], 1e-5));
      expect(cached.dy[i], closeTo(fresh.dy[i], 1e-5));
    }
  });

  test('sem pose fiável ou com slider em zero não há campo', () {
    expect(
      BodyWaistField.build(pose: pose, imageSize: _size, mask: mask, t: 0),
      isNull,
    );
    final blind = PoseResult(
      landmarks: [
        for (final l in pose.landmarks)
          PoseLandmark(index: l.index, normalized: l.normalized, visibility: 0),
      ],
      boundingBox: pose.boundingBox,
    );
    expect(
      BodyWaistField.build(pose: blind, imageSize: _size, mask: mask, t: 1),
      isNull,
    );
  });

  test('sem máscara a borda vem da pose', () {
    final g = BodyWaistField.measure(pose: pose, imageSize: _size)!;
    expect(g.fromMask, isFalse);
    final f = BodyWaistField.build(pose: pose, imageSize: _size, t: 1)!;
    expect(f.isZero, isFalse);
  });
}
