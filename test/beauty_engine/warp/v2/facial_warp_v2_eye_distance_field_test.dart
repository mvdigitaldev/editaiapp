import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/eye_distance/eye_distance_field.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../filters/skin/mvp_benchmark_faces.dart';

const _ids = ['real-p01', 'real-p05', 'real-p12'];
const _protectEps = 0.5;
const _coreCeiling = 0.30;
const _entryCeiling = 0.25;

void main() {
  late List<({String id, String label, FaceMeshResult face, Size imageSize})>
      faces;

  setUpAll(() {
    final available = loadAvailableRealBenchmarkFaces();
    faces = [
      for (final id in _ids)
        available.firstWhere(
          (f) => f.id == id,
          orElse: () => throw StateError('missing_real_landmarks: $id'),
        ),
    ];
    expect(faces.length, 3);
  });

  test('t=0 is a null field', () {
    for (final f in faces) {
      final built = EyeDistanceField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0,
      );
      expect(built.field.isZero, isTrue, reason: f.id);
      expect(built.metrics.minDetJ, 1, reason: f.id);
      expect(built.metrics.eyesApart, isFalse, reason: f.id);
      expect(built.metrics.eyesTogether, isFalse, reason: f.id);
    }
  });

  test('t=1 moves both eyes apart as a block; brow and nose stay', () {
    for (final f in faces) {
      final built = EyeDistanceField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 1,
      );
      final m = built.metrics;
      expect(m.eyesApart, isTrue, reason: f.id);
      expect(
        (m.dxAtLidLeft - m.dxAtCenterLeft).abs(),
        lessThan(0.35 * m.dxAtCenterLeft.abs() + _protectEps),
        reason: '${f.id} upper lid moves with the iris',
      );
      expect(
        (m.dxAtLidRight - m.dxAtCenterRight).abs(),
        lessThan(0.35 * m.dxAtCenterRight.abs() + _protectEps),
        reason: '${f.id} upper lid moves with the iris',
      );
      expect(
        (m.dxAtOuterLeft - m.dxAtCenterLeft).abs(),
        lessThan(0.35 * m.dxAtCenterLeft.abs() + _protectEps),
        reason: '${f.id} left eye translates',
      );
      expect(
        (m.dxAtOuterRight - m.dxAtCenterRight).abs(),
        lessThan(0.35 * m.dxAtCenterRight.abs() + _protectEps),
        reason: '${f.id} right eye translates',
      );
      expect(
        m.absAtBrowLeft,
        lessThan(0.25 * m.dxAtCenterLeft.abs() + _protectEps),
        reason: f.id,
      );
      expect(
        m.absAtBrowRight,
        lessThan(0.25 * m.dxAtCenterRight.abs() + _protectEps),
        reason: f.id,
      );
      expect(m.absAtHairline, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.nose.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.mouth.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.influenceMax, lessThan(0.045 * m.faceWidth), reason: f.id);
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');
      expect(m.coreCurvature, lessThan(_coreCeiling), reason: f.id);
      expect(m.entryStep, lessThan(_entryCeiling), reason: f.id);
      var nonzeroDy = 0;
      for (var i = 0; i < built.field.pixelCount; i++) {
        if (built.field.dy[i] != 0) {
          nonzeroDy++;
        }
      }
      expect(nonzeroDy, 0, reason: '${f.id} field is Δx only');
    }
  });

  test('t=-1 brings both eyes together without a fold', () {
    for (final f in faces) {
      final built = EyeDistanceField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: -1,
      );
      final m = built.metrics;
      expect(m.eyesTogether, isTrue, reason: f.id);
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');
      expect(m.coreCurvature, lessThan(_coreCeiling), reason: f.id);
      expect(m.entryStep, lessThan(_entryCeiling), reason: f.id);
      expect(m.nose.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.mouth.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
    }
  });

  test('photo-left t moves the left eye; photo-right t moves the right eye',
      () {
    for (final f in faces) {
      final leftOnly = EyeDistanceField.build(
        face: f.face,
        imageSize: f.imageSize,
        tPhotoLeft: 1,
        tPhotoRight: 0,
      );
      final rightOnly = EyeDistanceField.build(
        face: f.face,
        imageSize: f.imageSize,
        tPhotoLeft: 0,
        tPhotoRight: 1,
      );
      expect(leftOnly.metrics.dxAtCenterLeft, lessThan(-0.4), reason: f.id);
      expect(leftOnly.metrics.dxAtCenterRight.abs(), lessThan(0.4),
          reason: f.id);
      expect(rightOnly.metrics.dxAtCenterRight, greaterThan(0.4), reason: f.id);
      expect(rightOnly.metrics.dxAtCenterLeft.abs(), lessThan(0.4),
          reason: f.id);
      expect(leftOnly.metrics.minDetJ, greaterThan(0));
      expect(rightOnly.metrics.minDetJ, greaterThan(0));
    }
  });

  test('runtime cache scales the same unit weights', () {
    final f = faces.first;
    final runtime = EyeDistanceFieldRuntime();
    final cold = EyeDistanceField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 1,
    );
    final warm = EyeDistanceField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 1,
      runtime: runtime,
    );
    final again = EyeDistanceField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: -1,
      computeMetrics: false,
      runtime: runtime,
    );
    expect(
      warm.metrics.dxAtCenterLeft,
      closeTo(cold.metrics.dxAtCenterLeft, 1e-3),
    );
    expect(identical(again.field, warm.field), isTrue);
    final together = EyeDistanceField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: -1,
    );
    var maxDiff = 0.0;
    for (var i = 0; i < cold.field.pixelCount; i++) {
      maxDiff = math.max(
        maxDiff,
        (again.field.dx[i] - together.field.dx[i]).abs(),
      );
    }
    expect(maxDiff, lessThan(1e-3));
  });

  test('builder API has no image RGBA and does not import other Fields', () {
    const paths = [
      'lib/features/editor/beauty_engine/warp/v2/eye_distance/eye_distance_field.dart',
      'lib/features/editor/beauty_engine/warp/v2/eye_distance/eye_distance_masks.dart',
      'lib/features/editor/beauty_engine/warp/v2/eye_distance/eye_distance_metrics.dart',
    ];
    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source.contains('sourceRgba'), isFalse, reason: path);
      expect(source.contains('backward_bilinear_warp'), isFalse, reason: path);
      expect(source.contains('PersonMask'), isFalse, reason: path);
      expect(source.contains('eye_size'), isFalse, reason: path);
      expect(source.contains('eye_height'), isFalse, reason: path);
      expect(source.contains('eye_width'), isFalse, reason: path);
      expect(source.contains('eye_length'), isFalse, reason: path);
      expect(source.contains('eyebrow_'), isFalse, reason: path);
      expect(source.contains('jaw_field.dart'), isFalse, reason: path);
      expect(source.contains('ridge_weight.dart'), isFalse, reason: path);
    }
  });
}
