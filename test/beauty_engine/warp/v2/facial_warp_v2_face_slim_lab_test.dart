import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/backward_bilinear_warp.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/displacement_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/face_slim/face_slim_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/face_slim/face_slim_masks.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/region_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../filters/skin/mvp_benchmark_faces.dart';

const _protectEps = 0.5;

const _assets = {
  'real-p01': 'test/beauty_engine/warp/fixtures/phase12/p01-man-5021469.png',
  'real-p05': 'test/beauty_engine/warp/fixtures/phase12/p05-young-woman.png',
  'real-p12': 'test/beauty_engine/warp/fixtures/phase12/p12.jpg',
};

const _dumpIds = {
  'real-p01': 'p01',
  'real-p05': 'p05',
  'real-p12': 'p12',
};

const _levels = [
  (label: '0', t: 0.0),
  (label: '25', t: 0.25),
  (label: '50', t: 0.50),
];

const _dumpRoot = '.cursor/facial-warp-v2/face-slim/B';

class _Photo {
  const _Photo({
    required this.id,
    required this.dumpId,
    required this.face,
    required this.imageSize,
    required this.rgba,
    required this.width,
    required this.height,
  });

  final String id;
  final String dumpId;
  final FaceMeshResult face;
  final Size imageSize;
  final Uint8List rgba;
  final int width;
  final int height;
}

