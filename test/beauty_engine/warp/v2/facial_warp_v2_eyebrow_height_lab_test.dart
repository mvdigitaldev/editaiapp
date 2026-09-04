import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/backward_bilinear_warp.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/displacement_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/eyebrow_height/eyebrow_height_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/eyebrow_height/eyebrow_height_masks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../filters/skin/mvp_benchmark_faces.dart';

const _protectEps = 0.5;
const _coreCeiling = 0.30;
const _entryCeiling = 0.25;

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
  (label: '-100', t: -1.0, tPhotoLeft: null, tPhotoRight: null),
  (label: '-50', t: -0.50, tPhotoLeft: null, tPhotoRight: null),
  (label: '0', t: 0.0, tPhotoLeft: null, tPhotoRight: null),
  (label: '50', t: 0.50, tPhotoLeft: null, tPhotoRight: null),
  (label: '100', t: 1.0, tPhotoLeft: null, tPhotoRight: null),
  (label: 'L100', t: 0.0, tPhotoLeft: 1.0, tPhotoRight: 0.0),
  (label: 'R100', t: 0.0, tPhotoLeft: 0.0, tPhotoRight: 1.0),
];

const _dumpRoot = '.cursor/facial-warp-v2/eyebrow_height/B';

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

  test(
    'Eyebrow Height B lab matrix p01/p05/p12 × geral ±100/±50/0 + L/R writes v2Raw without fill',
    () {
      final summary = <Map<String, Object>>[];
      for (final photo in photos) {
        for (final level in _levels) {
          final built = EyebrowHeightField.build(
            face: photo.face,
            imageSize: photo.imageSize,
            t: level.t,
            tPhotoLeft: level.tPhotoLeft,
            tPhotoRight: level.tPhotoRight,
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
          var invalidOutsideBrow = 0;
          var coverageSum = 0;
          var nonzeroDx = 0;
          for (var i = 0; i < warped.invalidSource.length; i++) {
            coverageSum += warped.coverage[i];
            if (built.field.dx[i] != 0) {
              nonzeroDx++;
            }
            if (warped.invalidSource[i] == 0) {
              continue;
            }
            invalidCount++;
            if (built.masks.browActive[i] == 0) {
              invalidOutsideBrow++;
            }
            expect(
              _rgbaEquals(photo.rgba, warped.rgba, i),
              isTrue,
              reason: '${photo.id} ${level.label} fill at $i',
            );
          }
          final coverageMean = coverageSum / warped.coverage.length;
          expect(nonzeroDx, 0, reason: '${photo.id} ${level.label} Δy only');

          final signedLeft = level.tPhotoLeft ?? level.t;
          final signedRight = level.tPhotoRight ?? level.t;
          final isIdentity =
              signedLeft.abs() <= 1e-6 && signedRight.abs() <= 1e-6;
          final m = built.metrics;

          if (isIdentity) {
            expect(warped.rgba, photo.rgba, reason: '${photo.id} t=0 v2Raw');
            expect(invalidCount, 0, reason: '${photo.id} t=0 invalidSource');
            expect(changed, 0, reason: '${photo.id} t=0 changed');
            expect(built.field.isZero, isTrue);
          } else {
            expect(changed, greaterThan(0),
                reason: '${photo.id} ${level.label}');
            expect(m.minDetJ, greaterThan(0),
                reason: '${photo.id} ${level.label}');
            expect(m.coreCurvature, lessThan(_coreCeiling), reason: photo.id);
            expect(m.entryStep, lessThan(_entryCeiling), reason: photo.id);
            expect(
              m.outsideBrowZoneP95,
              lessThanOrEqualTo(_protectEps),
              reason: photo.id,
            );
            expect(m.eyes.p95Abs, lessThanOrEqualTo(_protectEps),
                reason: photo.id);
            expect(m.mouth.p95Abs, lessThanOrEqualTo(_protectEps),
                reason: photo.id);
            expect(m.nose.p95Abs, lessThanOrEqualTo(_protectEps),
                reason: photo.id);
            expect(
              m.absAtHairline,
              lessThanOrEqualTo(_protectEps),
              reason: photo.id,
            );
            expect(invalidOutsideBrow, 0,
                reason: '${photo.id} invalid off brow');
            final peak = math.max(
              m.dyAtPrimaryLeft.abs(),
              m.dyAtPrimaryRight.abs(),
            );
            expect(
              m.absAtLidLeft,
              lessThanOrEqualTo(0.30 * math.max(peak, 1e-6) + 1e-6),
              reason: '${photo.id} lid 386',
            );
            expect(
              m.absAtLidRight,
              lessThanOrEqualTo(0.30 * math.max(peak, 1e-6) + 1e-6),
              reason: '${photo.id} lid 159',
            );
            expect(
              m.absAtOuterCreaseLeft,
              lessThanOrEqualTo(0.20 * math.max(peak, 1e-6) + 1e-6),
              reason: '${photo.id} outer crease L',
            );
            expect(
              m.absAtOuterCreaseRight,
              lessThanOrEqualTo(0.20 * math.max(peak, 1e-6) + 1e-6),
              reason: '${photo.id} outer crease R',
            );

            if (level.tPhotoLeft == null) {
              if (level.t < 0) {
                expect(m.browsDrop, isTrue, reason: photo.id);
              } else if (level.t > 0) {
                expect(m.browsLift, isTrue, reason: photo.id);
              }
            } else if (level.tPhotoLeft! > 0 && level.tPhotoRight == 0) {
              expect(
                m.dyAtPrimaryRight.abs(),
                greaterThan(m.dyAtPrimaryLeft.abs() + 0.15),
                reason: '${photo.id} L100 should move 105',
              );
              expect(m.dyAtPrimaryRight, lessThan(0), reason: photo.id);
            } else if (level.tPhotoRight! > 0 && level.tPhotoLeft == 0) {
              expect(
                m.dyAtPrimaryLeft.abs(),
                greaterThan(m.dyAtPrimaryRight.abs() + 0.15),
                reason: '${photo.id} R100 should move 334',
              );
              expect(m.dyAtPrimaryLeft, lessThan(0), reason: photo.id);
            }
          }

          const far = Offset(8, 8);
          expect(
            _absAt(built.field, far),
            lessThanOrEqualTo(_protectEps),
            reason: '${photo.id} ${level.label} far field',
          );
          expect(
            _rgbaEqualsAt(photo.rgba, warped.rgba, photo.width, far),
            isTrue,
            reason: '${photo.id} ${level.label} far v2Raw',
          );

          final dir = Directory('$_dumpRoot/${photo.dumpId}/${level.label}');
          dir.createSync(recursive: true);
          _writeArtifacts(
            dir: dir.path,
            photo: photo,
            field: built.field,
            masks: built.masks,
            warped: warped,
          );
          final row = <String, Object>{
            'id': photo.dumpId,
            'label': level.label,
            't': level.t,
            'tPhotoLeft': level.tPhotoLeft ?? level.t,
            'tPhotoRight': level.tPhotoRight ?? level.t,
            'changedPixelCount': changed,
            'invalidCount': invalidCount,
            'invalidOutsideBrow': invalidOutsideBrow,
            'coverageMean': coverageMean,
            'hashV2Raw': _hash(warped.rgba),
            ...m.toJson(),
          };
          File('${dir.path}/metrics.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(row),
          );
          summary.add(row);
        }
      }

      expect(summary.length, 21);
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
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );

  test(
      'Eyebrow Height B lab test does not import V1 fill, pipeline or controller',
      () {
    final imports = File(
      'test/beauty_engine/warp/v2/facial_warp_v2_eyebrow_height_lab_test.dart',
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
    expect(imports.contains('hairline_field.dart'), isFalse);
    expect(imports.contains('head_field.dart'), isFalse);
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

void _writeArtifacts({
  required String dir,
  required _Photo photo,
  required DisplacementField field,
  required EyebrowHeightMasks masks,
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
  _saveMask('$dir/browActive.png', masks.browActive, photo.width, photo.height);
  _saveMask('$dir/eyesMask.png', masks.eyes, photo.width, photo.height);
  _saveOwnership(
    '$dir/ownershipMap.png',
    masks,
    warped.invalidSource,
    photo.width,
    photo.height,
  );
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
    final mag =
        math.sqrt(field.dx[i] * field.dx[i] + field.dy[i] * field.dy[i]);
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
      final mag =
          math.sqrt(field.dx[i] * field.dx[i] + field.dy[i] * field.dy[i]);
      final v = ((mag / maxMag) * 255).round().clamp(0, 255);
      image.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  File(path).writeAsBytesSync(img.encodePng(image));
}

void _saveOwnership(
  String path,
  EyebrowHeightMasks masks,
  Uint8List invalidSource,
  int width,
  int height,
) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = y * width + x;
      final r = masks.eyes[i] != 0 ? 220 : 20;
      final g = masks.browActive[i] != 0 ? 200 : 20;
      final b = invalidSource[i] != 0 ? 255 : 20;
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  File(path).writeAsBytesSync(img.encodePng(image));
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

bool _rgbaEquals(Uint8List a, Uint8List b, int pixel) {
  final o = pixel * 4;
  return a[o] == b[o] &&
      a[o + 1] == b[o + 1] &&
      a[o + 2] == b[o + 2] &&
      a[o + 3] == b[o + 3];
}

bool _rgbaEqualsAt(Uint8List a, Uint8List b, int width, Offset p) {
  final x = p.dx.round().clamp(0, width - 1);
  final y = p.dy.round();
  return _rgbaEquals(a, b, y * width + x);
}

double _absAt(DisplacementField field, Offset p) {
  final x = p.dx.round().clamp(0, field.width - 1);
  final y = p.dy.round().clamp(0, field.height - 1);
  final i = field.indexOf(x, y);
  return math.sqrt(field.dx[i] * field.dx[i] + field.dy[i] * field.dy[i]);
}

String _hash(Uint8List bytes) {
  var h = 2166136261;
  for (var i = 0; i < bytes.length; i++) {
    h ^= bytes[i];
    h = 0x1fffffff & (h * 16777619);
  }
  return h.toRadixString(16).padLeft(8, '0');
}
