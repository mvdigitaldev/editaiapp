import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/filters/body/body_warp_chain.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/segment/person_mask.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/backward_bilinear_warp.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/body_background/body_background_lock.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/body_legs/body_legs_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/displacement_field.dart';
import 'package:flutter_test/flutter_test.dart';

const _w = 300;
const _h = 600;
const _size = Size(300, 600);

/// Linha com vão largo entre as pernas (s ≈ 0.59).
const _openRow = 420;

/// Linha com as coxas encostadas (s ≈ 0.21).
const _touchRow = 310;

PoseResult _pose({double hipVisibility = 0.95}) {
  final points = <int, Offset>{
    23: const Offset(180 / _w, 250 / _h),
    24: const Offset(120 / _w, 250 / _h),
    25: const Offset(180 / _w, 395 / _h),
    26: const Offset(120 / _w, 395 / _h),
    27: const Offset(180 / _w, 540 / _h),
    28: const Offset(120 / _w, 540 / _h),
  };
  return PoseResult(
    landmarks: [
      for (var i = 0; i < PoseResult.expectedLandmarkCount; i++)
        PoseLandmark(
          index: i,
          normalized: points[i] ?? const Offset(0.5, 0.5),
          visibility: points.containsKey(i)
              ? (i == 23 || i == 24 ? hipVisibility : 0.95)
              : 0.2,
        ),
    ],
    boundingBox: const Rect.fromLTWH(0.2, 0.1, 0.6, 0.85),
  );
}

/// Bacia, coxas encostadas até y=340, depois duas pernas de 40 px com vão de
/// 20 px, e pés.
PersonMask _mask() {
  final bytes = Uint8List(_w * _h);
  void fill(int x0, int x1, int y0, int y1) {
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        bytes[y * _w + x] = 255;
      }
    }
  }

  fill(90, 210, 150, 290);
  fill(95, 205, 290, 340);
  fill(100, 140, 340, 540);
  fill(160, 200, 340, 540);
  fill(95, 145, 540, 580);
  fill(155, 205, 540, 580);
  return PersonMask(bytes: bytes, width: _w, height: _h);
}

Uint8List _scene(PersonMask mask) {
  final out = Uint8List(_w * _h * 4);
  for (var i = 0; i < _w * _h; i++) {
    final x = i % _w;
    final o = i * 4;
    if (mask.bytes[i] > 127) {
      out[o] = 220;
      out[o + 1] = 30;
      out[o + 2] = 30;
    } else if ((x ~/ 3).isEven) {
      out[o] = 20;
      out[o + 1] = 40;
      out[o + 2] = 230;
    } else {
      out[o] = 240;
      out[o + 1] = 220;
      out[o + 2] = 40;
    }
    out[o + 3] = 255;
  }
  return out;
}

bool _isPerson(Uint8List rgba, int i) =>
    rgba[i * 4] > 150 && rgba[i * 4 + 1] < 100 && rgba[i * 4 + 2] < 100;

/// Bordas (sub-pixel, pela cor) da perna que cobre [probeX] na linha [y].
({double left, double right}) _legEdges(Uint8List rgba, int y, int probeX) {
  double personness(int x) {
    final o = (y * _w + x) * 4;
    return ((rgba[o + 1] - 220).abs() < 1 && rgba[o] < 30)
        ? 0
        : (1 - (rgba[o + 1] - 30) / 190).clamp(0.0, 1.0);
  }

  var x = probeX;
  while (x > 0 && _isPerson(rgba, y * _w + x - 1)) {
    x--;
  }
  final left = x - personness(x - 1);
  x = probeX;
  while (x < _w - 1 && _isPerson(rgba, y * _w + x + 1)) {
    x++;
  }
  final right = x + 1 + personness(x + 1);
  return (left: left, right: right);
}

