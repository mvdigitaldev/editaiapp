import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/v_shape/v_shape_field.dart';
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
      final built = VShapeField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0,
      );
      expect(built.field.isZero, isTrue, reason: f.id);
      expect(built.metrics.influenceMax, 0, reason: f.id);
      expect(built.metrics.minDetJ, 1, reason: f.id);
      expect(built.metrics.vShapeSharpens, isFalse, reason: f.id);
      expect(built.metrics.vShapeSquares, isFalse, reason: f.id);
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

  test('t=0.5 pulls outer chin inward (Meitu right = V), dx only, locks 148/152',
      () {
    for (final f in faces) {
      final built = VShapeField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0.5,
      );
      final m = built.metrics;
      expect(built.field.isZero, isFalse, reason: f.id);
      expect(m.vShapeSharpens, isTrue, reason: f.id);
      expect(m.vShapeSquares, isFalse, reason: f.id);
      expect(
        m.chinWidthBefore - m.chinWidthAfter,
        greaterThan(0.4),
        reason: '${f.id} t>0 should narrow the outer chin',
      );
      expect(
        m.dxAtPrimaryLeft,
        greaterThan(0),
        reason: '${f.id} 172 toward midline',
      );
      expect(
        m.dxAtPrimaryRight,
        lessThan(0),
        reason: '${f.id} 397 toward midline',
      );
      expect(m.dyAtPrimaryLeft.abs(), lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.dyAtPrimaryRight.abs(), lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtChinTip, lessThanOrEqualTo(_protectEps), reason: '${f.id} 152');
      expect(m.absAtInnerLeft, lessThanOrEqualTo(_protectEps), reason: '${f.id} 148');
      expect(m.absAtInnerRight, lessThanOrEqualTo(_protectEps), reason: '${f.id} 377');
      expect(
        m.absAtGonionLeft,
        lessThan(0.04 * m.faceWidth),
        reason: '${f.id} 58 sopro, não compete com Jaw (${m.absAtGonionLeft} vs 0.04×${m.faceWidth})',
      );
      expect(
        m.absAtGonionRight,
        lessThan(0.04 * m.faceWidth),
        reason: '${f.id} 288 sopro, não compete com Jaw',
      );
      expect(
        m.absAtGonionLeft,
        lessThan(m.dxAtPrimaryLeft.abs()),
        reason: '${f.id} 58 << pico 172',
      );
      expect(
        m.absAtGonionRight,
        lessThan(m.dxAtPrimaryRight.abs()),
        reason: '${f.id} 288 << pico 397',
      );
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');
      expect(m.outsideChinZoneP95, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.eyes.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.mouth.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      // A zona do Jaw deixou de ser hard-zero: era um disco binário que, com a
      // rampa de bordo por cima, apagava o efeito em todo o gónio e fazia o
      // total dar um bico no 172. Passou a cauda graduada pelo peso da crista,
      // logo aqui exige-se que entre — mas só como cauda, nunca a mandar.
      expect(
        m.jawDomain.p95Abs,
        greaterThan(_protectEps),
        reason: '${f.id} a cauda tem de entrar na zona do Jaw',
      );
      expect(
        m.jawDomain.p95Abs,
        lessThan(0.55 * m.dxAtPrimaryRight.abs()),
        reason: '${f.id} cauda na zona do Jaw acima de meio pico',
      );

      var nonzeroDy = 0;
      for (var i = 0; i < built.field.pixelCount; i++) {
        if (built.field.dy[i] != 0) {
          nonzeroDy++;
        }
      }
      expect(nonzeroDy, 0, reason: '${f.id} field is Δx only');
    }
    for (final f in faces) {
      final atFullV = VShapeField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 1,
      );
      expect(
        atFullV.metrics.minDetJ,
        greaterThan(0),
        reason: '${f.id} fold at t=1 detJ=${atFullV.metrics.minDetJ}',
      );
    }
  });

  test('t=-0.5 pushes outer chin outward (Meitu left = square), dx only', () {
    for (final f in faces) {
      final built = VShapeField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: -0.5,
      );
      final m = built.metrics;
      expect(m.vShapeSquares, isTrue, reason: f.id);
      expect(m.vShapeSharpens, isFalse, reason: f.id);
      expect(
        m.chinWidthAfter - m.chinWidthBefore,
        greaterThan(0.4),
        reason: '${f.id} t<0 should square the outer chin',
      );
      expect(m.dxAtPrimaryLeft, lessThan(0), reason: '${f.id} 172 outward');
      expect(m.dxAtPrimaryRight, greaterThan(0), reason: '${f.id} 397 outward');
      expect(m.absAtChinTip, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtInnerLeft, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtInnerRight, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(
        m.absAtGonionLeft,
        lessThan(0.04 * m.faceWidth),
        reason: '${f.id} 58 sopro, não compete com Jaw',
      );
      expect(
        m.absAtGonionLeft,
        lessThan(m.dxAtPrimaryLeft.abs()),
        reason: '${f.id} 58 << pico 172',
      );
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');

      var nonzeroDy = 0;
      for (var i = 0; i < built.field.pixelCount; i++) {
        if (built.field.dy[i] != 0) {
          nonzeroDy++;
        }
      }
      expect(nonzeroDy, 0, reason: '${f.id} field is Δx only');
    }
    for (final f in faces) {
      final atFullSquare = VShapeField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: -1,
      );
      expect(
        atFullSquare.metrics.minDetJ,
        greaterThan(0),
        reason: '${f.id} fold at t=-1 detJ=${atFullSquare.metrics.minDetJ}',
      );
    }
  });

  test('photo-left t moves MediaPipe 397; photo-right t moves 172', () {
    for (final f in faces) {
      final leftOnly = VShapeField.build(
        face: f.face,
        imageSize: f.imageSize,
        tPhotoLeft: 0.5,
        tPhotoRight: 0,
      );
      final rightOnly = VShapeField.build(
        face: f.face,
        imageSize: f.imageSize,
        tPhotoLeft: 0,
        tPhotoRight: 0.5,
      );
      expect(
        leftOnly.metrics.dxAtPrimaryRight.abs(),
        greaterThan(leftOnly.metrics.dxAtPrimaryLeft.abs() + 0.15),
        reason: '${f.id} Esquerda should move 397, not 172',
      );
      expect(
        rightOnly.metrics.dxAtPrimaryLeft.abs(),
        greaterThan(rightOnly.metrics.dxAtPrimaryRight.abs() + 0.15),
        reason: '${f.id} Direita should move 172, not 397',
      );
      expect(leftOnly.metrics.minDetJ, greaterThan(0), reason: f.id);
      expect(rightOnly.metrics.minDetJ, greaterThan(0), reason: f.id);
    }
  });

  test('runtime cache scales the same unit weights', () {
    final f = faces.first;
    final runtime = VShapeFieldRuntime();
    final cold = VShapeField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 0.5,
    );
    final warm = VShapeField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 0.5,
      runtime: runtime,
    );
    final again = VShapeField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 0.5,
      computeMetrics: false,
      runtime: runtime,
    );
    expect(
      warm.metrics.dxAtPrimaryLeft,
      closeTo(cold.metrics.dxAtPrimaryLeft, 1e-4),
    );
    expect(
      warm.metrics.dxAtPrimaryRight,
      closeTo(cold.metrics.dxAtPrimaryRight, 1e-4),
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
      'lib/features/editor/beauty_engine/warp/v2/v_shape/v_shape_field.dart',
      'lib/features/editor/beauty_engine/warp/v2/v_shape/v_shape_masks.dart',
      'lib/features/editor/beauty_engine/warp/v2/v_shape/v_shape_metrics.dart',
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
      expect(source.contains('jaw_field.dart'), isFalse, reason: path);
      expect(source.contains('chin_field.dart'), isFalse, reason: path);
      expect(source.contains('cheekbones_field.dart'), isFalse, reason: path);
    }
  });
}
