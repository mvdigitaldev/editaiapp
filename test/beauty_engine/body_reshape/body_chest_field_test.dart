import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/filters/body/body_warp_chain.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/backward_bilinear_warp.dart';
import 'package:editaiapp/features/editor/beauty_engine/segment/person_mask.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/body_chest/body_chest_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/body_waist/body_waist_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/displacement_field.dart';
import 'package:flutter_test/flutter_test.dart';

const _w = 300;
const _h = 400;
const _size = Size(300, 400);

/// Ombros a 100 px, tronco de 180 px: centros a 48,6 px abaixo dos ombros,
/// em x = 123 e 177; raio 30 px.
PoseResult _pose({
  Offset left = const Offset(200, 100),
  Offset right = const Offset(100, 100),
  bool shoulders = true,
}) {
  final points = <int, Offset>{
    if (shoulders) 11: left,
    if (shoulders) 12: right,
    23: const Offset(190, 280),
    24: const Offset(110, 280),
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

/// Dois discos de raio 15 nos centros do busto.
Uint8List _bust(List<Offset> centers) {
  final out = Uint8List(_w * _h * 4);
  for (var y = 0; y < _h; y++) {
    for (var x = 0; x < _w; x++) {
      final q = Offset(x + 0.5, y + 0.5);
      final inside = centers.any((c) => (q - c).distance <= 15);
      final i = (y * _w + x) * 4;
      final v = inside ? 255 : 0;
      out[i] = v;
      out[i + 1] = v;
      out[i + 2] = v;
      out[i + 3] = 255;
    }
  }
  return out;
}

double _area(Uint8List rgba) {
  var sum = 0.0;
  for (var i = 0; i < _w * _h; i++) {
    sum += rgba[i * 4] / 255.0;
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

  DisplacementField chest(double t, [BodyChestFieldRuntime? runtime]) =>
      BodyChestField.build(
        pose: pose,
        imageSize: _size,
        t: t,
        runtime: runtime,
      )!;

  test('centros abaixo dos ombros, um por seio', () {
    final g = BodyChestField.measure(pose: pose, imageSize: _size)!;
    expect(g.centers, hasLength(2));
    final xs = g.centers.map((c) => c.dx).toList()..sort();
    expect(xs[0], closeTo(123, 0.5));
    expect(xs[1], closeTo(177, 0.5));
    for (final c in g.centers) {
      expect(c.dy, closeTo(148.6, 0.5));
    }
    expect(g.radius, closeTo(30, 1e-9));
  });

  test('direita aumenta, esquerda diminui', () {
    final g = BodyChestField.measure(pose: pose, imageSize: _size)!;
    final source = _bust(g.centers);
    final before = _area(source);
    double after(double t) => _area(
          BackwardBilinearWarp.apply(
            WarpRequest(
              sourceRgba: source,
              width: _w,
              height: _h,
              field: chest(t),
            ),
          ).rgba,
        );
    expect(after(1), greaterThan(before * 1.08));
    expect(after(-1), lessThan(before * 0.93));
  });

  test('movimento natural: no máximo ≈ 0.29 · R · α', () {
    final f = chest(1);
    var peak = 0.0;
    for (var i = 0; i < _w * _h; i++) {
      peak = math.max(peak, math.sqrt(f.dx[i] * f.dx[i] + f.dy[i] * f.dy[i]));
    }
    final g = BodyChestField.measure(pose: pose, imageSize: _size)!;
    expect(peak, lessThanOrEqualTo(BodyChestField.maxEdgeShift(g) * 1.05));
    expect(peak, greaterThan(0.6));
  });

  test('ombros, esterno acima, cintura e braços ficam parados', () {
    final f = chest(1);
    for (final (x, y) in [(150, 100), (150, 110), (150, 250), (60, 150)]) {
      expect(f.dx[y * _w + x], 0, reason: '($x, $y)');
      expect(f.dy[y * _w + x], 0, reason: '($x, $y)');
    }
  });

  test('não dobra nos dois extremos', () {
    for (final t in [-1.0, 1.0]) {
      expect(_minDetJ(chest(t)), greaterThan(0.6), reason: 't=$t');
    }
  });

  test('sem ombros ou de perfil, indisponível', () {
    expect(
      BodyChestField.isAvailable(
        pose: _pose(shoulders: false),
        imageSize: _size,
      ),
      isFalse,
    );
    expect(
      BodyChestField.isAvailable(
        pose: _pose(
          left: const Offset(165, 100),
          right: const Offset(135, 100),
        ),
        imageSize: _size,
      ),
      isFalse,
    );
    expect(BodyChestField.isAvailable(pose: pose, imageSize: _size), isTrue);
    expect(
      BodyWarpChain.unavailableKeys(pose: null, imageSize: _size),
      contains(BodyWarpChain.chestKey),
    );
  });

  group('largura da silhueta (BodyTorsoBand.chest)', () {
    final bytes = Uint8List(_w * _h);
    for (var y = 90; y < 300; y++) {
      for (var x = 95; x < 205; x++) {
        bytes[y * _w + x] = 255;
      }
    }
    final mask = PersonMask(bytes: bytes, width: _w, height: _h);
    final source = Uint8List(_w * _h * 4);
    for (var i = 0; i < _w * _h; i++) {
      final v = bytes[i];
      source[i * 4] = v;
      source[i * 4 + 1] = v;
      source[i * 4 + 2] = v;
      source[i * 4 + 3] = 255;
    }
    double rowWidth(Uint8List rgba, int y) {
      var sum = 0.0;
      for (var x = 0; x < _w; x++) {
        sum += rgba[(y * _w + x) * 4] / 255.0;
      }
      return sum;
    }

    Uint8List warp(double t) => BackwardBilinearWarp.apply(
          WarpRequest(
            sourceRgba: source,
            width: _w,
            height: _h,
            field: BodyWaistField.build(
              pose: pose,
              imageSize: _size,
              mask: mask,
              t: t,
              band: BodyTorsoBand.chest,
            )!,
          ),
        ).rgba;

    test('direita alarga, esquerda afina, na linha do busto', () {
      // Linha do busto: t = 0.27 → y ≈ 148; borda a 55 px do eixo.
      final before = rowWidth(source, 148);
      expect(rowWidth(warp(1), 148), greaterThan(before + 6));
      expect(rowWidth(warp(-1), 148), lessThan(before - 6));
    });

    test('cintura e ancas ficam', () {
      // t ≥ 0.49 (y ≥ 189): fora da faixa.
      final wide = warp(1);
      for (final y in [195, 250, 290]) {
        expect(rowWidth(wide, y), closeTo(rowWidth(source, y), 1e-6));
      }
    });
  });

  test('o slider só reescala o campo em cache', () {
    final runtime = BodyChestFieldRuntime();
    chest(0.3, runtime);
    final cached = chest(-0.8, runtime);
    final fresh = chest(-0.8);
    for (var i = 0; i < _w * _h; i++) {
      expect(cached.dx[i], closeTo(fresh.dx[i], 1e-5));
      expect(cached.dy[i], closeTo(fresh.dy[i], 1e-5));
    }
  });
}
