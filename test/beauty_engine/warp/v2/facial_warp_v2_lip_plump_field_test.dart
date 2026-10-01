import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/lip_plump/lip_plump_field.dart';
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
      final built = LipPlumpField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0,
      );
      expect(built.field.isZero, isTrue, reason: f.id);
      expect(built.metrics.influenceMax, 0, reason: f.id);
      expect(built.metrics.minDetJ, 1, reason: f.id);
      expect(built.metrics.plumps, isFalse, reason: f.id);
      expect(built.metrics.thins, isFalse, reason: f.id);
    }
  });

  test('t=1 plumps both lips; nose and chin stay', () {
    for (final f in faces) {
      final built = LipPlumpField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 1,
      );
      final m = built.metrics;
      expect(m.plumps, isTrue, reason: f.id);
      expect(m.dxAtUpper.abs(), lessThan(0.2), reason: '${f.id} only Δy');
      expect(m.absAtCornerLeft, lessThan(1.2), reason: '${f.id} corner L');
      expect(m.absAtCornerRight, lessThan(1.2), reason: '${f.id} corner R');
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

  test('t=-1 thins both lips without a fold', () {
    for (final f in faces) {
      final built = LipPlumpField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: -1,
      );
      final m = built.metrics;
      expect(m.thins, isTrue, reason: f.id);
      expect(m.absAtNoseTip, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtChin, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');
      expect(m.coreCurvature, lessThan(_coreCeiling), reason: f.id);
      expect(m.entryStep, lessThan(_entryCeiling), reason: f.id);
    }
  });

  test('upper-only leaves the lower lip', () {
    for (final f in faces) {
      final built = LipPlumpField.build(
        face: f.face,
        imageSize: f.imageSize,
        tUpper: 1,
        tLower: 0,
      );
      expect(built.metrics.plumpsUpperOnly, isTrue, reason: f.id);
    }
  });

  test('lower-only leaves the upper lip', () {
    for (final f in faces) {
      final built = LipPlumpField.build(
        face: f.face,
        imageSize: f.imageSize,
        tUpper: 0,
        tLower: 1,
      );
      expect(built.metrics.plumpsLowerOnly, isTrue, reason: f.id);
    }
  });

  test('runtime cache only rescales dy(t)', () {
    final f = faces.first;
    final runtime = LipPlumpFieldRuntime();
    final cold = LipPlumpField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 1,
    );
    final warm = LipPlumpField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 1,
      runtime: runtime,
    );
    expect(warm.metrics.dyAtUpper, closeTo(cold.metrics.dyAtUpper, 1e-3));
    final again = LipPlumpField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: -1,
      runtime: runtime,
    );
    expect(identical(again.field, warm.field), isTrue);
    final flipped = LipPlumpField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: -1,
    );
    var maxDiff = 0.0;
    for (var i = 0; i < cold.field.pixelCount; i++) {
      maxDiff = math.max(
        maxDiff,
        math.max(
          (again.field.dx[i] - flipped.field.dx[i]).abs(),
          (again.field.dy[i] - flipped.field.dy[i]).abs(),
        ),
      );
    }
    expect(maxDiff, lessThan(1e-3));
  });

  test('builder API has no image RGBA and does not import other Fields', () {
    const paths = [
      'lib/features/editor/beauty_engine/warp/v2/lip_plump/lip_plump_field.dart',
      'lib/features/editor/beauty_engine/warp/v2/lip_plump/lip_plump_masks.dart',
      'lib/features/editor/beauty_engine/warp/v2/lip_plump/lip_plump_metrics.dart',
    ];
    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source.contains('sourceRgba'), isFalse, reason: path);
      expect(source.contains('backward_bilinear_warp'), isFalse, reason: path);
      expect(source.contains('PersonMask'), isFalse, reason: path);
      expect(source.contains('lip_size_field.dart'), isFalse, reason: path);
      expect(source.contains('lip_width_field.dart'), isFalse, reason: path);
      expect(source.contains('lip_height_field.dart'), isFalse, reason: path);
      expect(source.contains('lip_angle_field.dart'), isFalse, reason: path);
      expect(source.contains('jaw_field.dart'), isFalse, reason: path);
      expect(source.contains('ridge_weight.dart'), isFalse, reason: path);
      expect(source.contains('lip_thickness'), isFalse, reason: path);
    }
  });
}
