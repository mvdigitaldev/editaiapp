import 'dart:io';
import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/warp/v2/displacement_field.dart';
import 'package:flutter_test/flutter_test.dart';

/// Primeiro marco V2.0 — só o buffer do campo. Sem renderer.
void main() {
  test('zeros is per-pixel and empty', () {
    final field = DisplacementField.zeros(width: 4, height: 3);
    expect(field.width, 4);
    expect(field.height, 3);
    expect(field.pixelCount, 12);
    expect(field.dx.length, 12);
    expect(field.dy.length, 12);
    expect(field.isZero, isTrue);
    expect(field.displacementAt(0, 0), Offset.zero);
    expect(field.displacementAt(3, 2), Offset.zero);
  });

  test('translation fills every pixel with the same vector', () {
    final field = DisplacementField.translation(
      width: 5,
      height: 2,
      dx: 3,
      dy: 0,
    );
    expect(field.isZero, isFalse);
    for (var y = 0; y < 2; y++) {
      for (var x = 0; x < 5; x++) {
        expect(field.displacementAt(x, y), const Offset(3, 0));
      }
    }
  });

  test('rejects mismatched buffer lengths', () {
    expect(
      () => DisplacementField(
        width: 2,
        height: 2,
        dx: Float32List(3),
        dy: Float32List(4),
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

  test('rejects non-positive size', () {
    expect(
      () => DisplacementField.zeros(width: 0, height: 8),
      throwsArgumentError,
    );
  });

  test('out-of-range pixel throws, does not clamp', () {
    final field = DisplacementField.zeros(width: 2, height: 2);
    expect(() => field.displacementAt(2, 0), throwsRangeError);
    expect(() => field.displacementAt(-1, 0), throwsRangeError);
  });

  test('field type has no image buffer', () {
    final source = File(
      'lib/features/editor/beauty_engine/warp/v2/displacement_field.dart',
    ).readAsStringSync();
    expect(source.contains('Uint8List'), isFalse);
    expect(source.contains('sourceRgba'), isFalse);
    expect(source.contains('rgba'), isFalse);
  });

  test('field does not import V1 warp or FaceMesh', () {
    final source = File(
      'lib/features/editor/beauty_engine/warp/v2/displacement_field.dart',
    ).readAsStringSync();
    expect(source.contains('extended_roi'), isFalse);
    expect(source.contains('warp_field'), isFalse);
    expect(source.contains('face_mesh'), isFalse);
    expect(source.contains('pass_warp'), isFalse);
    expect(source.contains('beauty_engine_controller'), isFalse);
  });
}