void main() {
  late List<_Photo> photos;

  setUpAll(() {
    final available = loadAvailableRealBenchmarkFaces();
    photos = [
      for (final id in _assets.keys) _loadPhoto(id, available),
    ];
    expect(photos.length, 3);
  });

  test('renderer applies vertical displacement on slimActive', () {
    final photo = photos.first;
    final built = FaceSlimField.build(
      face: photo.face,
      imageSize: photo.imageSize,
      t: 0,
    );
    final field = DisplacementField.zeros(
      width: photo.width,
      height: photo.height,
    );
    var painted = 0;
    var sample = -1;
    for (var i = 0; i < field.pixelCount; i++) {
      if (built.masks.slimActive[i] == 0) {
        continue;
      }
      field.dy[i] = -5;
      painted++;
      final y = i ~/ photo.width;
      if (sample < 0 && y >= 8 && y + 5 < photo.height) {
        sample = i;
      }
    }
    expect(painted, greaterThan(0));
    final warped = BackwardBilinearWarp.apply(
      WarpRequest(
        sourceRgba: photo.rgba,
        width: photo.width,
        height: photo.height,
        field: field,
      ),
    );
    expect(_changedPixelCount(photo.rgba, warped.rgba), greaterThan(0));
    expect(sample, greaterThanOrEqualTo(0));
    final x = sample % photo.width;
    final y = sample ~/ photo.width;
    final srcY = y + 5;
    if (srcY < photo.height) {
      final wi = sample * 4;
      final si = (srcY * photo.width + x) * 4;
      expect(warped.rgba[wi], photo.rgba[si]);
      expect(warped.rgba[wi + 1], photo.rgba[si + 1]);
      expect(warped.rgba[wi + 2], photo.rgba[si + 2]);
    }
  });

  test(
    'Face Slim B lab matrix p01/p05/p12 × face_slim 0/25/50 writes v2Raw without fill',
    () {
      final summary = <Map<String, Object>>[];
      for (final photo in photos) {
        for (final level in _levels) {
          final built = FaceSlimField.build(
            face: photo.face,
            imageSize: photo.imageSize,
            t: level.t,
          );
          expect(built.field.width, photo.width, reason: photo.id);
          expect(built.field.height, photo.height, reason: photo.id);

          final warped = BackwardBilinearWarp.apply(
            WarpRequest(
              sourceRgba: photo.rgba,
              width: photo.width,
              height: photo.height,
              field: built.field,
            ),
          );

          final changed = _changedPixelCount(photo.rgba, warped.rgba);
          var invalidCount = 0;
          var coverageSum = 0;
          for (var i = 0; i < warped.invalidSource.length; i++) {
            if (warped.invalidSource[i] != 0) {
              invalidCount++;
            }
            coverageSum += warped.coverage[i];
          }
          final coverageMean = coverageSum / warped.coverage.length;
          expect(invalidCount, 0, reason: '${photo.id} t=${level.t} invalidSource');

          if (level.t == 0) {
            expect(warped.rgba, photo.rgba, reason: '${photo.id} t=0 v2Raw');
            expect(changed, 0, reason: '${photo.id} t=0 changed');
            expect(built.field.isZero, isTrue);
            expect(built.metrics.faceSlimNarrows, isFalse, reason: photo.id);
          } else {
            expect(changed, greaterThan(0), reason: '${photo.id} t=${level.t}');
            expect(built.metrics.faceSlimNarrows, isTrue, reason: photo.id);
            expect(built.metrics.minDetJ, greaterThan(0), reason: photo.id);
            expect(
              built.metrics.outsideSlimZoneP95,
              lessThanOrEqualTo(_protectEps),
            );
            expect(built.metrics.eyes.p95Abs, lessThanOrEqualTo(_protectEps));
            expect(built.metrics.brows.p95Abs, lessThanOrEqualTo(_protectEps));
            expect(built.metrics.nose.p95Abs, lessThanOrEqualTo(_protectEps));
            expect(built.metrics.mouth.p95Abs, lessThanOrEqualTo(_protectEps));
            expect(
              built.metrics.faceCenter.p95Abs,
              lessThanOrEqualTo(_protectEps),
            );
            expect(built.metrics.ears.p95Abs, lessThanOrEqualTo(_protectEps));
            expect(built.metrics.jawDomain.p95Abs, lessThanOrEqualTo(_protectEps));
            expect(built.metrics.chinDomain.p95Abs, lessThanOrEqualTo(_protectEps));
            expect(
              built.metrics.absAtGonionLeft,
              lessThanOrEqualTo(_protectEps),
            );
            expect(
              built.metrics.absAtGonionRight,
              lessThanOrEqualTo(_protectEps),
            );
            expect(
              built.metrics.absAtChinTip,
              lessThanOrEqualTo(_protectEps),
            );
          }

          final dir = Directory('$_dumpRoot/${photo.dumpId}/${level.label}');
          dir.createSync(recursive: true);
          final continuity = _writeArtifacts(
            dir: dir.path,
            photo: photo,
            field: built.field,
            masks: built.masks,
            warped: warped,
          );
          final row = <String, Object>{
            'id': photo.dumpId,
            't': level.t,
            'changedPixelCount': changed,
            'invalidCount': invalidCount,
            'coverageMean': coverageMean,
            'hashV2Raw': _hash(warped.rgba),
            ...built.metrics.toJson(),
            ...continuity,
          };
          File('${dir.path}/metrics.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(row),
          );
          summary.add(row);
        }
      }

      expect(summary.length, 9);
      File('$_dumpRoot/summary.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(summary),
      );
      for (final photo in photos) {
        for (final level in _levels) {
          expect(
            File('$_dumpRoot/${photo.dumpId}/${level.label}/v2Raw.png')
                .existsSync(),
            isTrue,
          );
          expect(
            File(
              '$_dumpRoot/${photo.dumpId}/${level.label}/fieldGradient.png',
            ).existsSync(),
            isTrue,
          );
          expect(
            File(
              '$_dumpRoot/${photo.dumpId}/${level.label}/displacementIsolines.png',
            ).existsSync(),
            isTrue,
          );
          expect(
            File(
              '$_dumpRoot/${photo.dumpId}/${level.label}/silhouetteCurvature.json',
            ).existsSync(),
            isTrue,
          );
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('Face Slim B lab test does not import V1 fill, pipeline, Fields or controller',
      () {
    final imports = File(
      'test/beauty_engine/warp/v2/facial_warp_v2_face_slim_lab_test.dart',
    )
        .readAsLinesSync()
        .where((line) => line.trimLeft().startsWith('import '))
        .join('\n');
    expect(imports.contains('hole_fill_inpaint'), isFalse);
    expect(imports.contains('telea'), isFalse);
    expect(imports.contains('contour_band_fill'), isFalse);
    expect(imports.contains('semantic_released_fill'), isFalse);
    expect(imports.contains('extended_roi'), isFalse);
    expect(imports.contains('pass_warp'), isFalse);
    expect(imports.contains('beauty_engine_controller'), isFalse);
    expect(imports.contains('facial_warp_v2_device_lab'), isFalse);
    expect(imports.contains('jaw_field.dart'), isFalse);
    expect(imports.contains('chin_field.dart'), isFalse);
  });
}

_Photo _loadPhoto(
  String id,
  List<({String id, String label, FaceMeshResult face, Size imageSize})>
      available,
) {
  final match = available.where((f) => f.id == id);
  expect(match, isNotEmpty, reason: 'landmarks $id');
  final asset = _assets[id]!;
  expect(File(asset).existsSync(), isTrue, reason: asset);
  final decoded = img.decodeImage(File(asset).readAsBytesSync());
  expect(decoded, isNotNull, reason: 'decode $asset');
  final width = decoded!.width;
  final height = decoded.height;
  expect(width, match.first.imageSize.width.round(), reason: '$id width');
  expect(height, match.first.imageSize.height.round(), reason: '$id height');
  final rgba = Uint8List(width * height * 4);
  var o = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final p = decoded.getPixel(x, y);
      rgba[o++] = p.r.toInt();
      rgba[o++] = p.g.toInt();
      rgba[o++] = p.b.toInt();
      rgba[o++] = p.a.toInt();
    }
  }
  return _Photo(
    id: id,
    dumpId: _dumpIds[id]!,
    face: match.first.face,
    imageSize: Size(width.toDouble(), height.toDouble()),
    rgba: rgba,
    width: width,
    height: height,
  );
}

Map<String, Object> _writeArtifacts({
  required String dir,
  required _Photo photo,
  required DisplacementField field,
  required FaceSlimMasks masks,
  required WarpResult warped,
}) {
  _saveRgba('$dir/original.png', photo.rgba, photo.width, photo.height);
  _saveRgba('$dir/v2Raw.png', warped.rgba, photo.width, photo.height);
  _saveGray('$dir/coverage.png', warped.coverage, photo.width, photo.height);
  _saveMask(
    '$dir/invalidSource.png',
    warped.invalidSource,
    photo.width,
    photo.height,
  );
  _saveDisplacement('$dir/displacementField.png', field);
  _saveInfluence('$dir/influenceMap.png', field);
  _saveMask('$dir/protectedMask.png', masks.protected, photo.width, photo.height);
  _saveOwnership(
    '$dir/ownershipMap.png',
    masks,
    warped.invalidSource,
    photo.width,
    photo.height,
  );
  final continuity = _analyzeContinuity(photo, field, masks);
  _saveGradientHeatmaps(dir, field, continuity);
  _saveIsolines('$dir/displacementIsolines.png', photo, field);
  _saveJawSpline('$dir/jawSpline.png', photo);
  File('$dir/continuity.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(continuity.json),
  );
  final silhouette = _analyzeSilhouette(photo, field);
  _saveSilhouetteOverlay('$dir/silhouetteCurvature.png', photo, silhouette);
  _saveSilhouettePlot('$dir/silhouetteCurvaturePlot.png', silhouette);
  File('$dir/silhouetteCurvature.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(silhouette.json),
  );
  return {
    'gradDxP95': continuity.json['gradDxP95']!,
    'gradDyP95': continuity.json['gradDyP95']!,
    'maxAngleJumpDegNearGonion':
        continuity.json['maxAngleJumpDegNearGonion']!,
    'kinkNearGonion': continuity.json['kinkNearGonion']!,
    ...silhouette.summary,
  };
}

void _saveRgba(String path, Uint8List rgba, int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  var o = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(x, y, rgba[o], rgba[o + 1], rgba[o + 2], rgba[o + 3]);
      o += 4;
    }
  }
  File(path).writeAsBytesSync(img.encodePng(image));
}

