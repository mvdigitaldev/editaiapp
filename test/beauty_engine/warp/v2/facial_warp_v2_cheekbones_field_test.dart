import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/cheekbones/cheekbones_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/cheekbones/cheekbones_masks.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/displacement_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

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
      final built = CheekbonesField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0,
      );
      expect(built.field.isZero, isTrue, reason: f.id);
      expect(built.metrics.influenceMax, 0, reason: f.id);
      expect(built.metrics.minDetJ, 1, reason: f.id);
      expect(built.metrics.cheekbonesNarrows, isFalse, reason: f.id);
      expect(built.metrics.eyes.p95Abs, 0, reason: f.id);
      expect(built.metrics.mouth.p95Abs, 0, reason: f.id);
      expect(built.metrics.outsideCheekZoneP95, 0, reason: f.id);
      expect(
        built.masks.count(built.masks.cheekActive),
        greaterThan(0),
        reason: f.id,
      );
    }
  });

  test('t=0.5 narrows malar, protects chin/face, mandibular tail weaker than malar', () {
    final reports = <Map<String, Object>>[];
    for (final f in faces) {
      final built = CheekbonesField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 0.5,
      );
      final m = built.metrics;
      final dir = Directory('.cursor/facial-warp-v2/cheekbones/H/${f.id}');
      dir.createSync(recursive: true);
      final json = <String, Object>{
        'id': f.id,
        't': 0.5,
        'hypothesis': 'oval_ridge',
        'primaryLeft': CheekbonesField.primaryLeft,
        'primaryRight': CheekbonesField.primaryRight,
        'amplitudeFaceWidth': CheekbonesField.amplitudeFaceWidth,
        'falloffFaceWidth': CheekbonesField.falloffFaceWidth,
        'leftPad': built.leftPad?.toJson() ?? const <String, Object>{},
        'rightPad': built.rightPad?.toJson() ?? const <String, Object>{},
        ...m.toJson(),
        'foldGate': m.minDetJ > 0,
        'maskCounts': {
          'cheek': built.masks.count(built.masks.cheek),
          'cheekActive': built.masks.count(built.masks.cheekActive),
          'jawDomain': built.masks.count(built.masks.jawDomain),
          'chinDomain': built.masks.count(built.masks.chinDomain),
          'mouth': built.masks.count(built.masks.mouth),
        },
      };
      File('${dir.path}/metrics.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(json),
      );
      _saveMask('${dir.path}/cheekActive.png', built.masks.cheekActive, built.field);
      _saveMask('${dir.path}/protected.png', built.masks.protected, built.field);
      _saveMask('${dir.path}/jawDomain.png', built.masks.jawDomain, built.field);
      _saveMask('${dir.path}/chinDomain.png', built.masks.chinDomain, built.field);
      _saveDisplacement('${dir.path}/displacement.png', built.field);
      _saveInfluence('${dir.path}/influence.png', built.field);
      reports.add(json);

      expect(built.leftPad, isNotNull, reason: f.id);
      expect(built.rightPad, isNotNull, reason: f.id);
      final px = CheekbonesMasks.landmarkPixels(f.face, f.imageSize);
      final orbitL = px[CheekbonesField.orbitLowerLeft];
      final orbitR = px[CheekbonesField.orbitLowerRight];
      if (orbitL != null) {
        expect(
          built.leftPad!.center.dy - orbitL.dy,
          greaterThan(0.06 * m.faceWidth),
          reason: '${f.id} left pad glued to eyelid',
        );
      }
      if (orbitR != null) {
        expect(
          built.rightPad!.center.dy - orbitR.dy,
          greaterThan(0.06 * m.faceWidth),
          reason: '${f.id} right pad glued to eyelid',
        );
      }
      expect(
        m.influenceMax,
        greaterThan(0.5 * m.cheekAmplitude),
        reason: '${f.id} falloff ate the pad',
      );
      expect(
        m.absAtChinTip,
        lessThanOrEqualTo(_protectEps),
        reason: '${f.id} chin must stay locked',
      );
      expect(
        math.max(m.absAtGonionLeft, m.absAtGonionRight),
        lessThan(0.55 * m.influenceMax),
        reason: '${f.id} mandibular tail must stay weaker than malar',
      );
    }
    for (final f in faces) {
      final atOne = CheekbonesField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: 1,
      );
      expect(
        atOne.metrics.minDetJ,
        greaterThan(0),
        reason: '${f.id} fold at t=1 detJ=${atOne.metrics.minDetJ}',
      );
      final expand = CheekbonesField.build(
        face: f.face,
        imageSize: f.imageSize,
        t: -0.5,
      );
      expect(
        expand.metrics.malarWidthAfter,
        greaterThan(expand.metrics.malarWidthBefore),
        reason: '${f.id} negative t should widen malar',
      );
      expect(
        expand.metrics.minDetJ,
        greaterThan(0),
        reason: '${f.id} fold at t=-0.5 detJ=${expand.metrics.minDetJ}',
      );
    }
    expect(reports.length, 3);
    for (final json in reports) {
      expect((json['influenceMax'] as num).toDouble(), greaterThan(0), reason: '${json['id']}');
      expect(
        (json['minDetJ'] as num).toDouble(),
        greaterThan(0),
        reason: '${json['id']} detJ=${json['minDetJ']}',
      );
    }
  });

  test('photo-left t moves the right MediaPipe malar; photo-right t moves the left', () {
    for (final f in faces) {
      final leftOnly = CheekbonesField.build(
        face: f.face,
        imageSize: f.imageSize,
        tPhotoLeft: 0.5,
        tPhotoRight: 0,
      );
      final rightOnly = CheekbonesField.build(
        face: f.face,
        imageSize: f.imageSize,
        tPhotoLeft: 0,
        tPhotoRight: 0.5,
      );
      expect(
        leftOnly.metrics.dxAtPrimaryRight.abs(),
        greaterThan(leftOnly.metrics.dxAtPrimaryLeft.abs() + 0.2),
        reason: '${f.id} Esquerda should move 352, not 123',
      );
      expect(
        rightOnly.metrics.dxAtPrimaryLeft.abs(),
        greaterThan(rightOnly.metrics.dxAtPrimaryRight.abs() + 0.2),
        reason: '${f.id} Direita should move 123, not 352',
      );
      expect(leftOnly.metrics.minDetJ, greaterThan(0), reason: f.id);
      expect(rightOnly.metrics.minDetJ, greaterThan(0), reason: f.id);
    }
  });

  test('runtime cache scales the same unit weights', () {
    final f = faces.first;
    final runtime = CheekbonesFieldRuntime();
    final cold = CheekbonesField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 0.5,
    );
    final warm = CheekbonesField.build(
      face: f.face,
      imageSize: f.imageSize,
      t: 0.5,
      runtime: runtime,
    );
    final again = CheekbonesField.build(
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
      'lib/features/editor/beauty_engine/warp/v2/cheekbones/cheekbones_field.dart',
      'lib/features/editor/beauty_engine/warp/v2/cheekbones/cheekbones_masks.dart',
      'lib/features/editor/beauty_engine/warp/v2/cheekbones/cheekbones_metrics.dart',
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
      expect(source.contains('face_slim_field.dart'), isFalse, reason: path);
      expect(source.contains('face_slim_masks.dart'), isFalse, reason: path);
      expect(source.contains('face_slim_metrics.dart'), isFalse, reason: path);
    }
  });
}

