import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/lip_size/lip_size_field.dart';
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
      final built = LipSizeField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0,
      );
      expect(built.field.isZero, isTrue, reason: f.id);
      expect(built.metrics.influenceMax, 0, reason: f.id);
      expect(built.metrics.minDetJ, 1, reason: f.id);
      expect(built.metrics.lipsEnlarge, isFalse, reason: f.id);
      expect(built.metrics.lipsShrink, isFalse, reason: f.id);
    }
  });

  test('t=1 shrinks the lips; nose, chin, eyes and brow stay', () {
    for (final f in faces) {
      final built = LipSizeField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 1,
      );
      final m = built.metrics;
      expect(m.lipsShrink, isTrue, reason: f.id);
      expect(m.absAtCenter, lessThan(1.2), reason: '${f.id} center stays');
      expect(m.absAtNoseTip, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtChin, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtIrisLeft, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtIrisRight, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtBrow, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtHairline, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.eyes.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.nose.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.influenceMax, lessThan(0.06 * m.faceWidth), reason: f.id);
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');
      expect(m.coreCurvature, lessThan(_coreCeiling), reason: f.id);
      expect(m.entryStep, lessThan(_entryCeiling), reason: f.id);
    }
  });

  test('t=-1 enlarges the lips without a fold', () {
    for (final f in faces) {
      final built = LipSizeField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: -1,
      );
      final m = built.metrics;
      expect(m.lipsEnlarge, isTrue, reason: f.id);
      expect(m.absAtNoseTip, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtChin, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtIrisLeft, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');
      expect(m.coreCurvature, lessThan(_coreCeiling), reason: f.id);
      expect(m.entryStep, lessThan(_entryCeiling), reason: f.id);
    }
  });

  test('runtime cache only rescales α(t)', () {
    final f = faces.first;
    final runtime = LipSizeFieldRuntime();
    final cold = LipSizeField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 1,
    );
    final warm = LipSizeField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 1,
      runtime: runtime,
    );
    expect(
      warm.metrics.radialAtUpper,
      closeTo(cold.metrics.radialAtUpper, 1e-3),
    );
    final again = LipSizeField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: -1,
      runtime: runtime,
    );
    expect(identical(again.field, warm.field), isTrue);
    final enlarged = LipSizeField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: -1,
    );
    var maxDiff = 0.0;
    for (var i = 0; i < cold.field.pixelCount; i++) {
      maxDiff = math.max(
        maxDiff,
        math.max(
          (again.field.dx[i] - enlarged.field.dx[i]).abs(),
          (again.field.dy[i] - enlarged.field.dy[i]).abs(),
        ),
      );
    }
    expect(maxDiff, lessThan(1e-3));
  });

  test('builder API has no image RGBA and does not import other Fields', () {
    const paths = [
      'lib/features/editor/beauty_engine/warp/v2/lip_size/lip_size_field.dart',
      'lib/features/editor/beauty_engine/warp/v2/lip_size/lip_size_masks.dart',
      'lib/features/editor/beauty_engine/warp/v2/lip_size/lip_size_metrics.dart',
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
      expect(source.contains('lip_thickness'), isFalse, reason: path);
    }
  });
}