void _saveGray(String path, Uint8List bytes, int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final v = bytes[y * width + x];
      image.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  File(path).writeAsBytesSync(img.encodePng(image));
}

void _saveMask(String path, Uint8List mask, int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final on = mask[y * width + x] != 0;
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

void _saveOwnership(
  String path,
  FaceSlimMasks masks,
  Uint8List invalidSource,
  int width,
  int height,
) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = y * width + x;
      final r = masks.protected[i] != 0 ? 220 : 20;
      final g = masks.slimActive[i] != 0 ? 200 : 20;
      final b = invalidSource[i] != 0 ? 255 : 20;
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  File(path).writeAsBytesSync(img.encodePng(image));
}

class _ContinuityDump {
  const _ContinuityDump({
    required this.gradDx,
    required this.gradDy,
    required this.json,
  });

  final Float32List gradDx;
  final Float32List gradDy;
  final Map<String, Object> json;
}

_ContinuityDump _analyzeContinuity(
  _Photo photo,
  DisplacementField field,
  FaceSlimMasks masks,
) {
  final width = field.width;
  final height = field.height;
  final gradDx = Float32List(field.pixelCount);
  final gradDy = Float32List(field.pixelCount);
  final gradDxVals = <double>[];
  final gradDyVals = <double>[];
  var maxGradDx = 0.0;
  var maxGradDy = 0.0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = y * width + x;
      if (masks.slimActive[i] == 0) {
        continue;
      }
      final dxx = x + 1 < width ? (field.dx[i + 1] - field.dx[i]).abs() : 0.0;
      final dxy = y + 1 < height ? (field.dx[i + width] - field.dx[i]).abs() : 0.0;
      final dyx = x + 1 < width ? (field.dy[i + 1] - field.dy[i]).abs() : 0.0;
      final dyy = y + 1 < height ? (field.dy[i + width] - field.dy[i]).abs() : 0.0;
      final gdx = math.sqrt(dxx * dxx + dxy * dxy);
      final gdy = math.sqrt(dyx * dyx + dyy * dyy);
      gradDx[i] = gdx;
      gradDy[i] = gdy;
      gradDxVals.add(gdx);
      gradDyVals.add(gdy);
      maxGradDx = math.max(maxGradDx, gdx);
      maxGradDy = math.max(maxGradDy, gdy);
    }
  }

  final px = FaceSlimMasks.landmarkPixels(photo.face, photo.imageSize);
  final ovalSamples = <Map<String, Object>>[];
  final ovalIds = V2RegionCatalog.faceOval.toList();
  var prevAngle = 0.0;
  var prevS = 0.0;
  var prevMag = 0.0;
  var hasPrev = false;
  var s = 0.0;
  Offset? prevPt;
  var maxAngleJump = 0.0;
  var maxAngleJumpNearGonion = 0.0;
  var maxDmagDsNearGonion = 0.0;
  const gonions = {58, 288, 132, 361};
  for (var k = 0; k < ovalIds.length; k++) {
    final id = ovalIds[k];
    final p = id < px.length ? px[id] : null;
    if (p == null) {
      continue;
    }
    if (prevPt != null) {
      s += (p - prevPt).distance;
    }
    prevPt = p;
    final sampled = _sampleField(field, p);
    final mag = math.sqrt(
      sampled.dx * sampled.dx + sampled.dy * sampled.dy,
    );
    final angle = math.atan2(sampled.dy, sampled.dx) * 180 / math.pi;
    var dAngle = 0.0;
    var dMagDs = 0.0;
    if (hasPrev) {
      final ds = math.max(s - prevS, 1e-6);
      dMagDs = (mag - prevMag).abs() / ds;
      if (mag > 0.05 && prevMag > 0.05) {
        dAngle = _angleDeltaDeg(angle, prevAngle);
        maxAngleJump = math.max(maxAngleJump, dAngle.abs());
        final near = gonions.contains(id) ||
            (k > 0 && gonions.contains(ovalIds[k - 1]));
        if (near) {
          maxAngleJumpNearGonion =
              math.max(maxAngleJumpNearGonion, dAngle.abs());
          maxDmagDsNearGonion = math.max(maxDmagDsNearGonion, dMagDs);
        }
      } else if (gonions.contains(id) ||
          (k > 0 && gonions.contains(ovalIds[k - 1]))) {
        maxDmagDsNearGonion = math.max(maxDmagDsNearGonion, dMagDs);
      }
    }
    ovalSamples.add({
      'id': id,
      's': s,
      'dx': sampled.dx,
      'dy': sampled.dy,
      'mag': mag,
      'angleDeg': angle,
      'dAngleDeg': dAngle,
      'dMagDs': dMagDs,
      'gonion': gonions.contains(id),
    });
    prevAngle = angle;
    prevS = s;
    prevMag = mag;
    hasPrev = true;
  }

  return _ContinuityDump(
    gradDx: gradDx,
    gradDy: gradDy,
    json: {
      'gradDxP95': _p95(gradDxVals),
      'gradDyP95': _p95(gradDyVals),
      'gradDxMax': maxGradDx,
      'gradDyMax': maxGradDy,
      'maxAngleJumpDegAlongOval': maxAngleJump,
      'maxAngleJumpDegNearGonion': maxAngleJumpNearGonion,
      'maxDmagDsNearGonion': maxDmagDsNearGonion,
      'kinkNearGonion': maxAngleJumpNearGonion > 25,
      'ovalSamples': ovalSamples,
    },
  );
}

