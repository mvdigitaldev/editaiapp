import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/jaw_field.dart';
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
      final built = JawField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0,
      );
      expect(built.field.isZero, isTrue, reason: f.id);
      expect(built.metrics.influenceMax, 0, reason: f.id);
      expect(built.metrics.minDetJ, 1, reason: f.id);
      expect(built.metrics.eyes.p95Abs, 0, reason: f.id);
      expect(built.metrics.mouth.p95Abs, 0, reason: f.id);
      expect(built.metrics.outsideJawZoneP95, 0, reason: f.id);
      expect(built.masks.count(built.masks.beard), greaterThan(0), reason: f.id);
      expect(built.masks.count(built.masks.jawActive), greaterThan(0), reason: f.id);
    }
  });

  test('t=0.5 narrows jaw, protects regions, no fold', () {
    final reports = <Map<String, Object>>[];
    for (final f in faces) {
      final built = JawField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0.5,
      );
      final m = built.metrics;
      expect(built.field.isZero, isFalse, reason: f.id);
      expect(m.gonionNarrows, isTrue, reason: '${f.id} gonion 58-288');
      expect(
        m.gonionWidthBefore - m.gonionWidthAfter,
        greaterThan(1.5),
        reason: '${f.id} gonion narrowing should be > 1.5px',
      );
      expect(m.dxAtGonionLeft, greaterThan(0), reason: '${f.id} dx 58');
      expect(m.dxAtGonionRight, lessThan(0), reason: '${f.id} dx 288');
      expect(
        m.dxAtGonionLeft.abs(),
        greaterThan(0.4 * m.influenceMax),
        reason: '${f.id} energy at gonion left',
      );
      expect(
        m.dxAtGonionRight.abs(),
        greaterThan(0.4 * m.influenceMax),
        reason: '${f.id} energy at gonion right',
      );
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');
      expect(m.outsideJawZoneP95, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.eyes.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.brows.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.nose.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.mouth.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.faceCenter.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.beard.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.ears.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);

      final mid = f.imageSize.width / 2;
      var leftDx = 0.0;
      var rightDx = 0.0;
      for (var i = 0; i < built.field.pixelCount; i++) {
        if (built.masks.jawActive[i] == 0) {
          continue;
        }
        final x = i % built.field.width;
        if (x + 0.5 < mid) {
          leftDx = math.max(leftDx, built.field.dx[i]);
        } else {
          rightDx = math.min(rightDx, built.field.dx[i]);
        }
      }
      expect(leftDx, greaterThan(0), reason: '${f.id} left dx');
      expect(rightDx, lessThan(0), reason: '${f.id} right dx');

      final dir = Directory('.cursor/facial-warp-v2/v2.1/${f.id}');
      dir.createSync(recursive: true);
      final json = <String, Object>{
        'id': f.id,
        't': 0.5,
        ...m.toJson(),
        'maskCounts': {
          'jaw': built.masks.count(built.masks.jaw),
          'jawActive': built.masks.count(built.masks.jawActive),
          'beard': built.masks.count(built.masks.beard),
          'ears': built.masks.count(built.masks.ears),
          'mouth': built.masks.count(built.masks.mouth),
        },
      };
      File('${dir.path}/metrics.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(json),
      );
      reports.add(json);
    }
    expect(reports.length, 3);
  });

  test('builder API has no image RGBA and does not import the renderer', () {
    final source = File(
      'lib/features/editor/beauty_engine/warp/v2/jaw_field.dart',
    ).readAsStringSync();
    expect(source.contains('sourceRgba'), isFalse);
    expect(source.contains('backward_bilinear_warp'), isFalse);
    expect(source.contains('extended_roi'), isFalse);
    expect(source.contains('VertexRoleMap'), isFalse);
    expect(source.contains('FaceWarpUtils'), isFalse);
    expect(source.contains('PersonMask'), isFalse);
    expect(source.contains('Telea'), isFalse);
    expect(source.contains('pass_warp'), isFalse);
    expect(source.contains('beauty_engine_controller'), isFalse);
  });
}
