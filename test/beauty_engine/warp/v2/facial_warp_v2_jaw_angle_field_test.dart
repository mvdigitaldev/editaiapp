import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/jaw_angle/jaw_angle_field.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../filters/skin/mvp_benchmark_faces.dart';

const _ids = ['real-p01', 'real-p05', 'real-p12'];
const _protectEps = 0.5;

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
      final built = JawAngleField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0,
      );
      expect(built.field.isZero, isTrue, reason: f.id);
      expect(built.metrics.influenceMax, 0, reason: f.id);
      expect(built.metrics.minDetJ, 1, reason: f.id);
      expect(built.metrics.jawLifts, isFalse, reason: f.id);
      expect(built.metrics.jawDrops, isFalse, reason: f.id);
      expect(built.metrics.eyes.p95Abs, 0, reason: f.id);
      expect(built.metrics.mouth.p95Abs, 0, reason: f.id);
      expect(built.metrics.outsideChinZoneP95, 0, reason: f.id);
      expect(
        built.masks.count(built.masks.chinActive),
        greaterThan(0),
        reason: f.id,
      );
    }
  });

  test('t=0.5 lifts gonion 58/288 (dy < 0), dx only zero, chin sides follow', () {
    for (final f in faces) {
      final built = JawAngleField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0.5,
      );
      final m = built.metrics;
      expect(built.field.isZero, isFalse, reason: f.id);
      expect(m.jawLifts, isTrue, reason: f.id);
      expect(m.jawDrops, isFalse, reason: f.id);
      expect(
        m.dyAtPrimaryLeft,
        lessThan(0),
        reason: '${f.id} t>0 should lift MP 58 (dy < 0)',
      );
      expect(
        m.dyAtPrimaryRight,
        lessThan(0),
        reason: '${f.id} t>0 should lift MP 288 (dy < 0)',
      );
      expect(
        m.dyAtPrimaryLeft.abs(),
        greaterThan(0.012 * m.faceWidth),
        reason: '${f.id} visible lift at 58 (${m.dyAtPrimaryLeft.abs()} vs 0.012×${m.faceWidth})',
      );
      expect(
        m.dyAtPrimaryRight.abs(),
        greaterThan(0.012 * m.faceWidth),
        reason: '${f.id} visible lift at 288',
      );
      expect(m.dxAtPrimaryLeft.abs(), lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.dxAtPrimaryRight.abs(), lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(
        m.absAtChinSoproLeft,
        greaterThan(0.22 * m.dyAtPrimaryLeft.abs()),
        reason: '${f.id} 172 must follow (no chin lock)',
      );
      expect(
        m.absAtChinSoproLeft,
        lessThan(m.dyAtPrimaryLeft.abs()),
        reason: '${f.id} 172 < pico 58',
      );
      expect(
        m.absAtChinSoproRight,
        greaterThan(0.22 * m.dyAtPrimaryRight.abs()),
        reason: '${f.id} 397 must follow',
      );
      expect(
        m.absAtChinTip,
        lessThan(m.absAtChinSoproLeft),
        reason: '${f.id} 152 softer than chin side, not Chin Length',
      );
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');
      expect(m.outsideChinZoneP95, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.eyes.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.mouth.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.jawDomain.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);

      var nonzeroDx = 0;
      for (var i = 0; i < built.field.pixelCount; i++) {
        if (built.field.dx[i] != 0) {
          nonzeroDx++;
        }
      }
      expect(nonzeroDx, 0, reason: '${f.id} field is Δy only');
    }
    for (final f in faces) {
      final atFull = JawAngleField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 1,
      );
      expect(
        atFull.metrics.minDetJ,
        greaterThan(0),
        reason: '${f.id} fold at t=1 detJ=${atFull.metrics.minDetJ}',
      );
    }
  });

  test('t=-0.5 drops gonion 58/288 (dy > 0), dx only zero', () {
    for (final f in faces) {
      final built = JawAngleField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: -0.5,
      );
      final m = built.metrics;
      expect(m.jawDrops, isTrue, reason: f.id);
      expect(m.jawLifts, isFalse, reason: f.id);
      expect(m.dyAtPrimaryLeft, greaterThan(0), reason: '${f.id} 58 down');
      expect(m.dyAtPrimaryRight, greaterThan(0), reason: '${f.id} 288 down');
      expect(
        m.absAtChinSoproLeft,
        greaterThan(0.22 * m.dyAtPrimaryLeft.abs()),
        reason: '${f.id} 172 must follow (no chin lock)',
      );
      expect(
        m.absAtChinSoproLeft,
        lessThan(m.dyAtPrimaryLeft.abs()),
        reason: '${f.id} 172 < pico 58',
      );
      expect(
        m.absAtChinTip,
        lessThan(m.absAtChinSoproLeft),
        reason: '${f.id} 152 softer than chin side',
      );
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');

      var nonzeroDx = 0;
      for (var i = 0; i < built.field.pixelCount; i++) {
        if (built.field.dx[i] != 0) {
          nonzeroDx++;
        }
      }
      expect(nonzeroDx, 0, reason: '${f.id} field is Δy only');
    }
    for (final f in faces) {
      final atFullDrop = JawAngleField.build(
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

  test('photo-left t moves MediaPipe 288; photo-right t moves 58', () {
    for (final f in faces) {
      final leftOnly = JawAngleField.build(
        face: f.face,
        imageSize: f.imageSize,
        tPhotoLeft: 0.5,
        tPhotoRight: 0,
      );
      final rightOnly = JawAngleField.build(
        face: f.face,
        imageSize: f.imageSize,
        tPhotoLeft: 0,
        tPhotoRight: 0.5,
      );
      expect(
        leftOnly.metrics.dyAtPrimaryRight.abs(),
        greaterThan(leftOnly.metrics.dyAtPrimaryLeft.abs() + 0.15),
        reason: '${f.id} Esquerda should move 288, not 58',
      );
      expect(
        rightOnly.metrics.dyAtPrimaryLeft.abs(),
        greaterThan(rightOnly.metrics.dyAtPrimaryRight.abs() + 0.15),
        reason: '${f.id} Direita should move 58, not 288',
      );
      expect(leftOnly.metrics.dyAtPrimaryRight, lessThan(0), reason: f.id);
      expect(rightOnly.metrics.dyAtPrimaryLeft, lessThan(0), reason: f.id);
      expect(leftOnly.metrics.minDetJ, greaterThan(0), reason: f.id);
      expect(rightOnly.metrics.minDetJ, greaterThan(0), reason: f.id);
    }
  });

  test('runtime cache scales the same unit weights', () {
    final f = faces.first;
    final runtime = JawAngleFieldRuntime();
    final cold = JawAngleField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 0.5,
    );
    final warm = JawAngleField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 0.5,
      runtime: runtime,
    );
    final again = JawAngleField.build(
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
      'lib/features/editor/beauty_engine/warp/v2/jaw_angle/jaw_angle_field.dart',
      'lib/features/editor/beauty_engine/warp/v2/jaw_angle/jaw_angle_masks.dart',
      'lib/features/editor/beauty_engine/warp/v2/jaw_angle/jaw_angle_metrics.dart',
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
      expect(source.contains('beauty_engine_controller'), isFalse, reason: path);
      expect(source.contains('v_chin_field.dart'), isFalse, reason: path);
      expect(source.contains('v_shape_field.dart'), isFalse, reason: path);
      expect(source.contains('jaw_field.dart'), isFalse, reason: path);
      expect(source.contains('chin_field.dart'), isFalse, reason: path);
      expect(source.contains('cheekbones_field.dart'), isFalse, reason: path);
    }
  });
}