({double dx, double dy}) _sampleField(DisplacementField field, Offset p) {
  final x = p.dx.round().clamp(0, field.width - 1);
  final y = p.dy.round().clamp(0, field.height - 1);
  final i = field.indexOf(x, y);
  return (dx: field.dx[i], dy: field.dy[i]);
}

double _angleDeltaDeg(double a, double b) {
  var d = a - b;
  while (d > 180) {
    d -= 360;
  }
  while (d < -180) {
    d += 360;
  }
  return d;
}

double _p95(List<double> values) {
  if (values.isEmpty) {
    return 0;
  }
  values.sort();
  final i = ((values.length - 1) * 0.95).floor().clamp(0, values.length - 1);
  return values[i];
}

void _saveGradientHeatmaps(
  String dir,
  DisplacementField field,
  _ContinuityDump continuity,
) {
  final p95x = math.max(continuity.json['gradDxP95']! as double, 1e-6);
  final p95y = math.max(continuity.json['gradDyP95']! as double, 1e-6);
  final packed = img.Image(
    width: field.width,
    height: field.height,
    numChannels: 4,
  );
  final magImg = img.Image(
    width: field.width,
    height: field.height,
    numChannels: 4,
  );
  final scaleX = 1.5 / p95x;
  final scaleY = 1.5 / p95y;
  for (var y = 0; y < field.height; y++) {
    for (var x = 0; x < field.width; x++) {
      final i = y * field.width + x;
      final rx = (continuity.gradDx[i] * scaleX * 255).round().clamp(0, 255);
      final gy = (continuity.gradDy[i] * scaleY * 255).round().clamp(0, 255);
      packed.setPixelRgba(x, y, rx, gy, 0, 255);
      final mag = math.sqrt(
        continuity.gradDx[i] * continuity.gradDx[i] +
            continuity.gradDy[i] * continuity.gradDy[i],
      );
      final t = (mag / math.max(p95x, p95y) * 0.75).clamp(0.0, 1.0);
      magImg.setPixelRgba(
        x,
        y,
        (255 * t).round(),
        (80 * t).round(),
        (20 + 40 * (1 - t)).round(),
        255,
      );
    }
  }
  File('$dir/fieldGradient.png').writeAsBytesSync(img.encodePng(packed));
  File('$dir/fieldGradientMagnitude.png').writeAsBytesSync(img.encodePng(magImg));
}

void _saveIsolines(String path, _Photo photo, DisplacementField field) {
  var maxMag = 1e-6;
  final mag = Float32List(field.pixelCount);
  for (var i = 0; i < field.pixelCount; i++) {
    mag[i] = math.sqrt(field.dx[i] * field.dx[i] + field.dy[i] * field.dy[i]);
    if (mag[i] > maxMag) {
      maxMag = mag[i];
    }
  }
  final image = img.Image(
    width: photo.width,
    height: photo.height,
    numChannels: 4,
  );
  for (var y = 0; y < photo.height; y++) {
    for (var x = 0; x < photo.width; x++) {
      final o = (y * photo.width + x) * 4;
      final shade = (photo.rgba[o] * 0.35).round();
      image.setPixelRgba(x, y, shade, shade, shade, 255);
    }
  }
  const levels = [0.15, 0.30, 0.45, 0.60, 0.75, 0.90];
  for (final level in levels) {
    final thr = level * maxMag;
    final tone = (80 + level * 175).round();
    for (var y = 0; y < field.height; y++) {
      for (var x = 0; x < field.width; x++) {
        final i = y * field.width + x;
        if (mag[i] < 1e-6) {
          continue;
        }
        final crossX = x + 1 < field.width &&
            (mag[i] - thr) * (mag[i + 1] - thr) <= 0 &&
            (mag[i] > 1e-6 || mag[i + 1] > 1e-6);
        final crossY = y + 1 < field.height &&
            (mag[i] - thr) * (mag[i + field.width] - thr) <= 0 &&
            (mag[i] > 1e-6 || mag[i + field.width] > 1e-6);
        if (crossX || crossY) {
          image.setPixelRgba(x, y, tone, 220, 255 - tone, 255);
        }
      }
    }
  }
  File(path).writeAsBytesSync(img.encodePng(image));
}

