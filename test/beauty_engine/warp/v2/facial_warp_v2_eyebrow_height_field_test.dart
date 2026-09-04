import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/eyebrow_height/eyebrow_height_field.dart';
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
      final built = EyebrowHeightField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0,
      );
      expect(built.field.isZero, isTrue, reason: f.id);
      expect(built.metrics.influenceMax, 0, reason: f.id);
      expect(built.metrics.minDetJ, 1, reason: f.id);
      expect(built.metrics.browsLift, isFalse, reason: f.id);
      expect(built.metrics.browsDrop, isFalse, reason: f.id);
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

  test('t=0.5 lifts both brows (dy < 0), dx only zero, lids stay', () {
    for (final f in faces) {
      final built = EyebrowHeightField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0.5,
      );
      final m = built.metrics;
      expect(built.field.isZero, isFalse, reason: f.id);
      expect(m.browsLift, isTrue, reason: f.id);
      expect(m.browsDrop, isFalse, reason: f.id);
      expect(m.dyAtPrimaryLeft, lessThan(0), reason: '${f.id} 334 up');
      expect(m.dyAtPrimaryRight, lessThan(0), reason: '${f.id} 105 up');
      expect(
        m.dyAtPrimaryLeft.abs(),
        greaterThan(0.012 * m.faceWidth),
        reason: '${f.id} visible lift at 334',
      );
      expect(
        m.dyAtPrimaryRight.abs(),
        greaterThan(0.012 * m.faceWidth),
        reason: '${f.id} visible lift at 105',
      );
      expect(m.dyAtLowerLeft, lessThan(0), reason: '${f.id} 282 follows');
      expect(m.dyAtLowerRight, lessThan(0), reason: '${f.id} 52 follows');
      expect(
        m.dxAtPrimaryLeft.abs(),
        lessThanOrEqualTo(_protectEps),
        reason: f.id,
      );
      expect(
        m.dxAtPrimaryRight.abs(),
        lessThanOrEqualTo(_protectEps),
        reason: f.id,
      );
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');
      expect(m.coreCurvature, lessThan(_coreCeiling), reason: f.id);
      expect(m.entryStep, lessThan(_entryCeiling), reason: f.id);
      expect(m.outsideBrowZoneP95, lessThanOrEqualTo(_protectEps),
          reason: f.id);
      expect(m.eyes.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.mouth.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.nose.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtHairline, lessThanOrEqualTo(_protectEps), reason: f.id);
      final peak = math.max(m.dyAtPrimaryLeft.abs(), m.dyAtPrimaryRight.abs());
      expect(
        m.absAtLidLeft,
        lessThanOrEqualTo(0.30 * peak + 1e-6),
        reason: '${f.id} lid 386 ${m.absAtLidLeft} vs 30% of $peak',
      );
      expect(
        m.absAtLidRight,
        lessThanOrEqualTo(0.30 * peak + 1e-6),
        reason: '${f.id} lid 159 ${m.absAtLidRight} vs 30% of $peak',
      );
      expect(
        m.absAtOuterCreaseLeft,
        lessThanOrEqualTo(0.20 * peak + 1e-6),
        reason:
            '${f.id} outer crease ${m.absAtOuterCreaseLeft} vs 20% of $peak',
      );
      expect(
        m.absAtOuterCreaseRight,
        lessThanOrEqualTo(0.20 * peak + 1e-6),
        reason:
            '${f.id} outer crease ${m.absAtOuterCreaseRight} vs 20% of $peak',
      );

      var nonzeroDx = 0;
      for (var i = 0; i < built.field.pixelCount; i++) {
        if (built.field.dx[i] != 0) {
          nonzeroDx++;
        }
      }
      expect(nonzeroDx, 0, reason: '${f.id} field is Δy only');
    }
    for (final f in faces) {
      final atFull = EyebrowHeightField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 1,
      );
      expect(
        atFull.metrics.minDetJ,
        greaterThan(0),
        reason: '${f.id} fold at t=1 detJ=${atFull.metrics.minDetJ}',
      );
      expect(
        atFull.metrics.coreCurvature,
        lessThan(_coreCeiling),
        reason: '${f.id} t=1 vinco=${atFull.metrics.coreCurvature}',
      );
      expect(
        atFull.metrics.entryStep,
        lessThan(_entryCeiling),
        reason: '${f.id} t=1 degrau=${atFull.metrics.entryStep}',
      );
    }
  });

  test('t=-0.5 drops both brows (dy > 0), dx only zero', () {
    for (final f in faces) {
      final built = EyebrowHeightField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: -0.5,
      );
      final m = built.metrics;
      expect(m.browsDrop, isTrue, reason: f.id);
      expect(m.browsLift, isFalse, reason: f.id);
      expect(m.dyAtPrimaryLeft, greaterThan(0), reason: '${f.id} 334 down');
      expect(m.dyAtPrimaryRight, greaterThan(0), reason: '${f.id} 105 down');
      expect(m.dyAtLowerLeft, greaterThan(0), reason: '${f.id} 282 down');
      expect(m.dyAtLowerRight, greaterThan(0), reason: '${f.id} 52 down');
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');
      expect(m.coreCurvature, lessThan(_coreCeiling), reason: f.id);
      expect(m.entryStep, lessThan(_entryCeiling), reason: f.id);
      expect(m.eyes.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);

      var nonzeroDx = 0;
      for (var i = 0; i < built.field.pixelCount; i++) {
        if (built.field.dx[i] != 0) {
          nonzeroDx++;
        }
      }
      expect(nonzeroDx, 0, reason: '${f.id} field is Δy only');
    }
    for (final f in faces) {
      final atFullDrop = EyebrowHeightField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: -1,
      );
      expect(
        atFullDrop.metrics.minDetJ,
        greaterThan(0),
        reason: '${f.id} fold at t=-1 detJ=${atFullDrop.metrics.minDetJ}',
      );
    }
  });

  test('photo-left t moves MediaPipe 105; photo-right t moves 334', () {
    for (final f in faces) {
      final leftOnly = EyebrowHeightField.build(
        face: f.face,
        imageSize: f.imageSize,
        tPhotoLeft: 0.5,
        tPhotoRight: 0,
      );
      final rightOnly = EyebrowHeightField.build(
        face: f.face,
        imageSize: f.imageSize,
        tPhotoLeft: 0,
        tPhotoRight: 0.5,
      );
      expect(
        leftOnly.metrics.dyAtPrimaryRight.abs(),
        greaterThan(leftOnly.metrics.dyAtPrimaryLeft.abs() + 0.15),
        reason: '${f.id} Esquerda should move 105, not 334',
      );
      expect(
        rightOnly.metrics.dyAtPrimaryLeft.abs(),
        greaterThan(rightOnly.metrics.dyAtPrimaryRight.abs() + 0.15),
        reason: '${f.id} Direita should move 334, not 105',
      );
      expect(leftOnly.metrics.dyAtPrimaryRight, lessThan(0), reason: f.id);
      expect(rightOnly.metrics.dyAtPrimaryLeft, lessThan(0), reason: f.id);
      expect(leftOnly.metrics.minDetJ, greaterThan(0), reason: f.id);
      expect(rightOnly.metrics.minDetJ, greaterThan(0), reason: f.id);
    }
  });

  test('runtime cache scales the same unit weights', () {
    final f = faces.first;
    final runtime = EyebrowHeightFieldRuntime();
    final cold = EyebrowHeightField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 0.5,
    );
    final warm = EyebrowHeightField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 0.5,
      runtime: runtime,
    );
    final again = EyebrowHeightField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 0.5,
      computeMetrics: false,
      runtime: runtime,
    );
    expect(
      warm.metrics.dyAtPrimaryLeft,
      closeTo(cold.metrics.dyAtPrimaryLeft, 1e-4),
    );
    expect(
      warm.metrics.dyAtPrimaryRight,
      closeTo(cold.metrics.dyAtPrimaryRight, 1e-4),
    );
    expect(identical(again.field, warm.field), isTrue);
    var maxDiff = 0.0;
    for (var i = 0; i < cold.field.pixelCount; i++) {
      maxDiff = math.max(
        maxDiff,
        (again.field.dy[i] - cold.field.dy[i]).abs(),
      );
    }
    expect(maxDiff, lessThan(1e-4));
  });

  test('builder API has no image RGBA and does not import other Fields', () {
    const paths = [
      'lib/features/editor/beauty_engine/warp/v2/eyebrow_height/eyebrow_height_field.dart',
      'lib/features/editor/beauty_engine/warp/v2/eyebrow_height/eyebrow_height_masks.dart',
      'lib/features/editor/beauty_engine/warp/v2/eyebrow_height/eyebrow_height_metrics.dart',
    ];
    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source.contains('sourceRgba'), isFalse, reason: path);
      expect(source.contains('backward_bilinear_warp'), isFalse, reason: path);
      expect(source.contains('extended_roi'), isFalse, reason: path);
      expect(source.contains('VertexRoleMap'), isFalse, reason: path);
      expect(source.contains('FaceWarpUtils'), isFalse, reason: path);
      expect(source.contains('PersonMask'), isFalse, reason: path);
      expect(source.contains('Telea'), isFalse, reason: path);
      expect(source.contains('pass_warp'), isFalse, reason: path);
      expect(source.contains('beauty_engine_controller'), isFalse,
          reason: path);
      expect(source.contains('jaw_field.dart'), isFalse, reason: path);
      expect(source.contains('chin_field.dart'), isFalse, reason: path);
      expect(source.contains('hairline_field.dart'), isFalse, reason: path);
      expect(source.contains('head_field.dart'), isFalse, reason: path);
      expect(source.contains('ridge_weight.dart'), isFalse, reason: path);
    }
  });
}
