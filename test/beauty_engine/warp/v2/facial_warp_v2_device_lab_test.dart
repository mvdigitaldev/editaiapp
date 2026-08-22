import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/config/facial_warp_v2_config.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/facial_warp_v2_device_lab.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/facial_warp_v2_dump_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../filters/skin/mvp_benchmark_faces.dart';

const _assets = {
  'real-p01': 'test/beauty_engine/warp/fixtures/phase12/p01-man-5021469.png',
  'real-p05': 'test/beauty_engine/warp/fixtures/phase12/p05-young-woman.png',
  'real-p12': 'test/beauty_engine/warp/fixtures/phase12/p12.jpg',
};

class _Photo {
  const _Photo({
    required this.dumpId,
    required this.face,
    required this.imageSize,
    required this.rgba,
    required this.width,
    required this.height,
  });

  final String dumpId;
  final FaceMeshResult face;
  final Size imageSize;
  final Uint8List rgba;
  final int width;
  final int height;
}

void main() {
  late Directory dumpRoot;
  late List<_Photo> photos;

  setUpAll(() {
    photos = [
      for (final id in _assets.keys) _loadPhoto(id),
    ];
  });

  setUp(() {
    FacialWarpV2DeviceLab.resetForTest();
    dumpRoot = Directory.systemTemp.createTempSync('v23-device-lab-');
    FacialWarpV2DumpPaths.bindDeviceRoot(dumpRoot.path);
  });

  tearDown(() {
    FacialWarpV2DeviceLab.resetForTest();
    if (dumpRoot.existsSync()) {
      dumpRoot.deleteSync(recursive: true);
    }
  });

  test('facialWarpCoreV2Lab defaults to false', () {
    expect(FacialWarpV2Config.facialWarpCoreV2Lab, isFalse);
  });

  test('flag false does not write v2Raw', () {
    final p01 = photos.firstWhere((p) => p.dumpId == 'p01');
    final out = FacialWarpV2DeviceLab.maybeDump(
      sourceRgba: p01.rgba,
      width: p01.width,
      height: p01.height,
      face: p01.face,
      parameters: const {'jaw': 0.5},
    );
    expect(out.dumped, isFalse);
    expect(out.reason, 'disabled');
    expect(File('${dumpRoot.path}/p01/50/v2Raw.png').existsSync(), isFalse);
  });

  test('flag true dumps jaw-only v2Raw on approved photos', () {
    FacialWarpV2Config.facialWarpCoreV2Lab = true;
    final p01 = photos.firstWhere((p) => p.dumpId == 'p01');
    for (final t in const [0.0, 0.25, 0.5]) {
      final out = FacialWarpV2DeviceLab.maybeDump(
        sourceRgba: p01.rgba,
        width: p01.width,
        height: p01.height,
        face: p01.face,
        parameters: {'jaw': t},
      );
      expect(out.dumped, isTrue, reason: 'p01 t=$t');
      expect(File('${out.directory}/v2Raw.png').existsSync(), isTrue);
      expect(File('${out.directory}/metrics.json').existsSync(), isTrue);
    }
    for (final photo in photos.where((p) => p.dumpId != 'p01')) {
      final out = FacialWarpV2DeviceLab.maybeDump(
        sourceRgba: photo.rgba,
        width: photo.width,
        height: photo.height,
        face: photo.face,
        parameters: const {'jaw': 0.5},
      );
      expect(out.dumped, isTrue, reason: photo.dumpId);
      expect(out.photoId, photo.dumpId);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('jaw plus chin or v_face does not dump V2', () {
    FacialWarpV2Config.facialWarpCoreV2Lab = true;
    final p01 = photos.firstWhere((p) => p.dumpId == 'p01');
    final chin = FacialWarpV2DeviceLab.maybeDump(
      sourceRgba: p01.rgba,
      width: p01.width,
      height: p01.height,
      face: p01.face,
      parameters: const {'jaw': 0.5, 'chin': 0.4},
    );
    expect(chin.dumped, isFalse);
    expect(chin.reason, 'not_jaw_only');
    final vFace = FacialWarpV2DeviceLab.maybeDump(
      sourceRgba: p01.rgba,
      width: p01.width,
      height: p01.height,
      face: p01.face,
      parameters: const {'jaw': 0.5, 'v_face': 0.3},
    );
    expect(vFace.dumped, isFalse);
    expect(vFace.reason, 'not_jaw_only');
    expect(File('${dumpRoot.path}/p01/50/v2Raw.png').existsSync(), isFalse);
  });

  test('unknown photo size is ignored even with flag on', () {
    FacialWarpV2Config.facialWarpCoreV2Lab = true;
    final p01 = photos.firstWhere((p) => p.dumpId == 'p01');
    final out = FacialWarpV2DeviceLab.maybeDump(
      sourceRgba: p01.rgba.sublist(0, 16),
      width: 2,
      height: 2,
      face: p01.face,
      parameters: const {'jaw': 0.5},
    );
    expect(out.dumped, isFalse);
    expect(out.reason, 'not_approved_photo');
  });

  test('dump paths do not read FaceWarpV3Config or ExtendedRoiDumpPaths', () {
    final imports = File(
      'lib/features/editor/beauty_engine/warp/v2/facial_warp_v2_dump_paths.dart',
    )
        .readAsLinesSync()
        .where((line) => line.trimLeft().startsWith('import '))
        .join('\n');
    expect(imports.contains('face_warp_v3_config'), isFalse);
    expect(imports.contains('extended_roi'), isFalse);
  });

  test('PassWarp and controller do not import V2 Device Lab', () {
    final passWarp = File(
      'lib/features/editor/beauty_engine/rendering/pass_warp.dart',
    ).readAsStringSync();
    final controller = File(
      'lib/features/editor/beauty_engine/controllers/beauty_engine_controller.dart',
    ).readAsStringSync();
    expect(passWarp.contains('facial_warp_v2'), isFalse);
    expect(controller.contains('facial_warp_v2'), isFalse);
  });

  test('Device Lab does not import fill, Telea or PassWarp', () {
    final imports = File(
      'lib/features/editor/beauty_engine/warp/v2/facial_warp_v2_device_lab.dart',
    )
        .readAsLinesSync()
        .where((line) => line.trimLeft().startsWith('import '))
        .join('\n');
    expect(imports.contains('hole_fill'), isFalse);
    expect(imports.contains('telea'), isFalse);
    expect(imports.contains('contour_band_fill'), isFalse);
    expect(imports.contains('semantic_released_fill'), isFalse);
    expect(imports.contains('pass_warp'), isFalse);
    expect(imports.contains('extended_roi'), isFalse);
    expect(imports.contains('beauty_engine_controller'), isFalse);
  });
}

_Photo _loadPhoto(String id) {
  final available = loadAvailableRealBenchmarkFaces();
  final match = available.firstWhere((f) => f.id == id);
  final asset = _assets[id]!;
  final decoded = img.decodeImage(File(asset).readAsBytesSync());
  expect(decoded, isNotNull, reason: asset);
  final width = decoded!.width;
  final height = decoded.height;
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
    dumpId: id.replaceFirst('real-', ''),
    face: match.face,
    imageSize: Size(width.toDouble(), height.toDouble()),
    rgba: rgba,
    width: width,
    height: height,
  );
}