void _saveJawSpline(String path, _Photo photo) {
  final image = img.Image(
    width: photo.width,
    height: photo.height,
    numChannels: 4,
  );
  var o = 0;
  for (var y = 0; y < photo.height; y++) {
    for (var x = 0; x < photo.width; x++) {
      image.setPixelRgba(
        x,
        y,
        photo.rgba[o],
        photo.rgba[o + 1],
        photo.rgba[o + 2],
        255,
      );
      o += 4;
    }
  }
  final px = FaceSlimMasks.landmarkPixels(photo.face, photo.imageSize);
  _strokeChain(image, px, FaceSlimField.leftJawChain, 255, 210, 40);
  _strokeChain(image, px, FaceSlimField.rightJawChain, 255, 210, 40);
  _dot(image, px, FaceSlimField.gonionLeft, 255, 40, 80, 5);
  _dot(image, px, FaceSlimField.gonionRight, 255, 40, 80, 5);
  _dot(image, px, FaceSlimField.primaryLeft, 40, 220, 255, 4);
  _dot(image, px, FaceSlimField.primaryRight, 40, 220, 255, 4);
  File(path).writeAsBytesSync(img.encodePng(image));
}

void _strokeChain(
  img.Image image,
  List<Offset?> px,
  List<int> chain,
  int r,
  int g,
  int b,
) {
  Offset? prev;
  for (final id in chain) {
    final p = id < px.length ? px[id] : null;
    if (p == null) {
      continue;
    }
    if (prev != null) {
      img.drawLine(
        image,
        x1: prev.dx.round(),
        y1: prev.dy.round(),
        x2: p.dx.round(),
        y2: p.dy.round(),
        color: img.ColorRgb8(r, g, b),
        thickness: 2,
      );
    }
    prev = p;
  }
}

void _dot(
  img.Image image,
  List<Offset?> px,
  int id,
  int r,
  int g,
  int b,
  int radius,
) {
  final p = id < px.length ? px[id] : null;
  if (p == null) {
    return;
  }
  img.fillCircle(
    image,
    x: p.dx.round(),
    y: p.dy.round(),
    radius: radius,
    color: img.ColorRgb8(r, g, b),
  );
}

class _SilhouetteDump {
  const _SilhouetteDump({
    required this.json,
    required this.summary,
    required this.left,
    required this.right,
  });

  final Map<String, Object> json;
  final Map<String, Object> summary;
  final _SilhouetteSide left;
  final _SilhouetteSide right;
}

class _SilhouetteSide {
  const _SilhouetteSide({
    required this.name,
    required this.orig,
    required this.warped,
    required this.samples,
    required this.envelopeZeroU,
    required this.uMaxAbsDTheta,
    required this.uMaxAbsDThetaTail,
    required this.maxAbsDThetaDeg,
    required this.maxAbsDThetaTailDeg,
    required this.maxAbsDThetaHeadDeg,
    required this.maxAbsDThetaActiveTailDeg,
    required this.uMaxAbsDThetaActiveTail,
    required this.peakAtEnvelopeZero,
    required this.tailDominates,
    required this.activeTailAtEnvelopeZero,
  });

  final String name;
  final List<Offset> orig;
  final List<Offset> warped;
  final List<Map<String, Object>> samples;
  final double envelopeZeroU;
  final double uMaxAbsDTheta;
  final double uMaxAbsDThetaTail;
  final double maxAbsDThetaDeg;
  final double maxAbsDThetaTailDeg;
  final double maxAbsDThetaHeadDeg;
  final double maxAbsDThetaActiveTailDeg;
  final double uMaxAbsDThetaActiveTail;
  final bool peakAtEnvelopeZero;
  final bool tailDominates;
  final bool activeTailAtEnvelopeZero;

  bool get hardZeroSuspected =>
      activeTailAtEnvelopeZero && maxAbsDThetaActiveTailDeg >= 8;

  Map<String, Object> toJson() => {
        'envelopeZeroU': envelopeZeroU,
        'uMaxAbsDTheta': uMaxAbsDTheta,
        'uMaxAbsDThetaTail15': uMaxAbsDThetaTail,
        'maxAbsDThetaDeg': maxAbsDThetaDeg,
        'maxAbsDThetaTail15Deg': maxAbsDThetaTailDeg,
        'maxAbsDThetaHead85Deg': maxAbsDThetaHeadDeg,
        'maxAbsDThetaActiveTailDeg': maxAbsDThetaActiveTailDeg,
        'uMaxAbsDThetaActiveTail': uMaxAbsDThetaActiveTail,
        'peakAtEnvelopeZero': peakAtEnvelopeZero,
        'activeTailAtEnvelopeZero': activeTailAtEnvelopeZero,
        'tailDominates': tailDominates,
        'hardZeroBoundarySuspected': hardZeroSuspected,
        'samples': samples,
      };
}