Uint8List _warp(Uint8List rgba, DisplacementField field) =>
    BackwardBilinearWarp.apply(
      WarpRequest(sourceRgba: rgba, width: _w, height: _h, field: field),
    ).rgba;

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
  final source = _scene(mask);

  DisplacementField legs(double t, [BodyLegsFieldRuntime? runtime]) =>
      BodyLegsField.build(
        pose: pose,
        imageSize: _size,
        mask: mask,
        t: t,
        runtime: runtime,
      )!;

  test('mede as duas pernas na máscara', () {
    final g = BodyLegsField.measure(pose: pose, imageSize: _size, mask: mask)!;
    expect(g.fromMask, isTrue);
    expect(g.legs, hasLength(2));
    for (final leg in g.legs) {
      final k = (0.59 * (BodyLegsField.sampleCount - 1)).round();
      expect((leg.outer[k] - leg.inner[k]).abs(), closeTo(40, 2));
      expect(leg.gap[k], closeTo(20, 2));
    }
  });

  test('direita afina as duas pernas por igual dos dois lados', () {
    final out = _warp(source, legs(1));
    for (final probe in [120, 180]) {
      final before = _legEdges(source, _openRow, probe);
      final after = _legEdges(out, _openRow, probe);
      final moveLeft = after.left - before.left;
      final moveRight = before.right - after.right;
      expect(moveLeft, greaterThan(1.5), reason: 'perna $probe');
      expect(moveRight, greaterThan(1.5), reason: 'perna $probe');
      expect((moveLeft - moveRight).abs(), lessThan(0.75),
          reason: 'perna $probe: $moveLeft vs $moveRight');
    }
  });

  test('esquerda engrossa as duas pernas por igual dos dois lados', () {
    final out = _warp(source, legs(-1));
    for (final probe in [120, 180]) {
      final before = _legEdges(source, _openRow, probe);
      final after = _legEdges(out, _openRow, probe);
      final moveLeft = before.left - after.left;
      final moveRight = after.right - before.right;
      expect(moveLeft, greaterThan(1.5), reason: 'perna $probe');
      expect(moveRight, greaterThan(1.5), reason: 'perna $probe');
      expect((moveLeft - moveRight).abs(), lessThan(0.75),
          reason: 'perna $probe: $moveLeft vs $moveRight');
    }
  });

  test('coxas encostadas: a linha de contacto fica, as bordas de fora andam',
      () {
    for (final t in [1.0, -1.0]) {
      final out = _warp(source, legs(t));
      for (var x = 146; x <= 154; x++) {
        expect(_isPerson(out, _touchRow * _w + x), isTrue, reason: 't=$t x=$x');
      }
      final before = _legEdges(source, _touchRow, 150);
      final after = _legEdges(out, _touchRow, 150);
      if (t > 0) {
        expect(after.left, greaterThan(before.left + 1));
        expect(after.right, lessThan(before.right - 1));
      } else {
        expect(after.left, lessThan(before.left - 1));
        expect(after.right, greaterThan(before.right + 1));
      }
    }
  });

  test('anca e pés não se mexem', () {
    final f = legs(1);
    for (final y in [200, 250, 560, 590]) {
      for (var x = 0; x < _w; x++) {
        expect(f.dx[y * _w + x], 0, reason: 'y=$y x=$x');
        expect(f.dy[y * _w + x], 0, reason: 'y=$y x=$x');
      }
    }
  });

  test('não dobra nos dois extremos', () {
    for (final t in [-1.0, 1.0]) {
      expect(_minDetJ(legs(t)), greaterThan(0.3), reason: 't=$t');
    }
  });

  test('o slider só reescala o campo em cache', () {
    final runtime = BodyLegsFieldRuntime();
    legs(0.3, runtime);
    final cached = legs(-0.7, runtime);
    final fresh = legs(-0.7);
    for (var i = 0; i < _w * _h; i++) {
      expect(cached.dx[i], closeTo(fresh.dx[i], 1e-5));
      expect(cached.dy[i], closeTo(fresh.dy[i], 1e-5));
    }
  });

  test('sem ancas visíveis ou com slider em zero não há campo', () {
    expect(
      BodyLegsField.build(pose: pose, imageSize: _size, mask: mask, t: 0),
      isNull,
    );
    expect(
      BodyLegsField.build(
        pose: _pose(hipVisibility: 0.1),
        imageSize: _size,
        mask: mask,
        t: 1,
      ),
      isNull,
    );
  });

  test('foto cortada acima do joelho: sem campo (não mexe nas mãos na anca)',
      () {
    // Recorta a 330 px: o MediaPipe extrapola joelho e tornozelo para fora.
    const cropped = Size(300, 330);
    final base = _pose();
    final crop = PoseResult(
      landmarks: [
        for (final l in base.landmarks)
          PoseLandmark(
            index: l.index,
            normalized: Offset(l.normalized.dx, l.normalized.dy * 600 / 330),
            visibility: l.visibility,
          ),
      ],
      boundingBox: base.boundingBox,
    );
    final bytes = Uint8List(300 * 330)..setRange(0, 300 * 330, mask.bytes);
    final croppedMask = PersonMask(bytes: bytes, width: 300, height: 330);
    for (final band in [
      BodyLegBand.legs,
      BodyLegBand.thighs,
      BodyLegBand.calves,
    ]) {
      expect(
        BodyLegsField.build(
          pose: crop,
          imageSize: cropped,
          mask: croppedMask,
          t: 1,
          band: band,
        ),
        isNull,
      );
    }
  });

  PoseResult moved(Map<int, Offset> pixels, {Size size = _size}) {
    final base = _pose();
    return PoseResult(
      landmarks: [
        for (final l in base.landmarks)
          PoseLandmark(
            index: l.index,
            normalized: pixels.containsKey(l.index)
                ? Offset(
                    pixels[l.index]!.dx / size.width,
                    pixels[l.index]!.dy / size.height,
                  )
                : Offset(
                    l.normalized.dx * _size.width / size.width,
                    l.normalized.dy * _size.height / size.height,
                  ),
            visibility: pixels.containsKey(l.index) ? 0.95 : l.visibility,
          ),
      ],
      boundingBox: base.boundingBox,
    );
  }

  test('joelho posto pelo MediaPipe colado à borda de baixo: sem campo', () {
    const cropped = Size(300, 330);
    final bytes = Uint8List(300 * 330)..setRange(0, 300 * 330, mask.bytes);
    final croppedMask = PersonMask(bytes: bytes, width: 300, height: 330);
    final pose = moved(
      const {
        25: Offset(180, 320),
        26: Offset(120, 320),
        27: Offset(180, 420),
        28: Offset(120, 420),
      },
      size: cropped,
    );
    expect(
      BodyLegsField.build(
        pose: pose,
        imageSize: cropped,
        mask: croppedMask,
        t: 1,
      ),
      isNull,
    );
  });

  group('foto cortada acima do joelho, com ombros (como a body-p02)', () {
    // Tronco de 230 px; a foto acaba 80 px abaixo das ancas.
    const cropped = Size(300, 330);
    final bytes = Uint8List(300 * 330)..setRange(0, 300 * 330, mask.bytes);
    final croppedMask = PersonMask(bytes: bytes, width: 300, height: 330);
    final pose = moved(
      const {
        11: Offset(110, 20),
        12: Offset(190, 20),
        25: Offset(180, 320),
        26: Offset(120, 320),
        27: Offset(180, 420),
        28: Offset(120, 420),
      },
      size: cropped,
    );

    test('Pernas indisponível, Coxas disponível', () {
      expect(
        BodyLegsField.isAvailable(pose: pose, imageSize: cropped),
        isFalse,
      );
      expect(
        BodyLegsField.isAvailable(
          pose: pose,
          imageSize: cropped,
          band: BodyLegBand.thighs,
        ),
        isTrue,
      );
      expect(
        BodyWarpChain.unavailableKeys(
          pose: pose,
          imageSize: cropped,
        ).intersection(BodyWarpChain.legParameterKeys.toSet()),
        {'legs', 'calves'},
      );
      expect(
        BodyWarpChain.unavailableKeys(pose: null, imageSize: cropped),
        {'legs', 'thighs', 'calves', 'arms', 'chest', 'shoulders'},
      );
    });

    test('Coxas usa o joelho estimado pelo tronco e mexe pouco', () {
      final g = BodyLegsField.measure(
        pose: pose,
        imageSize: cropped,
        mask: croppedMask,
        band: BodyLegBand.thighs,
      )!;
      for (final leg in g.legs) {
        // Joelho a 0.95 × 230 px abaixo das ancas, a meio do eixo.
        expect(leg.ankle.dy, closeTo(250 + 2 * 0.95 * 230, 1));
        expect(leg.kneeS, closeTo(0.5, 1e-9));
      }
      final field = BodyLegsField.build(
        pose: pose,
        imageSize: cropped,
        mask: croppedMask,
        t: 1,
        band: BodyLegBand.thighs,
      )!;
      var peak = 0.0;
      for (var i = 0; i < field.dx.length; i++) {
        peak = peak > field.dx[i].abs() ? peak : field.dx[i].abs();
      }
      expect(peak, greaterThan(0.2));
      expect(peak,
          lessThanOrEqualTo(BodyLegsField.maxEdgeShift(g, BodyLegBand.thighs)));
    });
  });

  test('Coxas tem metade do ganho das Pernas', () {
    expect(BodyLegBand.thighs.gain, closeTo(BodyLegBand.legs.gain / 2, 1e-12));
  });

  test('joelho na foto mas sem canela nem tornozelo: Pernas indisponível', () {
    // Corte 35 px abaixo do joelho (0,24 da coxa); tornozelos fora.
    const cropped = Size(300, 430);
    final pose = moved(const {}, size: cropped);
    expect(BodyLegsField.isAvailable(pose: pose, imageSize: cropped), isFalse);
    // Com a canela quase toda à vista (corte em 0,7 da coxa abaixo do joelho).
    const tall = Size(300, 500);
    final tallPose = moved(const {}, size: tall);
    expect(BodyLegsField.isAvailable(pose: tallPose, imageSize: tall), isTrue);
  });

  test('coxa curta para o tronco (joelho inventado): sem campo', () {
    final shortThigh = moved(const {
      11: Offset(110, 20),
      12: Offset(190, 20),
      25: Offset(180, 330),
      26: Offset(120, 330),
    });
    expect(
      BodyLegsField.build(
        pose: shortThigh,
        imageSize: _size,
        mask: mask,
        t: 1,
      ),
      isNull,
    );
    final normal = moved(const {
      11: Offset(110, 20),
      12: Offset(190, 20),
    });
    expect(
      BodyLegsField.build(pose: normal, imageSize: _size, mask: mask, t: 1),
      isNotNull,
    );
  });

  test('com trava o fundo entre as pernas fica parado', () {
    for (final t in [1.0, -1.0]) {
      final field = legs(t);
      final geometry =
          BodyLegsField.measure(pose: pose, imageSize: _size, mask: mask)!;
      final prepared = BodyBackgroundLock.prepare(
        sourceRgba: source,
        width: _w,
        height: _h,
        mask: mask,
        fields: [field],
        bandPx: BodyLegsField.maxEdgeShift(geometry).ceil() + 6,
      )!;
      final out = BodyBackgroundLock.composite(
        warpedRgba:
            _warp(BodyBackgroundLock.packAlpha(source, prepared), field),
        prepared: prepared,
        fields: [field],
      );
      final plain = _warp(source, field);
      var lockedWorst = 0;
      var plainWorst = 0;
      for (var y = 350; y < 530; y++) {
        for (var x = 0; x < _w; x++) {
          var near = false;
          for (var dx = -3; dx <= 3 && !near; dx++) {
            final nx = (x + dx).clamp(0, _w - 1);
            final j = y * _w + nx;
            near =
                mask.bytes[j] > 127 || _isPerson(out, j) || _isPerson(plain, j);
          }
          if (near) continue;
          for (var c = 0; c < 3; c++) {
            final i = (y * _w + x) * 4 + c;
            final dl = (out[i] - source[i]).abs();
            final dp = (plain[i] - source[i]).abs();
            if (dl > lockedWorst) lockedWorst = dl;
            if (dp > plainWorst) plainWorst = dp;
          }
        }
      }
      expect(lockedWorst, lessThanOrEqualTo(2), reason: 't=$t');
      expect(plainWorst, greaterThan(40), reason: 't=$t sem trava estica');
    }
  });

  group('Coxas', () {
    DisplacementField thighs(double t, [BodyLegsFieldRuntime? runtime]) =>
        BodyLegsField.build(
          pose: pose,
          imageSize: _size,
          mask: mask,
          t: t,
          band: BodyLegBand.thighs,
          runtime: runtime,
        )!;

    /// Coxa com vão aberto (s ≈ 0.38, faixa no máximo).
    const thighRow = 360;

    /// Joelho (s = 0.5) e canela (s ≈ 0.66, já fora da cauda).
    const kneeRow = 395;
    const shinRow = 440;

    double edgeMove(Uint8List out, int y, int probe) {
      final before = _legEdges(source, y, probe);
      final after = _legEdges(out, y, probe);
      return ((after.left - before.left) + (before.right - after.right)) / 2;
    }

    test('mede o joelho no eixo de cada perna', () {
      final g =
          BodyLegsField.measure(pose: pose, imageSize: _size, mask: mask)!;
      for (final leg in g.legs) {
        expect(leg.kneeS, closeTo(0.5, 0.01));
      }
    });

    test('direita afina a coxa por igual dos dois lados', () {
      final out = _warp(source, thighs(1));
      for (final probe in [120, 180]) {
        final before = _legEdges(source, thighRow, probe);
        final after = _legEdges(out, thighRow, probe);
        final moveLeft = after.left - before.left;
        final moveRight = before.right - after.right;
        // Metade do ganho das Pernas: ≈ 0.06 × 20 px por borda.
        expect(moveLeft, greaterThan(0.6), reason: 'coxa $probe');
        expect(moveRight, greaterThan(0.6), reason: 'coxa $probe');
      }
    });

    test('as duas bordas de cada coxa andam o mesmo (no campo)', () {
      final f = thighs(1);
      for (final (lo, hi) in [(100, 139), (160, 199)]) {
        final a = f.dx[thighRow * _w + lo];
        final b = f.dx[thighRow * _w + hi];
        expect(a.sign, -b.sign, reason: 'perna $lo..$hi encolhe para dentro');
        expect((a.abs() - b.abs()).abs(), lessThan(0.1 * a.abs()),
            reason: 'perna $lo..$hi: $a vs $b');
      }
    });

    test('esquerda engrossa a coxa', () {
      final out = _warp(source, thighs(-1));
      for (final probe in [120, 180]) {
        expect(edgeMove(out, thighRow, probe), lessThan(-0.6),
            reason: 'coxa $probe');
      }
    });

    test('desce suave até um pouco abaixo do joelho e pára', () {
      final f = thighs(1);
      final out = _warp(source, f);
      for (final probe in [120, 180]) {
        expect(edgeMove(out, kneeRow, probe), greaterThan(0.1),
            reason: 'joelho ainda mexe um pouco');
      }
      // Na borda de fora de cada perna, no campo (sub-pixel exacto).
      for (final x in [100, 199]) {
        final atThigh = f.dx[thighRow * _w + x].abs();
        final atKnee = f.dx[kneeRow * _w + x].abs();
        expect(atKnee, lessThan(atThigh * 0.75),
            reason: 'x=$x joelho mexe menos');
      }
      for (final y in [shinRow, 480, 560, 200]) {
        for (var x = 0; x < _w; x++) {
          expect(f.dx[y * _w + x], 0, reason: 'y=$y x=$x');
          expect(f.dy[y * _w + x], 0, reason: 'y=$y x=$x');
        }
      }
    });

    test('não dobra nos dois extremos', () {
      for (final t in [-1.0, 1.0]) {
        expect(_minDetJ(thighs(t)), greaterThan(0.3), reason: 't=$t');
      }
    });

    test('o slider só reescala e não se mistura com o cache das Pernas', () {
      final runtime = BodyLegsFieldRuntime();
      legs(0.5, runtime);
      final cached = thighs(0.8, runtime);
      final fresh = thighs(0.8);
      for (var i = 0; i < _w * _h; i++) {
        expect(cached.dx[i], closeTo(fresh.dx[i], 1e-5));
        expect(cached.dy[i], closeTo(fresh.dy[i], 1e-5));
      }
      final again = thighs(-0.3, runtime);
      expect(identical(again, cached), isTrue);
    });
  });

  group('Canelas', () {
    DisplacementField calves(double t, [BodyLegsFieldRuntime? runtime]) =>
        BodyLegsField.build(
          pose: pose,
          imageSize: _size,
          mask: mask,
          t: t,
          band: BodyLegBand.calves,
          runtime: runtime,
        )!;

    /// Joelho s = 0.5 (y = 395), tornozelo s = 1 (y = 540).
    /// Barriga da perna s ≈ 0.71 (y = 455), no máximo da faixa.
    const calfRow = 455;

    test('a faixa vai da barriga da perna e pára antes do tornozelo', () {
      final f = calves(1);
      // Coxa, tornozelo e pé parados.
      for (final y in [_openRow - 60, 360, 530, 560]) {
        for (var x = 0; x < _w; x++) {
          expect(f.dx[y * _w + x], 0, reason: 'y=$y x=$x');
          expect(f.dy[y * _w + x], 0, reason: 'y=$y x=$x');
        }
      }
      expect(f.dx[calfRow * _w + 100].abs(), greaterThan(0.5));
    });

    test('direita afina a canela, esquerda engrossa', () {
      final slim = _warp(source, calves(1));
      final wide = _warp(source, calves(-1));
      for (final probe in [120, 180]) {
        final before = _legEdges(source, calfRow, probe);
        final a = _legEdges(slim, calfRow, probe);
        final b = _legEdges(wide, calfRow, probe);
        expect(a.right - a.left, lessThan(before.right - before.left - 1.5),
            reason: 'perna $probe afina');
        expect(b.right - b.left, greaterThan(before.right - before.left + 1.5),
            reason: 'perna $probe engrossa');
      }
    });

    test('natural: as duas bordas andam o mesmo e pouco', () {
      final f = calves(1);
      for (final (lo, hi) in [(100, 139), (160, 199)]) {
        final a = f.dx[calfRow * _w + lo];
        final b = f.dx[calfRow * _w + hi];
        expect(a.sign, -b.sign);
        expect((a.abs() - b.abs()).abs(), lessThan(0.1 * a.abs()));
        // Cada borda anda ≈ 0.07 × meia-largura (20 px): ≈ 1.4 px.
        expect(a.abs(), lessThan(2.0));
      }
    });

    test('não dobra nos dois extremos', () {
      for (final t in [-1.0, 1.0]) {
        expect(_minDetJ(calves(t)), greaterThan(0.3), reason: 't=$t');
      }
    });

    test('o slider só reescala e o cache não se mistura com as Coxas', () {
      final runtime = BodyLegsFieldRuntime();
      BodyLegsField.build(
        pose: pose,
        imageSize: _size,
        mask: mask,
        t: 0.5,
        band: BodyLegBand.thighs,
        runtime: runtime,
      );
      final cached = calves(0.8, runtime);
      final fresh = calves(0.8);
      for (var i = 0; i < _w * _h; i++) {
        expect(cached.dx[i], closeTo(fresh.dx[i], 1e-5));
      }
    });
  });
}
