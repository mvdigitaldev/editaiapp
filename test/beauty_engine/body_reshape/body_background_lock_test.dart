import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/pose_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/segment/person_mask.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/backward_bilinear_warp.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/body_background/body_background_lock.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/body_waist/body_waist_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/displacement_field.dart';
import 'package:flutter_test/flutter_test.dart';

const _w = 200;
const _h = 400;
const _size = Size(200, 400);
const _waistRow = 179;

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

/// Tronco vermelho sobre riscas verticais azul/amarelo de 3 px.
Uint8List _scene(PersonMask mask) {
  final out = Uint8List(_w * _h * 4);
  for (var y = 0; y < _h; y++) {
    for (var x = 0; x < _w; x++) {
      final i = y * _w + x;
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
  }
  return out;
}

bool _isPerson(Uint8List rgba, int i) =>
    rgba[i * 4] > 150 && rgba[i * 4 + 1] < 100 && rgba[i * 4 + 2] < 100;

/// Pessoa (origem ou resultado) a até [radius] px: aí a borda suave e a faixa
/// de guarda reconstruída são legítimas.
bool _nearPerson(PersonMask mask, Uint8List out, int x, int y,
    [int radius = 3]) {
  for (var dx = -radius; dx <= radius; dx++) {
    final nx = x + dx;
    if (nx < 0 || nx >= _w) continue;
    final j = y * _w + nx;
    if (mask.bytes[j] > 127 || _isPerson(out, j)) return true;
  }
  return false;
}

int _personWidth(Uint8List rgba, int y) {
  var count = 0;
  for (var x = 0; x < _w; x++) {
    if (_isPerson(rgba, y * _w + x)) {
      count++;
    }
  }
  return count;
}

Uint8List _warp(Uint8List rgba, DisplacementField field) =>
    BackwardBilinearWarp.apply(
      WarpRequest(sourceRgba: rgba, width: _w, height: _h, field: field),
    ).rgba;

Uint8List _locked(
  Uint8List source,
  PersonMask mask,
  DisplacementField field, {
  BodyBackgroundLockRuntime? runtime,
}) {
  final geometry = BodyWaistField.measure(
    pose: _pose(),
    imageSize: _size,
    mask: mask,
  )!;
  final prepared = BodyBackgroundLock.prepare(
    sourceRgba: source,
    width: _w,
    height: _h,
    mask: mask,
    fields: [field],
    bandPx: BodyWaistField.maxEdgeShift(geometry).ceil() + 6,
    runtime: runtime,
  )!;
  final packed = BodyBackgroundLock.packAlpha(source, prepared);
  return BodyBackgroundLock.composite(
    warpedRgba: _warp(packed, field),
    prepared: prepared,
    fields: [field],
  );
}

int _maxChannelDiff(Uint8List a, Uint8List b, int i) {
  var diff = 0;
  for (var c = 0; c < 4; c++) {
    final d = (a[i * 4 + c] - b[i * 4 + c]).abs();
    if (d > diff) {
      diff = d;
    }
  }
  return diff;
}

void main() {
  final pose = _pose();
  final mask = _mask();
  final source = _scene(mask);

  DisplacementField waist(double t, [BodyWaistFieldRuntime? runtime]) =>
      BodyWaistField.build(
        pose: pose,
        imageSize: _size,
        mask: mask,
        t: t,
        runtime: runtime,
      )!;

  test('com trava o fundo fica igual à origem (afinar e alargar)', () {
    for (final t in [1.0, -1.0]) {
      final out = _locked(source, mask, waist(t));
      var worst = 0;
      for (var y = 0; y < _h; y++) {
        for (var x = 0; x < _w; x++) {
          final i = y * _w + x;
          if (_nearPerson(mask, out, x, y)) {
            continue;
          }
          final d = _maxChannelDiff(out, source, i);
          if (d > worst) {
            worst = d;
          }
        }
      }
      expect(worst, lessThanOrEqualTo(2), reason: 't=$t');
    }
  });

  test('máscara suave com halo largo: o fundo do halo não é arrastado', () {
    // Como o segmentador real: confiança a cair 10 px para fora da pessoa,
    // sempre abaixo de 0.5 no fundo.
    final soft = Uint8List.fromList(mask.bytes);
    for (var y = 50; y < 390; y++) {
      for (var x = 0; x < _w; x++) {
        final i = y * _w + x;
        if (mask.bytes[i] == 255) continue;
        final d = x < 70 ? 70 - x : x - 129;
        final dy = y < 60 ? 60 - y : (y >= 380 ? y - 379 : 0);
        final dist = d > dy ? d : dy;
        if (dist <= 10) {
          soft[i] = (120 * (1 - dist / 11)).round();
        }
      }
    }
    final softMask = PersonMask(bytes: soft, width: _w, height: _h);
    for (final t in [1.0, -1.0]) {
      final field = BodyWaistField.build(
        pose: pose,
        imageSize: _size,
        mask: softMask,
        t: t,
      )!;
      final out = _locked(source, softMask, field);
      var worst = 0;
      // A borda 0.5 da máscara suave cai 1 px para fora: guarda + 1.
      final radius = BodyBackgroundLock.guardPx(_w, _h, softMask) + 1;
      for (var y = 0; y < _h; y++) {
        for (var x = 0; x < _w; x++) {
          if (_nearPerson(mask, out, x, y, radius)) continue;
          final d = _maxChannelDiff(out, source, y * _w + x);
          if (d > worst) worst = d;
        }
      }
      expect(worst, lessThanOrEqualTo(2), reason: 't=$t');
    }
  });

  test('pessoa 2 px fora da máscara: afinar não deixa fantasma', () {
    // O segmentador real erra a borda: a roupa passa um pouco da máscara.
    final wide = Uint8List.fromList(mask.bytes);
    for (var y = 60; y < 380; y++) {
      for (var x = 68; x < 132; x++) {
        wide[y * _w + x] = 255;
      }
    }
    final scene = _scene(PersonMask(bytes: wide, width: _w, height: _h));
    final field = waist(1);
    final plain = _personWidth(_warp(scene, field), _waistRow);
    final out = _locked(scene, mask, field);
    expect(plain, lessThan(_personWidth(scene, _waistRow) - 3));
    expect(_personWidth(out, _waistRow), lessThanOrEqualTo(plain + 1));
    // O buraco é fundo inventado só com fundo: nem vermelho nem rosado.
    for (var x = 0; x < _w; x++) {
      final o = (_waistRow * _w + x) * 4;
      if (_isPerson(out, _waistRow * _w + x)) continue;
      expect(out[o] > 150 && out[o + 1] < 150, isFalse, reason: 'x=$x');
    }
  });

  test('sem trava as riscas junto à cintura deslocam-se', () {
    final out = _warp(source, waist(1));
    var moved = 0;
    for (var x = 135; x < 160; x++) {
      if (_maxChannelDiff(out, source, _waistRow * _w + x) > 40) {
        moved++;
      }
    }
    expect(moved, greaterThan(5));
  });

  test('a cintura afina o mesmo com e sem trava', () {
    final field = waist(1);
    final plain = _personWidth(_warp(source, field), _waistRow);
    final locked = _personWidth(_locked(source, mask, field), _waistRow);
    expect(plain, lessThan(_personWidth(source, _waistRow) - 3));
    expect((locked - plain).abs(), lessThanOrEqualTo(1));
  });

  test('sem halo: o espaço que o corpo deixa não fica vermelho', () {
    final field = waist(1);
    final out = _locked(source, mask, field);
    final plainWidth = _personWidth(_warp(source, field), _waistRow);
    final shrink = (_personWidth(source, _waistRow) - plainWidth) ~/ 2;
    expect(shrink, greaterThan(1));
    for (var dx = 1; dx < shrink; dx++) {
      for (final x in [70 + dx - 1, 129 - dx + 1]) {
        final i = _waistRow * _w + x;
        expect(_isPerson(out, i), isFalse, reason: 'x=$x');
      }
    }
  });

  test('o fundo revelado continua as riscas, não fica embaçado', () {
    final f1 = waist(1);
    final emptyMask = PersonMask(
      bytes: Uint8List(_w * _h),
      width: _w,
      height: _h,
    );
    final out = _locked(source, mask, f1);
    var revealed = 0;
    var sharp = 0;
    var inPhase = 0;
    for (var y = 150; y < 210; y++) {
      for (var x = 60; x < 140; x++) {
        final i = y * _w + x;
        // Só o fundo revelado de facto: a borda anti-aliasing da pessoa
        // (um pixel) mistura-se com ela, como deve.
        if (mask.bytes[i] <= 127 ||
            f1.dx[i].abs() < 1 ||
            _nearPerson(emptyMask, out, x, y, 1)) {
          continue;
        }
        revealed++;
        final r = out[i * 4];
        final g = out[i * 4 + 1];
        final b = out[i * 4 + 2];
        int near(int cr, int cg, int cb) => [
              (r - cr).abs(),
              (g - cg).abs(),
              (b - cb).abs(),
            ].reduce((a, c) => a > c ? a : c);
        final blue = near(20, 40, 230);
        final yellow = near(240, 220, 40);
        if (blue < 50 || yellow < 50) {
          sharp++;
        }
        if ((x ~/ 3).isEven ? blue < 50 : yellow < 50) {
          inPhase++;
        }
      }
    }
    expect(revealed, greaterThan(40));
    // O pull-push sozinho dava a média azul/amarelo em quase todos.
    expect(sharp, greaterThan(0.9 * revealed));
    expect(inPhase, greaterThan(0.8 * revealed));
  });

  test('o fundo limpo não se refaz quando o slider muda', () {
    final fieldRuntime = BodyWaistFieldRuntime();
    final lockRuntime = BodyBackgroundLockRuntime();
    _locked(source, mask, waist(0.4, fieldRuntime), runtime: lockRuntime);
    _locked(source, mask, waist(0.9, fieldRuntime), runtime: lockRuntime);
    _locked(source, mask, waist(-0.6, fieldRuntime), runtime: lockRuntime);
    expect(lockRuntime.builds, 1);
    expect(lockRuntime.prepared!.filled, greaterThan(0));
  });

  test('o canal A sai a 255', () {
    final out = _locked(source, mask, waist(1));
    for (var i = 3; i < out.length; i += 4) {
      expect(out[i], 255);
    }
  });
}