_SilhouetteDump _analyzeSilhouette(_Photo photo, DisplacementField field) {
  final px = FaceSlimMasks.landmarkPixels(photo.face, photo.imageSize);
  final leftIds = _chainUntil(FaceSlimField.leftJawChain, FaceSlimField.gonionLeft);
  final rightIds = _chainUntil(
    FaceSlimField.rightJawChain,
    FaceSlimField.gonionRight,
  );
  final left = _analyzeSilhouetteSide('left', px, leftIds, field);
  final right = _analyzeSilhouetteSide('right', px, rightIds, field);
  final suspected = left.hardZeroSuspected || right.hardZeroSuspected;
  return _SilhouetteDump(
    left: left,
    right: right,
    json: {
      'hardZeroBoundarySuspected': suspected,
      'alignToleranceU': 0.08,
      'tailWindowU': 0.85,
      'left': left.toJson(),
      'right': right.toJson(),
    },
    summary: {
      'hardZeroBoundarySuspected': suspected,
      'leftEnvelopeZeroU': left.envelopeZeroU,
      'rightEnvelopeZeroU': right.envelopeZeroU,
      'leftPeakAtEnvelopeZero': left.peakAtEnvelopeZero,
      'rightPeakAtEnvelopeZero': right.peakAtEnvelopeZero,
      'leftTailMaxDThetaDeg': left.maxAbsDThetaTailDeg,
      'rightTailMaxDThetaDeg': right.maxAbsDThetaTailDeg,
      'leftUMaxDThetaActiveTail': left.uMaxAbsDThetaActiveTail,
      'rightUMaxDThetaActiveTail': right.uMaxAbsDThetaActiveTail,
      'leftActiveTailDThetaDeg': left.maxAbsDThetaActiveTailDeg,
      'rightActiveTailDThetaDeg': right.maxAbsDThetaActiveTailDeg,
    },
  );
}

List<int> _chainUntil(List<int> chain, int endId) {
  final i = chain.indexOf(endId);
  if (i < 0) {
    return List<int>.from(chain);
  }
  return chain.sublist(0, i + 1);
}

_SilhouetteSide _analyzeSilhouetteSide(
  String name,
  List<Offset?> px,
  List<int> ids,
  DisplacementField field,
) {
  final orig = _densifyChain(px, ids);
  final empty = _SilhouetteSide(
    name: name,
    orig: orig,
    warped: orig,
    samples: const [],
    envelopeZeroU: 1,
    uMaxAbsDTheta: 1,
    uMaxAbsDThetaTail: 1,
    maxAbsDThetaDeg: 0,
    maxAbsDThetaTailDeg: 0,
    maxAbsDThetaHeadDeg: 0,
    peakAtEnvelopeZero: false,
    tailDominates: false,
    maxAbsDThetaActiveTailDeg: 0,
    uMaxAbsDThetaActiveTail: 1,
    activeTailAtEnvelopeZero: false,
  );
  if (orig.length < 5) {
    return empty;
  }

  final warped = <Offset>[];
  final mag = <double>[];
  var peakMag = 0.0;
  for (final p in orig) {
    final d = _sampleFieldBilinear(field, p);
    final m = math.sqrt(d.dx * d.dx + d.dy * d.dy);
    mag.add(m);
    warped.add(Offset(p.dx + d.dx, p.dy + d.dy));
    if (m > peakMag) {
      peakMag = m;
    }
  }

  final s = <double>[0];
  var total = 0.0;
  for (var i = 1; i < orig.length; i++) {
    total += (orig[i] - orig[i - 1]).distance;
    s.add(total);
  }
  if (total < 1e-6) {
    return empty;
  }

  final dThetaOrig = _turningDeg(orig);
  final dThetaWarp = _turningDeg(warped);
  final samples = <Map<String, Object>>[];
  var uEnvelopeZero = 1.0;
  var foundZero = false;
  var passedPeak = false;
  final zeroThr = math.max(0.5, 0.05 * peakMag);

  var maxAbs = 0.0;
  var uMaxAbs = 0.0;
  var maxTail = 0.0;
  var uMaxTail = 0.85;
  var maxHead = 0.0;
  var maxActiveTail = 0.0;
  var uMaxActiveTail = 0.0;

  for (var i = 0; i < orig.length; i++) {
    final u = s[i] / total;
    final dOrig = i < dThetaOrig.length ? dThetaOrig[i] : 0.0;
    final dWarp = i < dThetaWarp.length ? dThetaWarp[i] : 0.0;
    final dDelta = _angleDeltaDeg(dWarp, dOrig);
    if (mag[i] >= peakMag * 0.95 && peakMag > 1e-6) {
      passedPeak = true;
    }
    if (!foundZero && passedPeak && mag[i] <= zeroThr) {
      uEnvelopeZero = u;
      foundZero = true;
    }
    final absD = dDelta.abs();
    if (absD > maxAbs) {
      maxAbs = absD;
      uMaxAbs = u;
    }
    if (u >= 0.85) {
      if (absD > maxTail) {
        maxTail = absD;
        uMaxTail = u;
      }
    } else if (absD > maxHead) {
      maxHead = absD;
    }
    samples.add({
      'i': i,
      'u': u,
      'x': orig[i].dx,
      'y': orig[i].dy,
      'wx': warped[i].dx,
      'wy': warped[i].dy,
      'mag': mag[i],
      'dThetaOrigDeg': dOrig,
      'dThetaWarpDeg': dWarp,
      'dThetaDeltaDeg': dDelta,
    });
  }
  if (!foundZero && peakMag <= zeroThr) {
    uEnvelopeZero = 0;
  }

  final activeStart = uEnvelopeZero * 0.85;
  for (final sample in samples) {
    final u = sample['u']! as double;
    final absD = (sample['dThetaDeltaDeg']! as double).abs();
    if (u >= activeStart && u <= uEnvelopeZero + 0.02) {
      if (absD > maxActiveTail) {
        maxActiveTail = absD;
        uMaxActiveTail = u;
      }
    }
  }
  if (uMaxActiveTail == 0 && samples.isNotEmpty) {
    uMaxActiveTail = uEnvelopeZero;
  }

  final peakAtZero = maxAbs >= 8 && (uMaxAbs - uEnvelopeZero).abs() <= 0.08;
  final activeAtZero =
      maxActiveTail >= 8 && (uMaxActiveTail - uEnvelopeZero).abs() <= 0.08;
  final tailDominates = maxTail > 1.5 * math.max(maxHead, 1e-6);

  return _SilhouetteSide(
    name: name,
    orig: orig,
    warped: warped,
    samples: samples,
    envelopeZeroU: uEnvelopeZero,
    uMaxAbsDTheta: uMaxAbs,
    uMaxAbsDThetaTail: uMaxTail,
    maxAbsDThetaDeg: maxAbs,
    maxAbsDThetaTailDeg: maxTail,
    maxAbsDThetaHeadDeg: maxHead,
    maxAbsDThetaActiveTailDeg: maxActiveTail,
    uMaxAbsDThetaActiveTail: uMaxActiveTail,
    peakAtEnvelopeZero: peakAtZero,
    tailDominates: tailDominates,
    activeTailAtEnvelopeZero: activeAtZero,
  );
}

