import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/chin/chin_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/displacement_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/hairline/hairline_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/head/head_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/head/head_masks.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/landmark_advection.dart';
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
      final built = HeadField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0,
      );
      expect(built.field.isZero, isTrue, reason: f.id);
      expect(built.metrics.influenceMax, 0, reason: f.id);
      expect(built.metrics.minDetJ, 1, reason: f.id);
      expect(built.metrics.headGrows, isFalse, reason: f.id);
      expect(built.metrics.headShrinks, isFalse, reason: f.id);
      expect(built.metrics.outsideHeadP95, 0, reason: f.id);
      expect(
        built.masks.count(built.masks.headActive),
        greaterThan(0),
        reason: f.id,
      );
    }
  });

  test('t=-0.5 grows the silhouette and leaves far background still', () {
    for (final f in faces) {
      final built = HeadField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: -0.5,
      );
      final m = built.metrics;
      final px = HeadMasks.landmarkPixels(f.face, f.imageSize);
      final c = built.center;
      expect(c, isNotNull, reason: f.id);
      expect(built.field.isZero, isFalse, reason: f.id);
      expect(m.headGrows, isTrue, reason: f.id);
      expect(m.scale, closeTo(HeadField.scaleOf(-0.5), 1e-9));
      expect(m.outsideHeadP95, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');
      expect(m.coreCurvature, lessThan(_coreCeiling), reason: f.id);
      expect(m.entryStep, lessThan(_entryCeiling), reason: f.id);

      final outside = _alongRay(c!, px[152]!, 1.08);
      expect(
        _absAt(built.field, outside),
        greaterThan(0.8),
        reason: '${f.id} silhouette must leave the original oval',
      );

      const far = Offset(8, 8);
      expect(
        _absAt(built.field, far),
        lessThanOrEqualTo(_protectEps),
        reason: '${f.id} far background stays',
      );

      final left = m.absAtGonionLeft;
      final right = m.absAtGonionRight;
      expect(left, greaterThan(0), reason: f.id);
      expect(right, greaterThan(0), reason: f.id);
      final hi = math.max(left, right);
      final lo = math.min(left, right);
      expect(hi / lo, lessThan(1.25), reason: '${f.id} 58/288 $left $right');

      final fw = HeadMasks.faceWidthOf(px);
      final earL = px[234];
      final earR = px[454];
      if (earL != null && earR != null) {
        final leftEar = earL.dx < earR.dx ? earL : earR;
        final rightEar = earL.dx < earR.dx ? earR : earL;
        expect(
          _absAt(
            built.field,
            Offset(leftEar.dx - 0.20 * fw, leftEar.dy),
          ),
          greaterThan(0.8),
          reason: '${f.id} left hair wing',
        );
        expect(
          _absAt(
            built.field,
            Offset(rightEar.dx + 0.20 * fw, rightEar.dy),
          ),
          greaterThan(0.8),
          reason: '${f.id} right hair wing',
        );
      }
    }
  });

  test('t=0.5 shrinks without a ghost ring', () {
    for (final f in faces) {
      final built = HeadField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0.5,
      );
      final m = built.metrics;
      final px = HeadMasks.landmarkPixels(f.face, f.imageSize);
      final c = built.center;
      expect(c, isNotNull, reason: f.id);
      expect(m.headShrinks, isTrue, reason: f.id);
      expect(m.outsideHeadP95, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');
      expect(m.coreCurvature, lessThan(_coreCeiling), reason: f.id);
      expect(m.entryStep, lessThan(_entryCeiling), reason: f.id);

      final chin = px[152]!;
      final s = HeadField.scaleOf(0.5);
      final moved = Offset(
        c!.dx + s * (chin.dx - c.dx),
        c.dy + s * (chin.dy - c.dy),
      );
      final ring = Offset(
        (chin.dx + moved.dx) * 0.5,
        (chin.dy + moved.dy) * 0.5,
      );
      expect(
        _absAt(built.field, ring),
        greaterThan(0.8),
        reason: '${f.id} shrink ring must not be identity',
      );
    }
  });

  test('t=±1 stays injective and does not crease', () {
    for (final f in faces) {
      for (final t in const [-1.0, 1.0]) {
        final built = HeadField.build(
          face: f.face,
          imageSize: f.imageSize,
          t: t,
        );
        expect(
          built.metrics.minDetJ,
          greaterThan(0),
          reason: '${f.id} t=$t detJ=${built.metrics.minDetJ}',
        );
        expect(
          built.metrics.coreCurvature,
          lessThan(_coreCeiling),
          reason: '${f.id} t=$t vinco=${built.metrics.coreCurvature}',
        );
        expect(
          built.metrics.entryStep,
          lessThan(_entryCeiling),
          reason: '${f.id} t=$t degrau=${built.metrics.entryStep}',
        );
      }
    }
  });

  test('runtime cache keeps the same unit weights across t', () {
    final f = faces.first;
    final runtime = HeadFieldRuntime();
    final a = HeadField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: -0.5,
      runtime: runtime,
    );
    final unitRef = runtime.unitDx!;
    final unitDx = Float32List.fromList(unitRef);
    final unitDy = Float32List.fromList(runtime.unitDy!);
    final snapDx = Float32List.fromList(a.field.dx);
    final snapDy = Float32List.fromList(a.field.dy);
    final b = HeadField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: -1,
      computeMetrics: false,
      runtime: runtime,
    );
    expect(identical(b.field, a.field), isTrue);
    expect(identical(runtime.unitDx, unitRef), isTrue);
    var maxUnit = 0.0;
    for (var i = 0; i < unitDx.length; i++) {
      maxUnit = math.max(
        maxUnit,
        math.max(
          (runtime.unitDx![i] - unitDx[i]).abs(),
          (runtime.unitDy![i] - unitDy[i]).abs(),
        ),
      );
    }
    expect(maxUnit, lessThan(1e-7), reason: 'unit must not depend on t');

    final alphaA = HeadField.alphaOf(-0.5);
    final alphaB = HeadField.alphaOf(-1);
    expect(alphaA.abs(), greaterThan(1e-6));
    var maxRatioErr = 0.0;
    var checked = 0;
    for (var i = 0; i < snapDx.length; i++) {
      final da = math.sqrt(snapDx[i] * snapDx[i] + snapDy[i] * snapDy[i]);
      if (da < 0.2) {
        continue;
      }
      final db = math.sqrt(
        b.field.dx[i] * b.field.dx[i] + b.field.dy[i] * b.field.dy[i],
      );
      maxRatioErr = math.max(maxRatioErr, (db / da - alphaB / alphaA).abs());
      checked++;
    }
    expect(checked, greaterThan(100));
    expect(maxRatioErr, lessThan(1e-4));
  });

  test('Head then Chin/Hairline read the advected 152 and 10', () {
    for (final f in faces) {
      final head = HeadField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: -0.5,
      );
      final advected = LandmarkAdvection.advance(
        face: f.face,
        field: head.field,
        imageSize: f.imageSize,
      );
      final px0 = HeadMasks.landmarkPixels(f.face, f.imageSize);
      final px1 = HeadMasks.landmarkPixels(advected, f.imageSize);
      for (final id in const [10, 152]) {
        final p = px0[id]!;
        final qFace = px1[id]!;
        final qAdv = LandmarkAdvection.advancePoint(head.field, p);
        expect(
          (qFace - qAdv).distance,
          lessThan(1.0),
          reason: '${f.id} landmark $id desvio=${(qFace - qAdv).distance}',
        );
        expect(
          (qFace - p).distance,
          greaterThan(1.0),
          reason: '${f.id} $id must move with Head',
        );
      }

      final chin = ChinField.build(
        face: advected,
        imageSize: f.imageSize,
        t: -0.5,
        computeMetrics: true,
      );
      final chinOnOrigin = ChinField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: -0.5,
        computeMetrics: true,
      );
      expect(
        (chin.metrics.chinYBefore - px1[152]!.dy).abs(),
        lessThan(1.0),
        reason: '${f.id} Chin 152 is the advected chin',
      );
      expect(
        (chinOnOrigin.metrics.chinYBefore - px0[152]!.dy).abs(),
        lessThan(1.0),
        reason: '${f.id} control: Chin on origin uses detection 152',
      );
      expect(
        (chin.metrics.chinYBefore - chinOnOrigin.metrics.chinYBefore).abs(),
        greaterThan(0.8),
        reason: '${f.id} Chin must not keep the detection 152',
      );

      final hair = HairlineField.build(
        face: advected,
        imageSize: f.imageSize,
        t: 0,
        computeMetrics: true,
      );
      expect(hair.field.isZero, isTrue, reason: f.id);
      expect(px1[10], isNotNull);
    }
  });

  test('builder API has no image RGBA and does not import other Fields', () {
    const paths = [
      'lib/features/editor/beauty_engine/warp/v2/head/head_field.dart',
      'lib/features/editor/beauty_engine/warp/v2/head/head_masks.dart',
      'lib/features/editor/beauty_engine/warp/v2/head/head_metrics.dart',
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
      expect(source.contains('ridge_weight.dart'), isFalse, reason: path);
    }
  });
}

double _absAt(DisplacementField field, Offset p) {
  final x = p.dx.round().clamp(0, field.width - 1);
  final y = p.dy.round().clamp(0, field.height - 1);
  final i = field.indexOf(x, y);
  return math.sqrt(field.dx[i] * field.dx[i] + field.dy[i] * field.dy[i]);
}

Offset _alongRay(Offset c, Offset p, double factor) {
  return Offset(c.dx + factor * (p.dx - c.dx), c.dy + factor * (p.dy - c.dy));
}
