import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/face_slim/face_slim_field.dart';
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
      final built = FaceSlimField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0,
      );
      expect(built.field.isZero, isTrue, reason: f.id);
      expect(built.metrics.influenceMax, 0, reason: f.id);
      expect(built.metrics.minDetJ, 1, reason: f.id);
      expect(built.metrics.faceSlimNarrows, isFalse, reason: f.id);
      expect(built.metrics.eyes.p95Abs, 0, reason: f.id);
      expect(built.metrics.mouth.p95Abs, 0, reason: f.id);
      expect(built.metrics.outsideSlimZoneP95, 0, reason: f.id);
      expect(
        built.masks.count(built.masks.slimActive),
        greaterThan(0),
        reason: f.id,
      );
    }
  });

  test('t=0.5 narrows mid-face, protects jaw/chin, dx only', () {
    final reports = <Map<String, Object>>[];
    for (final f in faces) {
      final built = FaceSlimField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0.5,
      );
      final m = built.metrics;
      expect(built.field.isZero, isFalse, reason: f.id);
      expect(
        m.faceSlimNarrows,
        isTrue,
        reason: '${f.id} primaries ${m.primaryLeft}/${m.primaryRight}',
      );
      expect(m.widthDelta, greaterThan(0), reason: '${f.id} Δ width');
      expect(m.dxAtPrimaryLeft, greaterThan(0), reason: '${f.id} left → midline');
      expect(m.dxAtPrimaryRight, lessThan(0), reason: '${f.id} right → midline');
      expect(m.dyAtPrimaryLeft.abs(), lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.dyAtPrimaryRight.abs(), lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(
        m.dxAtPrimaryLeft.abs(),
        greaterThan(0.4 * m.influenceMax),
        reason: '${f.id} energy at primary left',
      );
      expect(
        m.dxAtPrimaryRight.abs(),
        greaterThan(0.4 * m.influenceMax),
        reason: '${f.id} energy at primary right',
      );
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');
      expect(m.outsideSlimZoneP95, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.eyes.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.brows.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.nose.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.mouth.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.faceCenter.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.ears.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.jawDomain.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.chinDomain.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtGonionLeft, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtGonionRight, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.absAtChinTip, lessThanOrEqualTo(_protectEps), reason: f.id);

      var nonzeroDy = 0;
      for (var i = 0; i < built.field.pixelCount; i++) {
        if (built.field.dy[i] != 0) {
          nonzeroDy++;
        }
      }
      expect(nonzeroDy, 0, reason: '${f.id} field is Δx only');

      final dir = Directory('.cursor/facial-warp-v2/face-slim/A/${f.id}');
      dir.createSync(recursive: true);
      final json = <String, Object>{
        'id': f.id,
        't': 0.5,
        ...m.toJson(),
        'maskCounts': {
          'slim': built.masks.count(built.masks.slim),
          'slimActive': built.masks.count(built.masks.slimActive),
          'jawDomain': built.masks.count(built.masks.jawDomain),
          'chinDomain': built.masks.count(built.masks.chinDomain),
        },
      };
      File('${dir.path}/metrics.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(json),
      );
      reports.add(json);
    }
    expect(reports.length, 3);
  });

  test('builder API has no image RGBA and does not import other Fields', () {
    const paths = [
      'lib/features/editor/beauty_engine/warp/v2/face_slim/face_slim_field.dart',
      'lib/features/editor/beauty_engine/warp/v2/face_slim/face_slim_masks.dart',
      'lib/features/editor/beauty_engine/warp/v2/face_slim/face_slim_metrics.dart',
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
      expect(source.contains('nose_field.dart'), isFalse, reason: path);
      expect(source.contains('eyes_field.dart'), isFalse, reason: path);
      expect(source.contains('mouth_field.dart'), isFalse, reason: path);
    }
  });
}
