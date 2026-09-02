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

Offset? _landmarkPixel(FaceMeshResult face, int id, Size size) {
  for (final lm in face.landmarks) {
    if (lm.index == id) {
      return Offset(lm.normalized.dx * size.width, lm.normalized.dy * size.height);
    }
  }
  return null;
}

int _indexAt(JawFieldBuild built, Offset p) {
  final x = p.dx.round().clamp(0, built.field.width - 1);
  final y = p.dy.round().clamp(0, built.field.height - 1);
  return built.field.indexOf(x, y);
}

bool _isActive(JawFieldBuild built, Offset p) =>
    built.masks.jawActive[_indexAt(built, p)] != 0;

double _absDx(JawFieldBuild built, Offset p) =>
    built.field.dx[_indexAt(built, p)].abs();

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

  test('t=1 does not fold and keeps protections (slider vai a 99%)', () {
    for (final f in faces) {
      final built = JawField.build(face: f.face, imageSize: f.imageSize, t: 1);
      final m = built.metrics;
      expect(m.gonionNarrows, isTrue, reason: f.id);
      expect(m.minDetJ, greaterThan(0), reason: '${f.id} detJ=${m.minDetJ}');
      expect(m.outsideJawZoneP95, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.eyes.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.mouth.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.ears.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
      expect(m.beard.p95Abs, lessThanOrEqualTo(_protectEps), reason: f.id);
    }
  });

  // Regressão do serrilhado: com `max` de gaussianas por landmark o peso caía
  // no vão entre âncoras, o que ondulava a silhueta e fazia quina onde duas
  // gaussianas empatavam. Na crista em polilinha o meio do segmento tem de
  // seguir a interpolação, não colapsar.
  test('crista não festona entre âncoras consecutivas', () {
    for (final f in faces) {
      final built = JawField.build(face: f.face, imageSize: f.imageSize, t: 1);
      var checked = 0;
      for (final chain in [JawField.curveLeft, JawField.curveRight]) {
        for (var i = 0; i < chain.length - 1; i++) {
          final a = _landmarkPixel(f.face, chain[i], f.imageSize);
          final b = _landmarkPixel(f.face, chain[i + 1], f.imageSize);
          if (a == null || b == null) {
            continue;
          }
          final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
          if (!_isActive(built, mid) ||
              !_isActive(built, a) ||
              !_isActive(built, b)) {
            continue;
          }
          final absA = _absDx(built, a);
          final absB = _absDx(built, b);
          final absMid = _absDx(built, mid);
          final floor = 0.8 * math.min(absA, absB);
          expect(
            absMid,
            greaterThanOrEqualTo(floor),
            reason: '${f.id} vão ${chain[i]}→${chain[i + 1]}: '
                'meio=${absMid.toStringAsFixed(2)} '
                'a=${absA.toStringAsFixed(2)} b=${absB.toStringAsFixed(2)}',
          );
          checked++;
        }
      }
      expect(checked, greaterThanOrEqualTo(4), reason: '${f.id} vãos testados');
    }
  });

  // A cauda existe para o estreitamento não acabar em ponta no 132/361: acima
  // dele o pixel saía do domínio e o deslocamento caía de golpe para zero.
  // Tem de ser leve (não é o Cheekbones) e igual dos dois lados — o disco da
  // orelha na rampa longa deixava o lado direito a um terço do esquerdo.
  test('cauda na lateral do rosto é leve e simétrica', () {
    for (final f in faces) {
      final built = JawField.build(face: f.face, imageSize: f.imageSize, t: 1);
      final peak = built.metrics.influenceMax;
      expect(peak, greaterThan(0), reason: f.id);

      for (final pair in [(93, 323), (234, 454)]) {
        final isRamp = pair.$1 == 93;
        final lo = isRamp ? 0.02 : 0.005;
        final hi = isRamp ? 0.35 : 0.15;
        final values = <double>[];
        for (final id in [pair.$1, pair.$2]) {
          final p = _landmarkPixel(f.face, id, f.imageSize);
          expect(p, isNotNull, reason: '${f.id} landmark $id');
          final frac = _absDx(built, p!) / peak;
          expect(
            frac,
            inInclusiveRange(lo, hi),
            reason: '${f.id} id=$id fracção do pico = '
                '${frac.toStringAsFixed(3)}, esperado $lo..$hi',
          );
          values.add(frac);
        }
        final ratio = math.max(values[0], values[1]) /
            math.max(math.min(values[0], values[1]), 1e-9);
        expect(
          ratio,
          lessThan(2.0),
          reason: '${f.id} assimetria ${pair.$1}/${pair.$2} = '
              '${ratio.toStringAsFixed(2)}×',
        );
      }
    }
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