List<double> _turningDeg(List<Offset> pts) {
  final out = List<double>.filled(pts.length, 0);
  for (var i = 1; i < pts.length - 1; i++) {
    final a = pts[i] - pts[i - 1];
    final b = pts[i + 1] - pts[i];
    if (a.distance < 1e-6 || b.distance < 1e-6) {
      continue;
    }
    final t0 = math.atan2(a.dy, a.dx) * 180 / math.pi;
    final t1 = math.atan2(b.dy, b.dx) * 180 / math.pi;
    out[i] = _angleDeltaDeg(t1, t0);
  }
  return out;
}

List<Offset> _densifyChain(List<Offset?> px, List<int> ids) {
  final pts = <Offset>[];
  for (final id in ids) {
    final p = id >= 0 && id < px.length ? px[id] : null;
    if (p != null) {
      pts.add(p);
    }
  }
  if (pts.length < 2) {
    return pts;
  }
  final dense = <Offset>[];
  for (var i = 0; i < pts.length - 1; i++) {
    final p0 = i == 0 ? pts[i] : pts[i - 1];
    final p1 = pts[i];
    final p2 = pts[i + 1];
    final p3 = i + 2 < pts.length ? pts[i + 2] : pts[i + 1];
    for (var k = 0; k < 20; k++) {
      dense.add(_catmull(p0, p1, p2, p3, k / 20));
    }
  }
  dense.add(pts.last);
  return dense;
}

Offset _catmull(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
  final t2 = t * t;
  final t3 = t2 * t;
  return Offset(
    0.5 *
        (2 * p1.dx +
            (-p0.dx + p2.dx) * t +
            (2 * p0.dx - 5 * p1.dx + 4 * p2.dx - p3.dx) * t2 +
            (-p0.dx + 3 * p1.dx - 3 * p2.dx + p3.dx) * t3),
    0.5 *
        (2 * p1.dy +
            (-p0.dy + p2.dy) * t +
            (2 * p0.dy - 5 * p1.dy + 4 * p2.dy - p3.dy) * t2 +
            (-p0.dy + 3 * p1.dy - 3 * p2.dy + p3.dy) * t3),
  );
}

({double dx, double dy}) _sampleFieldBilinear(
  DisplacementField field,
  Offset p,
) {
  final x = p.dx.clamp(0.0, field.width - 1.001);
  final y = p.dy.clamp(0.0, field.height - 1.001);
  final x0 = x.floor();
  final y0 = y.floor();
  final x1 = math.min(x0 + 1, field.width - 1);
  final y1 = math.min(y0 + 1, field.height - 1);
  final tx = x - x0;
  final ty = y - y0;
  double dxAt(int ix, int iy) => field.dx[field.indexOf(ix, iy)];
  double dyAt(int ix, int iy) => field.dy[field.indexOf(ix, iy)];
  final dx = dxAt(x0, y0) * (1 - tx) * (1 - ty) +
      dxAt(x1, y0) * tx * (1 - ty) +
      dxAt(x0, y1) * (1 - tx) * ty +
      dxAt(x1, y1) * tx * ty;
  final dy = dyAt(x0, y0) * (1 - tx) * (1 - ty) +
      dyAt(x1, y0) * tx * (1 - ty) +
      dyAt(x0, y1) * (1 - tx) * ty +
      dyAt(x1, y1) * tx * ty;
  return (dx: dx, dy: dy);
}

