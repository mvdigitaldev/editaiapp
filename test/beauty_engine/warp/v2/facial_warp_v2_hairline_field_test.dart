import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/displacement_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/hairline/hairline_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/hairline/hairline_masks.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/hairline/hairline_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../filters/skin/mvp_benchmark_faces.dart';

const _ids = ['real-p01', 'real-p05', 'real-p12'];
const _protectEps = 0.5;

void _expectTempleTail(HairlineFieldMetrics m, String id) {
  final peak = math.max(m.dyAtCrown.abs(), m.influenceMax);
  expect(peak, greaterThan(0), reason: id);
  expect(
    m.absAtTempleMax,
    lessThan(0.35 * peak),
    reason: '$id temples must stay a tail vs the crown',
  );
}

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
      final built = HairlineField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0,
      );
      expect(built.field.isZero, isTrue, reason: f.id);
      expect(built.metrics.influenceMax, 0, reason: f.id);
      expect(built.metrics.minDetJ, 1, reason: f.id);
      expect(built.metrics.hairlineInflates, isFalse, reason: f.id);
      expect(built.metrics.hairlineDeflates, isFalse, reason: f.id);
      expect(built.metrics.eyes.p95Abs, 0, reason: f.id);
      expect(built.metrics.mouth.p95Abs, 0, reason: f.id);
      expect(built.metrics.outsideHairlineZoneP95, 0, reason: f.id);
      expect(
        built.masks.count(built.masks.hairlineActive),
        greaterThan(0),
        reason: f.id,
      );
    }
  });

  test('t=-0.5 inflates from the hairline, line stays, sides and crown move', () {
    final reports = <Map<String, Object>>[];
    for (final f in faces) {
      final built = HairlineField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: -0.5,
      );
      final m = built.metrics;
      expect(built.field.isZero, isFalse, reason: f.id);
      expect(
        m.hairlineInflates,
        isTrue,
        reason: '${f.id} primary ${m.primaryHandle}',
      );
      expect(m.hairlineDeflates, isFalse, reason: f.id);
      expect(
        m.hairlineYBefore - m.hairlineYAfter,
        greaterThan(1.5),
        reason: '${f.id} crown Δy should be > 1.5px',
      );
      expect(m.dyAtCrown, lessThan(0), reason: '${f.id} crown up');
      expect(m.dxAtCrown.abs(), lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(
        math.sqrt(m.dxAtCrown * m.dxAtCrown + m.dyAtCrown * m.dyAtCrown),
        greaterThan(0.4 * m.influenceMax),
        reason: '${f.id} energy at crown',
      );
      final left = _sampleCrownFlankDx(built.field, f.face, f.imageSize, 109);
      final right = _sampleCrownFlankDx(built.field, f.face, f.imageSize, 338);
      expect(left, lessThan(0), reason: '${f.id} left crown inflates outward');
      expect(right, greaterThan(0), reason: '${f.id} right crown inflates outward');
      final flankL = _sampleCrownFlankDy(built.field, f.face, f.imageSize, 67);
      final flankR = _sampleCrownFlankDy(built.field, f.face, f.imageSize, 297);
      expect(flankL, lessThan(0), reason: '${f.id} left hair side must rise');
      expect(flankR, lessThan(0), reason: '${f.id} right hair side must rise');
      expect(
        flankL.abs(),
        greaterThan(0.20 * m.dyAtCrown.abs()),
        reason: '${f.id} left side is a lift, not a leftover of the crown',
      );
      expect(
        m.dyAtPrimary.abs(),
        lessThanOrEqualTo(_protectEps),
        reason: '${f.id} line at 10 stays',
      );
      expect(
        _sampleAbs(built.field, f.face, f.imageSize, 103),
        lessThanOrEqualTo(_protectEps),
        reason: '${f.id} 103 is on the line and stays',
      );
      expect(
        _sampleAbs(built.field, f.face, f.imageSize, 332),
        lessThanOrEqualTo(_protectEps),
        reason: '${f.id} 332 is on the line and stays',
      );
      expect(
        _sampleAbs(built.field, f.face, f.imageSize, 67),
        lessThanOrEqualTo(_protectEps),
        reason: '${f.id} 67 is on the line and stays',
      );
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');
      expect(
        m.outsideHairlineZoneP95,
        lessThanOrEqualTo(_protectEps),
        reason: f.id,
      );
      expect(m.eyes.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.brows.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.nose.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.mouth.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.faceCenter.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.ears.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.cheeks.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.jawDomain.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      _expectTempleTail(m, f.id);

      var nonzeroDx = 0;
      for (var i = 0; i < built.field.pixelCount; i++) {
        if (built.field.dx[i] != 0) {
          nonzeroDx++;
        }
      }
      expect(nonzeroDx, greaterThan(0), reason: '${f.id} radial field has Δx');

      final dir = Directory('.cursor/facial-warp-v2/hairline/A/${f.id}');
      dir.createSync(recursive: true);
      final json = <String, Object>{
        'id': f.id,
        't': -0.5,
        ...m.toJson(),
        'maskCounts': {
          'hairline': built.masks.count(built.masks.hairline),
          'hairlineActive': built.masks.count(built.masks.hairlineActive),
          'temples': built.masks.count(built.masks.temples),
          'cheeks': built.masks.count(built.masks.cheeks),
        },
      };
      File('${dir.path}/metrics.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(json),
      );
      reports.add(json);
    }
    expect(reports.length, 3);
  });

  test('t=0.5 deflates inward to interior, temple tail, protects face', () {
    for (final f in faces) {
      final built = HairlineField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0.5,
      );
      final m = built.metrics;
      expect(built.field.isZero, isFalse, reason: f.id);
      expect(
        m.hairlineDeflates,
        isTrue,
        reason: '${f.id} primary ${m.primaryHandle}',
      );
      expect(m.hairlineInflates, isFalse, reason: f.id);
      expect(
        m.hairlineYAfter - m.hairlineYBefore,
        greaterThan(1.5),
        reason: '${f.id} crown should deflate > 1.5px',
      );
      expect(m.dyAtCrown, greaterThan(0), reason: '${f.id} crown down');
      expect(m.dxAtCrown.abs(), lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(
        math.sqrt(m.dxAtCrown * m.dxAtCrown + m.dyAtCrown * m.dyAtCrown),
        greaterThan(0.4 * m.influenceMax),
        reason: '${f.id} energy at crown',
      );
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');
      _expectTempleTail(m, f.id);
      final left = _sampleCrownFlankDx(built.field, f.face, f.imageSize, 109);
      final right = _sampleCrownFlankDx(built.field, f.face, f.imageSize, 338);
      expect(left, greaterThan(0), reason: '${f.id} left crown deflates inward');
      expect(right, lessThan(0), reason: '${f.id} right crown deflates inward');
      expect(
        _sampleCrownFlankDy(built.field, f.face, f.imageSize, 67),
        greaterThan(0),
        reason: '${f.id} left hair side deflates',
      );
      expect(
        m.dyAtPrimary.abs(),
        lessThanOrEqualTo(_protectEps),
        reason: '${f.id} line at 10 stays when deflating',
      );
      expect(
        _sampleAbs(built.field, f.face, f.imageSize, 103),
        lessThanOrEqualTo(_protectEps),
        reason: '${f.id} 103 stays when deflating',
      );

      var nonzeroDx = 0;
      for (var i = 0; i < built.field.pixelCount; i++) {
        if (built.field.dx[i] != 0) {
          nonzeroDx++;
        }
      }
      expect(nonzeroDx, greaterThan(0), reason: '${f.id} radial field has Δx');
    }
  });

  test('t=±1 stays injective', () {
    for (final f in faces) {
      for (final t in const [-1.0, 1.0]) {
        final built = HairlineField.build(
          face: f.face,
          imageSize: f.imageSize,
          t: t,
        );
        expect(
          built.metrics.minDetJ,
          greaterThan(0),
          reason: '${f.id} t=$t detJ=${built.metrics.minDetJ}',
        );
      }
    }
  });

  test('runtime cache scales the same unit weights', () {
    final f = faces.first;
    final runtime = HairlineFieldRuntime();
    final cold = HairlineField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: -0.5,
    );
    final warm = HairlineField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: -0.5,
      runtime: runtime,
    );
    final again = HairlineField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: -0.5,
      computeMetrics: false,
      runtime: runtime,
    );
    expect(warm.metrics.dyAtCrown, closeTo(cold.metrics.dyAtCrown, 1e-4));
    expect(warm.metrics.dxAtCrown, closeTo(cold.metrics.dxAtCrown, 1e-4));
    expect(identical(again.field, warm.field), isTrue);
    var maxDiff = 0.0;
    for (var i = 0; i < cold.field.pixelCount; i++) {
      maxDiff = math.max(
        maxDiff,
        math.max(
          (again.field.dx[i] - cold.field.dx[i]).abs(),
          (again.field.dy[i] - cold.field.dy[i]).abs(),
        ),
      );
    }
    expect(maxDiff, lessThan(1e-4));
  });

  test('builder API has no image RGBA and does not import the renderer', () {
    const paths = [
      'lib/features/editor/beauty_engine/warp/v2/hairline/hairline_field.dart',
      'lib/features/editor/beauty_engine/warp/v2/hairline/hairline_masks.dart',
      'lib/features/editor/beauty_engine/warp/v2/hairline/hairline_metrics.dart',
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
    }
  });
}

