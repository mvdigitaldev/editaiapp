import 'dart:io';
import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/warp/v2/backward_bilinear_warp.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/displacement_field.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _rampX({required int width, required int height}) {
  final rgba = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      rgba[i] = x;
      rgba[i + 1] = y;
      rgba[i + 2] = 128;
      rgba[i + 3] = 255;
    }
  }
  return rgba;
}

List<int> _pixel(Uint8List rgba, int width, int x, int y) {
  final i = (y * width + x) * 4;
  return [rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3]];
}

void main() {
  test('zero field is identity with full coverage', () {
    const width = 6;
    const height = 4;
    final source = _rampX(width: width, height: height);
    final result = BackwardBilinearWarp.apply(
      WarpRequest(
        sourceRgba: source,
        width: width,
        height: height,
        field: DisplacementField.zeros(width: width, height: height),
      ),
    );
    expect(result.rgba, source);
    expect(result.coverage, everyElement(255));
    expect(result.invalidSource, everyElement(0));
  });

  test('campo de suporte compacto não toca o resto da imagem', () {
    const width = 32;
    const height = 24;
    final source = _rampX(width: width, height: height);
    final field = DisplacementField.zeros(width: width, height: height);
    // Suporte num bloco interior, com valor fraccionário para o remap ser
    // interpolado e não uma translação inteira.
    for (var y = 10; y <= 13; y++) {
      for (var x = 12; x <= 17; x++) {
        field.dx[y * width + x] = 1.4;
        field.dy[y * width + x] = -0.7;
      }
    }
    final result = BackwardBilinearWarp.apply(
      WarpRequest(
        sourceRgba: source,
        width: width,
        height: height,
        field: field,
      ),
    );
    // Fora do suporte dilatado de um pixel, o campo e os vizinhos que a
    // jacobiana lê são nulos, logo o destino tem de sair byte a byte igual à
    // fonte. É o que autoriza o remap a nem visitar esses pixels.
    var touchedOutside = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final inSupport = x >= 11 && x <= 18 && y >= 9 && y <= 14;
        if (inSupport) {
          continue;
        }
        final i = (y * width + x) * 4;
        for (var c = 0; c < 4; c++) {
          if (result.rgba[i + c] != source[i + c]) {
            touchedOutside++;
          }
        }
      }
    }
    expect(touchedOutside, 0);
    expect(result.coverage, everyElement(255));
    expect(result.invalidSource, everyElement(0));
    // E dentro do suporte moveu-se de facto.
    expect(_pixel(result.rgba, width, 15, 11),
        isNot(_pixel(source, width, 15, 11)));
  });

  test('integer translation uses src = dest - d in the interior', () {
    const width = 8;
    const height = 4;
    const dx = 3.0;
    final source = _rampX(width: width, height: height);
    final result = BackwardBilinearWarp.apply(
      WarpRequest(
        sourceRgba: source,
        width: width,
        height: height,
        field: DisplacementField.translation(
          width: width,
          height: height,
          dx: dx,
          dy: 0,
        ),
      ),
    );

    for (var y = 0; y < height; y++) {
      for (var x = 3; x < width; x++) {
        final i = y * width + x;
        expect(result.coverage[i], 255, reason: 'valid ($x,$y)');
        expect(result.invalidSource[i], 0);
        expect(
          _pixel(result.rgba, width, x, y),
          _pixel(source, width, x - 3, y),
          reason: 'dest ($x,$y) <- src (${x - 3},$y)',
        );
      }
    }
  });

  test('invalid origin preserves dest and does not clamp to source edge', () {
    const width = 8;
    const height = 4;
    final source = _rampX(width: width, height: height);
    final result = BackwardBilinearWarp.apply(
      WarpRequest(
        sourceRgba: source,
        width: width,
        height: height,
        field: DisplacementField.translation(
          width: width,
          height: height,
          dx: 3,
          dy: 0,
        ),
      ),
    );

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < 3; x++) {
        final i = y * width + x;
        expect(result.invalidSource[i], 1, reason: 'OOB dest ($x,$y)');
        expect(result.coverage[i], 0);
        expect(
          _pixel(result.rgba, width, x, y),
          _pixel(source, width, x, y),
          reason: 'preserved dest ($x,$y)',
        );
      }
      expect(
        _pixel(result.rgba, width, 1, y),
        isNot(_pixel(source, width, 0, y)),
        reason: 'clamp would copy the source left edge onto dest x=1',
      );
    }
  });

  test('rejects rgba size mismatch without remapping', () {
    expect(
      () => BackwardBilinearWarp.apply(
        WarpRequest(
          sourceRgba: Uint8List(3),
          width: 2,
          height: 2,
          field: DisplacementField.zeros(width: 2, height: 2),
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('rgba_buffer_size_mismatch'),
        ),
      ),
    );
  });

  test('rejects field size mismatch', () {
    expect(
      () => BackwardBilinearWarp.apply(
        WarpRequest(
          sourceRgba: _rampX(width: 4, height: 2),
          width: 4,
          height: 2,
          field: DisplacementField.zeros(width: 2, height: 2),
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('displacement_field_size_mismatch'),
        ),
      ),
    );
  });

  test('renderer does not import V1, FaceMesh, controller or UI', () {
    final source = File(
      'lib/features/editor/beauty_engine/warp/v2/backward_bilinear_warp.dart',
    ).readAsStringSync();
    expect(source.contains('extended_roi'), isFalse);
    expect(source.contains('face_mesh'), isFalse);
    expect(source.contains('FaceMesh'), isFalse);
    expect(source.contains('pass_warp'), isFalse);
    expect(source.contains('beauty_engine_controller'), isFalse);
    expect(source.contains('Telea'), isFalse);
    expect(source.contains('inpaint'), isFalse);
    expect(source.contains('jaw'), isFalse);
    expect(source.contains('package:flutter/'), isFalse);
  });
}
