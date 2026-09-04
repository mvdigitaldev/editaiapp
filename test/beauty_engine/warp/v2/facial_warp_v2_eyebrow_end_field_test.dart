import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/eyebrow_end/eyebrow_end_field.dart';
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
    for (final f in faces) {
      expect(f.face.landmarks.length, 478, reason: f.id);
    }
  });

  test('t=0 is a null field with identity metrics', () {
    for (final f in faces) {
      final built = EyebrowEndField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0,
      );
      expect(built.field.isZero, isTrue, reason: f.id);
      expect(built.metrics.influenceMax, 0, reason: f.id);
      expect(built.metrics.minDetJ, 1, reason: f.id);
      expect(built.metrics.browsSeparate, isFalse, reason: f.id);
      expect(built.metrics.browsJoin, isFalse, reason: f.id);
      expect(built.metrics.eyes.p95Abs, 0, reason: f.id);
      expect(built.metrics.mouth.p95Abs, 0, reason: f.id);
      expect(built.metrics.outsideBrowZoneP95, 0, reason: f.id);
      expect(
        built.masks.count(built.masks.browActive),
        greaterThan(0),
        reason: f.id,
      );
    }
  });

  test('t=0.5 separates inner heads; tails and lids stay; subtle', () {
    for (final f in faces) {
      final built = EyebrowEndField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0.5,
      );
      final m = built.metrics;
      expect(built.field.isZero, isFalse, reason: f.id);
      expect(m.browsSeparate, isTrue, reason: f.id);
      expect(m.browsJoin, isFalse, reason: f.id);
      expect(m.dxAtInnerLeft, greaterThan(0), reason: '${f.id} 336 out');
      expect(m.dxAtInnerRight, lessThan(0), reason: '${f.id} 107 out');
      expect(
        m.dxAtInnerLeft.abs(),
        greaterThan(0.0015 * m.faceWidth),
        reason: '${f.id} visible at 336',
      );
      expect(
        m.dxAtInnerRight.abs(),
        greaterThan(0.0015 * m.faceWidth),
        reason: '${f.id} visible at 107',
      );
      expect(
        m.dxAtTailLeft.abs(),
        lessThan(0.25 * m.dxAtInnerLeft.abs() + 1e-6),
        reason: '${f.id} tail 300 stays',
      );
      expect(
        m.dxAtTailRight.abs(),
        lessThan(0.25 * m.dxAtInnerRight.abs() + 1e-6),
        reason: '${f.id} tail 70 stays',
      );
      expect(
        m.dxAtArchLeft.abs(),
        lessThan(0.45 * m.dxAtInnerLeft.abs() + 1e-6),
        reason: '${f.id} arch 334 quieter than inner',
      );
      expect(
        m.influenceMax,
        lessThan(0.040 * m.faceWidth),
        reason: '${f.id} must stay subtle',
      );
      expect(m.dyAtInnerLeft.abs(), lessThanOrEqualTo(_protectEps));
      expect(m.dyAtInnerRight.abs(), lessThanOrEqualTo(_protectEps));
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');
      expect(m.coreCurvature, lessThan(_coreCeiling), reason: f.id);
      expect(m.entryStep, lessThan(_entryCeiling), reason: f.id);
      expect(m.outsideBrowZoneP95, lessThanOrEqualTo(_protectEps));
      expect(m.eyes.p95Abs, lessThanOrEqualTo(_protectEps));
      expect(m.mouth.p95Abs, lessThanOrEqualTo(_protectEps));
      expect(m.nose.p95Abs, lessThanOrEqualTo(_protectEps));
      expect(m.absAtHairline, lessThanOrEqualTo(_protectEps));
      final peak = math.max(m.dxAtInnerLeft.abs(), m.dxAtInnerRight.abs());
      expect(m.absAtLidLeft, lessThanOrEqualTo(0.30 * peak + 1e-6));
      expect(m.absAtLidRight, lessThanOrEqualTo(0.30 * peak + 1e-6));
      expect(m.absAtOuterCreaseLeft, lessThanOrEqualTo(0.20 * peak + 1e-6));
      expect(m.absAtOuterCreaseRight, lessThanOrEqualTo(0.20 * peak + 1e-6));

      var nonzeroDy = 0;
      for (var i = 0; i < built.field.pixelCount; i++) {
        if (built.field.dy[i] != 0) {
          nonzeroDy++;
        }
      }
      expect(nonzeroDy, 0, reason: '${f.id} field is Δx only');
    }
    for (final f in faces) {
      final atFull = EyebrowEndField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 1,
      );
      expect(atFull.metrics.minDetJ, greaterThan(0), reason: f.id);
      expect(atFull.metrics.coreCurvature, lessThan(_coreCeiling));
      expect(atFull.metrics.entryStep, lessThan(_entryCeiling));
      expect(
        atFull.metrics.influenceMax,
        lessThan(0.040 * atFull.metrics.faceWidth),
        reason: '${f.id} t=1 still subtle',
      );
    }
  });

  test('t=-0.5 joins inner heads', () {
    for (final f in faces) {
      final built = EyebrowEndField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: -0.5,
      );
      final m = built.metrics;
      expect(m.browsJoin, isTrue, reason: f.id);
      expect(m.browsSeparate, isFalse, reason: f.id);
      expect(m.dxAtInnerLeft, lessThan(0), reason: '${f.id} 336 in');
      expect(m.dxAtInnerRight, greaterThan(0), reason: '${f.id} 107 in');
      expect(m.minDetJ, greaterThan(0), reason: f.id);
      expect(m.eyes.p95Abs, lessThanOrEqualTo(_protectEps));
    }
    for (final f in faces) {
      final atFull = EyebrowEndField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: -1,
      );
      expect(atFull.metrics.minDetJ, greaterThan(0), reason: f.id);
    }
  });

  test('photo-left t moves MediaPipe 107; photo-right t moves 336', () {
    for (final f in faces) {
      final leftOnly = EyebrowEndField.build(
        face: f.face,
        imageSize: f.imageSize,
        tPhotoLeft: 0.5,
        tPhotoRight: 0,
      );
      final rightOnly = EyebrowEndField.build(
        face: f.face,
        imageSize: f.imageSize,
        tPhotoLeft: 0,
        tPhotoRight: 0.5,
      );
      expect(
        leftOnly.metrics.dxAtInnerRight.abs(),
        greaterThan(leftOnly.metrics.dxAtInnerLeft.abs() + 0.15),
        reason: '${f.id} Esquerda should move 107, not 336',
      );
      expect(
        rightOnly.metrics.dxAtInnerLeft.abs(),
        greaterThan(rightOnly.metrics.dxAtInnerRight.abs() + 0.15),
        reason: '${f.id} Direita should move 336, not 107',
      );
      expect(leftOnly.metrics.dxAtInnerRight, lessThan(0), reason: f.id);
      expect(rightOnly.metrics.dxAtInnerLeft, greaterThan(0), reason: f.id);
      expect(leftOnly.metrics.minDetJ, greaterThan(0));
      expect(rightOnly.metrics.minDetJ, greaterThan(0));
    }
  });

  test('runtime cache scales the same unit weights', () {
    final f = faces.first;
    final runtime = EyebrowEndFieldRuntime();
    final cold = EyebrowEndField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 0.5,
    );
    final warm = EyebrowEndField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 0.5,
      runtime: runtime,
    );
    final again = EyebrowEndField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 0.5,
      computeMetrics: false,
      runtime: runtime,
    );
    expect(
      warm.metrics.dxAtInnerLeft,
      closeTo(cold.metrics.dxAtInnerLeft, 1e-4),
    );
    expect(
      warm.metrics.dxAtInnerRight,
      closeTo(cold.metrics.dxAtInnerRight, 1e-4),
    );
    expect(identical(again.field, warm.field), isTrue);
    var maxDiff = 0.0;
    for (var i = 0; i < cold.field.pixelCount; i++) {
      maxDiff = math.max(
        maxDiff,
        (again.field.dx[i] - cold.field.dx[i]).abs(),
      );
    }
    expect(maxDiff, lessThan(1e-4));
  });

  test('builder API has no image RGBA and does not import other Fields', () {
    const paths = [
      'lib/features/editor/beauty_engine/warp/v2/eyebrow_end/eyebrow_end_field.dart',
      'lib/features/editor/beauty_engine/warp/v2/eyebrow_end/eyebrow_end_masks.dart',
      'lib/features/editor/beauty_engine/warp/v2/eyebrow_end/eyebrow_end_metrics.dart',
    ];
    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source.contains('sourceRgba'), isFalse, reason: path);
      expect(source.contains('backward_bilinear_warp'), isFalse, reason: path);
      expect(source.contains('PersonMask'), isFalse, reason: path);
      expect(source.contains('beauty_engine_controller'), isFalse);
      expect(source.contains('jaw_field.dart'), isFalse, reason: path);
      expect(source.contains('eyebrow_height_field.dart'), isFalse,
          reason: path);
      expect(source.contains('eyebrow_width_field.dart'), isFalse,
          reason: path);
      expect(source.contains('ridge_weight.dart'), isFalse, reason: path);
    }
  });
}