void _saveMask(String path, List<int> mask, DisplacementField field) {
  final image = img.Image(
    width: field.width,
    height: field.height,
    numChannels: 4,
  );
  for (var y = 0; y < field.height; y++) {
    for (var x = 0; x < field.width; x++) {
      final on = mask[y * field.width + x] != 0;
      image.setPixelRgba(x, y, on ? 255 : 0, on ? 255 : 0, on ? 255 : 0, 255);
    }
  }
  File(path).writeAsBytesSync(img.encodePng(image));
}

void _saveDisplacement(String path, DisplacementField field) {
  final image = img.Image(
    width: field.width,
    height: field.height,
    numChannels: 4,
  );
  final scale = field.isZero ? 1.0 : 12.0;
  for (var y = 0; y < field.height; y++) {
    for (var x = 0; x < field.width; x++) {
      final i = field.indexOf(x, y);
      final r = (128 + field.dx[i] * scale).round().clamp(0, 255);
      final g = (128 + field.dy[i] * scale).round().clamp(0, 255);
      image.setPixelRgba(x, y, r, g, 128, 255);
    }
  }
  File(path).writeAsBytesSync(img.encodePng(image));
}

void _saveInfluence(String path, DisplacementField field) {
  var maxMag = 1e-6;
  for (var i = 0; i < field.pixelCount; i++) {
    final mag = math.sqrt(field.dx[i] * field.dx[i] + field.dy[i] * field.dy[i]);
    if (mag > maxMag) {
      maxMag = mag;
    }
  }
  final image = img.Image(
    width: field.width,
    height: field.height,
    numChannels: 4,
  );
  for (var y = 0; y < field.height; y++) {
    for (var x = 0; x < field.width; x++) {
      final i = field.indexOf(x, y);
      final mag = math.sqrt(field.dx[i] * field.dx[i] + field.dy[i] * field.dy[i]);
      final v = ((mag / maxMag) * 255).round().clamp(0, 255);
      image.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  File(path).writeAsBytesSync(img.encodePng(image));
}