void _saveSilhouetteOverlay(
  String path,
  _Photo photo,
  _SilhouetteDump dump,
) {
  final image = img.Image(
    width: photo.width,
    height: photo.height,
    numChannels: 4,
  );
  var o = 0;
  for (var y = 0; y < photo.height; y++) {
    for (var x = 0; x < photo.width; x++) {
      image.setPixelRgba(
        x,
        y,
        (photo.rgba[o] * 0.45).round(),
        (photo.rgba[o + 1] * 0.45).round(),
        (photo.rgba[o + 2] * 0.45).round(),
        255,
      );
      o += 4;
    }
  }
  for (final side in [dump.left, dump.right]) {
    _strokeOffsets(image, side.orig, 80, 220, 255, 2);
    _strokeOffsets(image, side.warped, 255, 70, 200, 2);
    _markAtU(image, side.orig, side.envelopeZeroU, 255, 220, 40, 6);
    _markAtU(image, side.orig, side.uMaxAbsDThetaActiveTail, 255, 40, 40, 5);
  }
  File(path).writeAsBytesSync(img.encodePng(image));
}

void _strokeOffsets(
  img.Image image,
  List<Offset> pts,
  int r,
  int g,
  int b,
  int thickness,
) {
  for (var i = 1; i < pts.length; i++) {
    img.drawLine(
      image,
      x1: pts[i - 1].dx.round(),
      y1: pts[i - 1].dy.round(),
      x2: pts[i].dx.round(),
      y2: pts[i].dy.round(),
      color: img.ColorRgb8(r, g, b),
      thickness: thickness,
    );
  }
}

void _markAtU(
  img.Image image,
  List<Offset> pts,
  double u,
  int r,
  int g,
  int b,
  int radius,
) {
  if (pts.isEmpty) {
    return;
  }
  var total = 0.0;
  for (var i = 1; i < pts.length; i++) {
    total += (pts[i] - pts[i - 1]).distance;
  }
  if (total < 1e-6) {
    return;
  }
  var s = 0.0;
  var best = pts.first;
  var bestU = 1e9;
  for (var i = 0; i < pts.length; i++) {
    if (i > 0) {
      s += (pts[i] - pts[i - 1]).distance;
    }
    final ui = s / total;
    if ((ui - u).abs() < bestU) {
      bestU = (ui - u).abs();
      best = pts[i];
    }
  }
  img.fillCircle(
    image,
    x: best.dx.round(),
    y: best.dy.round(),
    radius: radius,
    color: img.ColorRgb8(r, g, b),
  );
}

void _saveSilhouettePlot(String path, _SilhouetteDump dump) {
  const w = 720;
  const h = 360;
  final image = img.Image(width: w, height: h, numChannels: 4);
  img.fill(image, color: img.ColorRgb8(18, 18, 24));
  _drawSidePlot(image, dump.left, 0, w, h ~/ 2);
  _drawSidePlot(image, dump.right, h ~/ 2, w, h ~/ 2);
  File(path).writeAsBytesSync(img.encodePng(image));
}

void _drawSidePlot(
  img.Image image,
  _SilhouetteSide side,
  int y0,
  int w,
  int h,
) {
  const padL = 48;
  const padR = 16;
  const padT = 18;
  const padB = 22;
  var maxY = 1.0;
  for (final s in side.samples) {
    maxY = math.max(maxY, (s['dThetaDeltaDeg']! as double).abs());
  }
  maxY = math.max(maxY, 2.0);
  int sx(double u) => (padL + u * (w - padL - padR)).round();
  int sy(double v) {
    final t = ((v / maxY) + 1) * 0.5;
    return y0 + padT + ((1 - t) * (h - padT - padB)).round();
  }

  img.drawLine(
    image,
    x1: padL,
    y1: sy(0),
    x2: w - padR,
    y2: sy(0),
    color: img.ColorRgb8(60, 60, 70),
  );
  img.drawLine(
    image,
    x1: sx(0.85),
    y1: y0 + padT,
    x2: sx(0.85),
    y2: y0 + h - padB,
    color: img.ColorRgb8(50, 50, 90),
  );
  img.drawLine(
    image,
    x1: sx(side.envelopeZeroU),
    y1: y0 + padT,
    x2: sx(side.envelopeZeroU),
    y2: y0 + h - padB,
    color: img.ColorRgb8(255, 210, 40),
  );
  img.drawLine(
    image,
    x1: sx(side.uMaxAbsDThetaActiveTail),
    y1: y0 + padT,
    x2: sx(side.uMaxAbsDThetaActiveTail),
    y2: y0 + h - padB,
    color: img.ColorRgb8(255, 60, 60),
  );
  Offset? prev;
  for (final s in side.samples) {
    final u = s['u']! as double;
    final v = s['dThetaDeltaDeg']! as double;
    final p = Offset(sx(u).toDouble(), sy(v).toDouble());
    if (prev != null) {
      img.drawLine(
        image,
        x1: prev.dx.round(),
        y1: prev.dy.round(),
        x2: p.dx.round(),
        y2: p.dy.round(),
        color: img.ColorRgb8(120, 220, 255),
        thickness: 2,
      );
    }
    prev = p;
  }
}

int _changedPixelCount(Uint8List a, Uint8List b) {
  var n = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) {
      n++;
    }
  }
  return n;
}

String _hash(Uint8List bytes) {
  var h = 2166136261;
  for (var i = 0; i < bytes.length; i++) {
    h ^= bytes[i];
    h = 0x1fffffff & (h * 16777619);
  }
  return h.toRadixString(16).padLeft(8, '0');
}
