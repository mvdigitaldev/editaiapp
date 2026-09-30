import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/nose_lift/nose_lift_field.dart';
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
      final built = NoseLiftField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0,
      );
      expect(built.field.isZero, isTrue, reason: f.id);
      expect(built.metrics.influenceMax, 0, reason: f.id);
      expect(built.metrics.minDetJ, 1, reason: f.id);
      expect(built.metrics.noseLifts, isFalse, reason: f.id);
      expect(built.metrics.noseDrops, isFalse, reason: f.id);
    }
  });

  test('t=1 lifts the tip; root, eyes and mouth stay', () {
    for (final f in faces) {
      final built = NoseLiftField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 1,
      );
      final m = built.metrics;
      expect(m.noseLifts, isTrue, reason: f.id);
      expect(m.dxAtTip.abs(), lessThan(0.2), reason: '${f.id} only Δy');
      expect(m.absAtIrisLeft, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtIrisRight, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtBrow, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtMouth, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtHairline, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.eyes.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.mouth.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.influenceMax, lessThan(0.08 * m.faceWidth), reason: f.id);
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');
      expect(m.coreCurvature, lessThan(_coreCeiling), reason: f.id);
      expect(m.entryStep, lessThan(_entryCeiling), reason: f.id);
    }
  });

  test('t=-1 drops the tip without a fold', () {
    for (final f in faces) {
      final built = NoseLiftField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: -1,
      );
      final m = built.metrics;
      expect(m.noseDrops, isTrue, reason: f.id);
      expect(m.absAtIrisLeft, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtIrisRight, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtMouth, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');
      expect(m.coreCurvature, lessThan(_coreCeiling), reason: f.id);
      expect(m.entryStep, lessThan(_entryCeiling), reason: f.id);
    }
  });

  test('runtime cache only rescales dy(t)', () {
    final f = faces.first;
    final runtime = NoseLiftFieldRuntime();
    final cold = NoseLiftField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 1,
    );
    final warm = NoseLiftField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 1,
      runtime: runtime,
    );
    expect(warm.metrics.dyAtTip, closeTo(cold.metrics.dyAtTip, 1e-3));
    final again = NoseLiftField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: -1,
      runtime: runtime,
    );
    expect(identical(again.field, warm.field), isTrue);
    final dropped = NoseLiftField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: -1,
    );
    var maxDiff = 0.0;
    for (var i = 0; i < cold.field.pixelCount; i++) {
      maxDiff = math.max(
        maxDiff,
        math.max(
          (again.field.dx[i] - dropped.field.dx[i]).abs(),
          (again.field.dy[i] - dropped.field.dy[i]).abs(),
        ),
      );
    }
    expect(maxDiff, lessThan(1e-3));
  });

  test('builder API has no image RGBA and does not import other Fields', () {
    const paths = [
      'lib/features/editor/beauty_engine/warp/v2/nose_lift/nose_lift_field.dart',
      'lib/features/editor/beauty_engine/warp/v2/nose_lift/nose_lift_masks.dart',
      'lib/features/editor/beauty_engine/warp/v2/nose_lift/nose_lift_metrics.dart',
    ];
    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source.contains('sourceRgba'), isFalse, reason: path);
      expect(source.contains('backward_bilinear_warp'), isFalse, reason: path);
      expect(source.contains('PersonMask'), isFalse, reason: path);
      expect(source.contains('nose_size_field.dart'), isFalse, reason: path);
      expect(source.contains('jaw_field.dart'), isFalse, reason: path);
      expect(source.contains('head_field.dart'), isFalse, reason: path);
      expect(source.contains('ridge_weight.dart'), isFalse, reason: path);
      expect(source.contains('nose_slim'), isFalse, reason: path);
    }
  });
}
