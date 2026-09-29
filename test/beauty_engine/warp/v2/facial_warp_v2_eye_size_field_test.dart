import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/eye_size/eye_size_field.dart';
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
      final built = EyeSizeField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0,
      );
      expect(built.field.isZero, isTrue, reason: f.id);
      expect(built.metrics.influenceMax, 0, reason: f.id);
      expect(built.metrics.minDetJ, 1, reason: f.id);
      expect(built.metrics.eyesEnlarge, isFalse, reason: f.id);
      expect(built.metrics.eyesShrink, isFalse, reason: f.id);
    }
  });

  test('t=1 enlarges both eyes; brows, nose and mouth stay', () {
    for (final f in faces) {
      final built = EyeSizeField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 1,
      );
      final m = built.metrics;
      expect(m.eyesEnlarge, isTrue, reason: f.id);
      expect(m.absAtCenterLeft, lessThan(1.2), reason: '${f.id} iris stays');
      expect(m.absAtCenterRight, lessThan(1.2), reason: '${f.id} iris stays');
      expect(
        m.absAtBrowLeft,
        lessThan(0.25 * m.radialAtOuterLeft.abs() + _protectEps),
        reason: '${f.id} brow stays',
      );
      expect(
        m.absAtBrowRight,
        lessThan(0.25 * m.radialAtOuterRight.abs() + _protectEps),
        reason: '${f.id} brow stays',
      );
      expect(m.absAtHairline, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.nose.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.mouth.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.influenceMax, lessThan(0.08 * m.faceWidth), reason: f.id);
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');
      expect(m.coreCurvature, lessThan(_coreCeiling), reason: f.id);
      expect(m.entryStep, lessThan(_entryCeiling), reason: f.id);
    }
  });

  test('t=-1 shrinks both eyes without a fold', () {
    for (final f in faces) {
      final built = EyeSizeField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: -1,
      );
      final m = built.metrics;
      expect(m.eyesShrink, isTrue, reason: f.id);
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
      final leftOnly = EyeSizeField.build(
        face: f.face,
        imageSize: f.imageSize,
        tPhotoLeft: 1,
        tPhotoRight: 0,
      );
      final rightOnly = EyeSizeField.build(
        face: f.face,
        imageSize: f.imageSize,
        tPhotoLeft: 0,
        tPhotoRight: 1,
      );
      expect(leftOnly.metrics.radialAtOuterLeft, greaterThan(0.4),
          reason: f.id);
      expect(
        leftOnly.metrics.radialAtOuterRight.abs(),
        lessThan(0.4),
        reason: '${f.id} right eye stays',
      );
      expect(rightOnly.metrics.radialAtOuterRight, greaterThan(0.4),
          reason: f.id);
      expect(
        rightOnly.metrics.radialAtOuterLeft.abs(),
        lessThan(0.4),
        reason: '${f.id} left eye stays',
      );
      expect(leftOnly.metrics.minDetJ, greaterThan(0));
      expect(rightOnly.metrics.minDetJ, greaterThan(0));
    }
  });

  test('runtime cache scales the same unit vectors', () {
    final f = faces.first;
    final runtime = EyeSizeFieldRuntime();
    final cold = EyeSizeField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 1,
    );
    final warm = EyeSizeField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 1,
      runtime: runtime,
    );
    final again = EyeSizeField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: -1,
      computeMetrics: false,
      runtime: runtime,
    );
    expect(
      warm.metrics.radialAtOuterLeft,
      closeTo(cold.metrics.radialAtOuterLeft, 1e-3),
    );
    expect(identical(again.field, warm.field), isTrue);
    final shrunk = EyeSizeField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: -1,
    );
    var maxDiff = 0.0;
    for (var i = 0; i < cold.field.pixelCount; i++) {
      maxDiff = math.max(
        maxDiff,
        math.max(
          (again.field.dx[i] - shrunk.field.dx[i]).abs(),
          (again.field.dy[i] - shrunk.field.dy[i]).abs(),
        ),
      );
    }
    expect(maxDiff, lessThan(1e-3));
  });

  test('builder API has no image RGBA and does not import other Fields', () {
    const paths = [
      'lib/features/editor/beauty_engine/warp/v2/eye_size/eye_size_field.dart',
      'lib/features/editor/beauty_engine/warp/v2/eye_size/eye_size_masks.dart',
      'lib/features/editor/beauty_engine/warp/v2/eye_size/eye_size_metrics.dart',
    ];
    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source.contains('sourceRgba'), isFalse, reason: path);
      expect(source.contains('backward_bilinear_warp'), isFalse, reason: path);
      expect(source.contains('PersonMask'), isFalse, reason: path);
      expect(source.contains('eyebrow_'), isFalse, reason: path);
      expect(source.contains('jaw_field.dart'), isFalse, reason: path);
      expect(source.contains('head_field.dart'), isFalse, reason: path);
      expect(source.contains('ridge_weight.dart'), isFalse, reason: path);
      expect(source.contains('eye_scale'), isFalse, reason: path);
    }
  });
}
