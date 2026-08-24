import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/chin/chin_field.dart';
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
      final built = ChinField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0,
      );
      expect(built.field.isZero, isTrue, reason: f.id);
      expect(built.metrics.influenceMax, 0, reason: f.id);
      expect(built.metrics.minDetJ, 1, reason: f.id);
      expect(built.metrics.chinShortens, isFalse, reason: f.id);
      expect(built.metrics.eyes.p95Abs, 0, reason: f.id);
      expect(built.metrics.mouth.p95Abs, 0, reason: f.id);
      expect(built.metrics.outsideChinZoneP95, 0, reason: f.id);
      expect(built.masks.count(built.masks.chinActive), greaterThan(0), reason: f.id);
    }
  });

  test('t=0.5 shortens chin, protects jaw and face, dy only', () {
    final reports = <Map<String, Object>>[];
    for (final f in faces) {
      final built = ChinField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0.5,
      );
      final m = built.metrics;
      expect(built.field.isZero, isFalse, reason: f.id);
      expect(m.chinShortens, isTrue, reason: '${f.id} primary ${m.primaryHandle}');
      expect(
        m.chinYBefore - m.chinYAfter,
        greaterThan(1.5),
        reason: '${f.id} chin Δy should be > 1.5px',
      );
      expect(m.dyAtPrimary, lessThan(0), reason: '${f.id} dy primary up');
      expect(m.dxAtPrimary.abs(), lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(
        m.dyAtPrimary.abs(),
        greaterThan(0.4 * m.influenceMax),
        reason: '${f.id} energy at primary handle',
      );
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');
      expect(m.outsideChinZoneP95, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.eyes.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.brows.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.nose.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.mouth.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.faceCenter.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.ears.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.jawDomain.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtGonionLeft, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtGonionRight, lessThanOrEqualTo(_protectEps), reason: f.id);

      var nonzeroDx = 0;
      for (var i = 0; i < built.field.pixelCount; i++) {
        if (built.field.dx[i] != 0) {
          nonzeroDx++;
        }
      }
      expect(nonzeroDx, 0, reason: '${f.id} field is Δy only');

      final dir = Directory('.cursor/facial-warp-v2/chin/A/${f.id}');
      dir.createSync(recursive: true);
      final json = <String, Object>{
        'id': f.id,
        't': 0.5,
        ...m.toJson(),
        'maskCounts': {
          'chin': built.masks.count(built.masks.chin),
          'chinActive': built.masks.count(built.masks.chinActive),
          'jawDomain': built.masks.count(built.masks.jawDomain),
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
    const paths = [
      'lib/features/editor/beauty_engine/warp/v2/chin/chin_field.dart',
      'lib/features/editor/beauty_engine/warp/v2/chin/chin_masks.dart',
      'lib/features/editor/beauty_engine/warp/v2/chin/chin_metrics.dart',
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
    }
  });
}
