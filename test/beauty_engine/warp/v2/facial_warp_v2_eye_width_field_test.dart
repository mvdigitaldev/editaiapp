import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/eye_width/eye_width_field.dart';
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
      final built = EyeWidthField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0,
      );
      expect(built.field.isZero, isTrue, reason: f.id);
      expect(built.metrics.minDetJ, 1, reason: f.id);
      expect(built.metrics.eyesWiden, isFalse, reason: f.id);
      expect(built.metrics.eyesNarrow, isFalse, reason: f.id);
    }
  });

  test('t=1 widens both eyes in x only; iris, brow and nose stay', () {
    for (final f in faces) {
      final built = EyeWidthField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 1,
      );
      final m = built.metrics;
      expect(m.eyesWiden, isTrue, reason: f.id);
      expect(m.absAtCenterLeft, lessThan(1.2), reason: '${f.id} iris stays');
      expect(m.absAtCenterRight, lessThan(1.2), reason: '${f.id} iris stays');
      expect(
        m.absAtBrowLeft,
        lessThan(0.25 * m.horizontalAtOuterLeft.abs() + _protectEps),
        reason: f.id,
      );
      expect(
        m.absAtBrowRight,
        lessThan(0.25 * m.horizontalAtOuterRight.abs() + _protectEps),
        reason: f.id,
      );
      expect(m.absAtHairline, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.nose.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.mouth.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.influenceMax, lessThan(0.06 * m.faceWidth), reason: f.id);
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

  test('t=-1 narrows both eyes without a fold', () {
    for (final f in faces) {
      final built = EyeWidthField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: -1,
      );
      final m = built.metrics;
      expect(m.eyesNarrow, isTrue, reason: f.id);
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
      final leftOnly = EyeWidthField.build(
        face: f.face,
        imageSize: f.imageSize,
        tPhotoLeft: 1,
        tPhotoRight: 0,
      );
      final rightOnly = EyeWidthField.build(
        face: f.face,
        imageSize: f.imageSize,
        tPhotoLeft: 0,
        tPhotoRight: 1,
      );
      expect(leftOnly.metrics.horizontalAtOuterLeft, greaterThan(0.4),
          reason: f.id);
      expect(leftOnly.metrics.horizontalAtOuterRight.abs(), lessThan(0.4),
          reason: f.id);
      expect(rightOnly.metrics.horizontalAtOuterRight, greaterThan(0.4),
          reason: f.id);
      expect(rightOnly.metrics.horizontalAtOuterLeft.abs(), lessThan(0.4),
          reason: f.id);
      expect(leftOnly.metrics.minDetJ, greaterThan(0));
      expect(rightOnly.metrics.minDetJ, greaterThan(0));
    }
  });

  test('runtime cache scales the same unit weights', () {
    final f = faces.first;
    final runtime = EyeWidthFieldRuntime();
    final cold = EyeWidthField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 1,
    );
    final warm = EyeWidthField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 1,
      runtime: runtime,
    );
    final again = EyeWidthField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: -1,
      computeMetrics: false,
      runtime: runtime,
    );
    expect(
      warm.metrics.horizontalAtOuterLeft,
      closeTo(cold.metrics.horizontalAtOuterLeft, 1e-3),
    );
    expect(identical(again.field, warm.field), isTrue);
    final narrowed = EyeWidthField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: -1,
    );
    var maxDiff = 0.0;
    for (var i = 0; i < cold.field.pixelCount; i++) {
      maxDiff = math.max(
        maxDiff,
        (again.field.dx[i] - narrowed.field.dx[i]).abs(),
      );
    }
    expect(maxDiff, lessThan(1e-3));
  });

  test('builder API has no image RGBA and does not import other Fields', () {
    const paths = [
      'lib/features/editor/beauty_engine/warp/v2/eye_width/eye_width_field.dart',
      'lib/features/editor/beauty_engine/warp/v2/eye_width/eye_width_masks.dart',
      'lib/features/editor/beauty_engine/warp/v2/eye_width/eye_width_metrics.dart',
    ];
    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source.contains('sourceRgba'), isFalse, reason: path);
      expect(source.contains('backward_bilinear_warp'), isFalse, reason: path);
      expect(source.contains('PersonMask'), isFalse, reason: path);
      expect(source.contains('eye_size'), isFalse, reason: path);
      expect(source.contains('eye_height'), isFalse, reason: path);
      expect(source.contains('eyebrow_'), isFalse, reason: path);
      expect(source.contains('jaw_field.dart'), isFalse, reason: path);
      expect(source.contains('ridge_weight.dart'), isFalse, reason: path);
    }
  });
}
