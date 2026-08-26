import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/v_chin/v_chin_field.dart';
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
      final built = VChinField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0,
      );
      expect(built.field.isZero, isTrue, reason: f.id);
      expect(built.metrics.influenceMax, 0, reason: f.id);
      expect(built.metrics.minDetJ, 1, reason: f.id);
      expect(built.metrics.vChinSharpens, isFalse, reason: f.id);
      expect(built.metrics.vChinSquares, isFalse, reason: f.id);
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

  test('t=-0.5 pulls chin sides inward (Meitu left = V), dx only, locks 152 and gonions', () {
    for (final f in faces) {
      final built = VChinField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: -0.5,
      );
      final m = built.metrics;
      expect(built.field.isZero, isFalse, reason: f.id);
      expect(m.vChinSharpens, isTrue, reason: f.id);
      expect(m.vChinSquares, isFalse, reason: f.id);
      expect(
        m.chinWidthBefore - m.chinWidthAfter,
        greaterThan(0.4),
        reason: '${f.id} t<0 should narrow the chin pad',
      );
      expect(m.dxAtPrimaryLeft, greaterThan(0), reason: '${f.id} 148 toward midline');
      expect(m.dxAtPrimaryRight, lessThan(0), reason: '${f.id} 377 toward midline');
      expect(m.dyAtPrimaryLeft.abs(), lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.dyAtPrimaryRight.abs(), lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtChinTip, lessThan(2.5), reason: '${f.id} 152');
      expect(m.absAtGonionLeft, lessThanOrEqualTo(_protectEps), reason: '${f.id} 58');
      expect(m.absAtGonionRight, lessThanOrEqualTo(_protectEps), reason: '${f.id} 288');
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');
      expect(m.outsideChinZoneP95, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.eyes.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.mouth.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.jawDomain.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(
        m.chinTip.p95Abs,
        lessThanOrEqualTo(math.max(_protectEps, 0.35 * m.influenceMax)),
        reason: f.id,
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
      final atFullV = VChinField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: -1,
      );
      expect(
        atFullV.metrics.minDetJ,
        greaterThan(0),
        reason: '${f.id} fold at t=-1 detJ=${atFullV.metrics.minDetJ}',
      );
    }
  });

  test('t=0.5 pushes chin sides outward (Meitu right = square), dx only, locks 152 and gonions', () {
    for (final f in faces) {
      final built = VChinField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0.5,
      );
      final m = built.metrics;
      expect(m.vChinSquares, isTrue, reason: f.id);
      expect(m.vChinSharpens, isFalse, reason: f.id);
      expect(
        m.chinWidthAfter - m.chinWidthBefore,
        greaterThan(0.4),
        reason: '${f.id} t>0 should square the chin pad',
      );
      expect(m.dxAtPrimaryLeft, lessThan(0), reason: '${f.id} 148 outward');
      expect(m.dxAtPrimaryRight, greaterThan(0), reason: '${f.id} 377 outward');
      expect(m.absAtChinTip, lessThan(2.5), reason: f.id);
      expect(m.absAtGonionLeft, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtGonionRight, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');

      var nonzeroDy = 0;
      for (var i = 0; i < built.field.pixelCount; i++) {
        if (built.field.dy[i] != 0) {
          nonzeroDy++;
        }
      }
      expect(nonzeroDy, 0, reason: '${f.id} field is Δx only');
    }
  });

  test('photo-left t moves MediaPipe 377; photo-right t moves 148', () {
    for (final f in faces) {
      final leftOnly = VChinField.build(
        face: f.face,
        imageSize: f.imageSize,
        tPhotoLeft: 0.5,
        tPhotoRight: 0,
      );
      final rightOnly = VChinField.build(
        face: f.face,
        imageSize: f.imageSize,
        tPhotoLeft: 0,
        tPhotoRight: 0.5,
      );
      expect(
        leftOnly.metrics.dxAtPrimaryRight.abs(),
        greaterThan(leftOnly.metrics.dxAtPrimaryLeft.abs() + 0.15),
        reason: '${f.id} Esquerda should move 377, not 148',
      );
      expect(
        rightOnly.metrics.dxAtPrimaryLeft.abs(),
        greaterThan(rightOnly.metrics.dxAtPrimaryRight.abs() + 0.15),
        reason: '${f.id} Direita should move 148, not 377',
      );
      expect(leftOnly.metrics.minDetJ, greaterThan(0), reason: f.id);
      expect(rightOnly.metrics.minDetJ, greaterThan(0), reason: f.id);
    }
  });

  test('runtime cache scales the same unit weights', () {
    final f = faces.first;
    final runtime = VChinFieldRuntime();
    final cold = VChinField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 0.5,
    );
    final warm = VChinField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 0.5,
      runtime: runtime,
    );
    final again = VChinField.build(
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
      'lib/features/editor/beauty_engine/warp/v2/v_chin/v_chin_field.dart',
      'lib/features/editor/beauty_engine/warp/v2/v_chin/v_chin_masks.dart',
      'lib/features/editor/beauty_engine/warp/v2/v_chin/v_chin_metrics.dart',
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
      expect(source.contains('jaw_field.dart'), isFalse, reason: path);
      expect(source.contains('chin_field.dart'), isFalse, reason: path);
      expect(source.contains('cheekbones_field.dart'), isFalse, reason: path);
    }
  });
}