double _sampleAbs(
  DisplacementField field,
  FaceMeshResult face,
  Size imageSize,
  int id,
) {
  final s = _sampleAt(field, face, imageSize, id);
  return math.sqrt(s.dx * s.dx + s.dy * s.dy);
}

({double dx, double dy}) _sampleAt(
  DisplacementField field,
  FaceMeshResult face,
  Size imageSize,
  int id,
) {
  final px = HairlineMasks.landmarkPixels(face, imageSize);
  final p = id < px.length ? px[id] : null;
  expect(p, isNotNull, reason: 'missing landmark $id');
  final x = p!.dx.round().clamp(0, field.width - 1);
  final y = p.dy.round().clamp(0, field.height - 1);
  final i = field.indexOf(x, y);
  return (dx: field.dx[i], dy: field.dy[i]);
}

double _sampleCrownFlankDx(
  DisplacementField field,
  FaceMeshResult face,
  Size imageSize,
  int id,
) {
  return _sampleCrownFlank(field, face, imageSize, id).dx;
}

double _sampleCrownFlankDy(
  DisplacementField field,
  FaceMeshResult face,
  Size imageSize,
  int id,
) {
  return _sampleCrownFlank(field, face, imageSize, id).dy;
}

({double dx, double dy}) _sampleCrownFlank(
  DisplacementField field,
  FaceMeshResult face,
  Size imageSize,
  int id,
) {
  final px = HairlineMasks.landmarkPixels(face, imageSize);
  final p = id < px.length ? px[id] : null;
  expect(p, isNotNull, reason: 'missing landmark $id');
  final lift = HairlineField.crownExtendPx(px, HairlineField.faceWidthOf(px));
  final x = p!.dx.round().clamp(0, field.width - 1);
  final y = (p.dy - lift).round().clamp(0, field.height - 1);
  final i = field.indexOf(x, y);
  return (dx: field.dx[i], dy: field.dy[i]);
}
