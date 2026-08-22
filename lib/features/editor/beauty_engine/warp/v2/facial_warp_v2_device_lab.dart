import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../config/facial_warp_v2_config.dart';
import '../../models/face_mesh_result.dart';
import 'backward_bilinear_warp.dart';
import 'displacement_field.dart';
import 'facial_warp_v2_dump_paths.dart';
import 'jaw_field.dart';
import 'region_masks.dart';

class FacialWarpV2DumpOutcome {
  const FacialWarpV2DumpOutcome({
    required this.dumped,
    required this.reason,
    this.directory,
    this.photoId,
    this.intensityPercent,
  });

  final bool dumped;
  final String reason;
  final String? directory;
  final String? photoId;
  final int? intensityPercent;
}

/// Device Lab V2: compõe JawField + renderer e grava `v2Raw`.
/// Não devolve RGBA para o preview. Não preenche buracos.
abstract final class FacialWarpV2DeviceLab {
  FacialWarpV2DeviceLab._();

  static const blockingKeys = ['chin', 'v_face', 'face_slim', 'narrow_face'];

  static const approvedLabSizes = {
    'p01': (695, 1024),
    'p05': (740, 740),
    'p12': (960, 1440),
  };

  static String? _lastDumpKey;

  @visibleForTesting
  static void resetForTest() {
    _lastDumpKey = null;
    FacialWarpV2DumpPaths.clearDeviceRootForTest();
    FacialWarpV2Config.resetForTest();
  }

  static String? approvedPhotoId(int width, int height) {
    for (final entry in approvedLabSizes.entries) {
      if (entry.value.$1 == width && entry.value.$2 == height) {
        return entry.key;
      }
    }
    return null;
  }

  static bool isJawOnly(Map<String, double> parameters) {
    for (final key in blockingKeys) {
      if ((parameters[key] ?? 0) > 0.01) {
        return false;
      }
    }
    return true;
  }

  static int intensityPercent(double t) {
    final pct = (t.clamp(0.0, 1.0) * 100).round();
    for (final grid in const [0, 25, 50]) {
      if ((pct - grid).abs() <= 2) {
        return grid;
      }
    }
    return pct;
  }

  static FacialWarpV2DumpOutcome maybeDump({
    required Uint8List sourceRgba,
    required int width,
    required int height,
    required FaceMeshResult? face,
    required Map<String, double> parameters,
  }) {
    if (!FacialWarpV2Config.facialWarpCoreV2Lab) {
      return const FacialWarpV2DumpOutcome(
        dumped: false,
        reason: 'disabled',
      );
    }
    if (kIsWeb) {
      return const FacialWarpV2DumpOutcome(
        dumped: false,
        reason: 'web',
      );
    }
    if (face == null || face.landmarks.length < 478) {
      return const FacialWarpV2DumpOutcome(
        dumped: false,
        reason: 'no_face',
      );
    }
    if (!isJawOnly(parameters)) {
      debugPrint('V2 Device Lab: skip not_jaw_only');
      return const FacialWarpV2DumpOutcome(
        dumped: false,
        reason: 'not_jaw_only',
      );
    }
    final photoId = approvedPhotoId(width, height);
    if (photoId == null) {
      debugPrint(
        'V2 Device Lab: skip not_approved_photo ${width}x$height',
      );
      return const FacialWarpV2DumpOutcome(
        dumped: false,
        reason: 'not_approved_photo',
      );
    }
    if (sourceRgba.length != width * height * 4) {
      return const FacialWarpV2DumpOutcome(
        dumped: false,
        reason: 'rgba_size_mismatch',
      );
    }

    final t = (parameters['jaw'] ?? 0).clamp(0.0, 1.0);
    final percent = intensityPercent(t);
    final key = '$photoId/$percent';
    if (_lastDumpKey == key) {
      return FacialWarpV2DumpOutcome(
        dumped: false,
        reason: 'duplicate',
        photoId: photoId,
        intensityPercent: percent,
      );
    }

    final built = JawField.build(
      face: face,
      imageSize: Size(width.toDouble(), height.toDouble()),
      t: t,
    );
    final warped = BackwardBilinearWarp.apply(
      WarpRequest(
        sourceRgba: sourceRgba,
        width: width,
        height: height,
        field: built.field,
      ),
    );

    final preferred = FacialWarpV2DumpPaths.runDir(
      photoId: photoId,
      intensityPercent: percent,
    );
    final dir = FacialWarpV2DumpPaths.ensureWritable(preferred);
    _writeArtifacts(
      dir: dir,
      sourceRgba: sourceRgba,
      width: width,
      height: height,
      field: built.field,
      masks: built.masks,
      warped: warped,
    );

    var invalidCount = 0;
    var coverageSum = 0;
    for (var i = 0; i < warped.invalidSource.length; i++) {
      if (warped.invalidSource[i] != 0) {
        invalidCount++;
      }
      coverageSum += warped.coverage[i];
    }
    File('$dir/metrics.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'id': photoId,
        't': t,
        'intensityPercent': percent,
        'changedPixelCount': _changedPixelCount(sourceRgba, warped.rgba),
        'invalidCount': invalidCount,
        'coverageMean': coverageSum / warped.coverage.length,
        'hashV2Raw': _hash(warped.rgba),
        ...built.metrics.toJson(),
      }),
    );
    _lastDumpKey = key;
    debugPrint('V2 Device Lab: dumped $photoId t=$t dir=$dir');
    return FacialWarpV2DumpOutcome(
      dumped: true,
      reason: 'ok',
      directory: dir,
      photoId: photoId,
      intensityPercent: percent,
    );
  }

  static void _writeArtifacts({
    required String dir,
    required Uint8List sourceRgba,
    required int width,
    required int height,
    required DisplacementField field,
    required RegionMasks masks,
    required WarpResult warped,
  }) {
    _saveRgba('$dir/original.png', sourceRgba, width, height);
    _saveRgba('$dir/v2Raw.png', warped.rgba, width, height);
    _saveGray('$dir/coverage.png', warped.coverage, width, height);
    _saveMask('$dir/invalidSource.png', warped.invalidSource, width, height);
    _saveMask(
      '$dir/invalidSourceMask.png',
      warped.invalidSource,
      width,
      height,
    );
    _saveMask('$dir/protectedMask.png', masks.protected, width, height);
    _saveDisplacement('$dir/displacementField.png', field);
    _saveInfluence('$dir/influenceMap.png', field);
    _saveOwnership(
      '$dir/ownershipMap.png',
      masks,
      warped.invalidSource,
      width,
      height,
    );
  }

  static void _saveRgba(String path, Uint8List rgba, int width, int height) {
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

  static void _saveGray(String path, Uint8List bytes, int width, int height) {
    final image = img.Image(width: width, height: height, numChannels: 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final v = bytes[y * width + x];
        image.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    File(path).writeAsBytesSync(img.encodePng(image));
  }

  static void _saveMask(String path, Uint8List mask, int width, int height) {
    final image = img.Image(width: width, height: height, numChannels: 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final on = mask[y * width + x] != 0;
        image.setPixelRgba(x, y, on ? 255 : 0, on ? 255 : 0, on ? 255 : 0, 255);
      }
    }
    File(path).writeAsBytesSync(img.encodePng(image));
  }

  static void _saveDisplacement(String path, DisplacementField field) {
    final image = img.Image(
      width: field.width,
      height: field.height,
      numChannels: 4,
    );
    const scale = 12.0;
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

  static void _saveInfluence(String path, DisplacementField field) {
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

  static void _saveOwnership(
    String path,
    RegionMasks masks,
    Uint8List invalidSource,
    int width,
    int height,
  ) {
    final image = img.Image(width: width, height: height, numChannels: 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = y * width + x;
        final r = masks.protected[i] != 0 ? 220 : 20;
        final g = masks.jawActive[i] != 0 ? 200 : 20;
        final b = invalidSource[i] != 0 ? 255 : 20;
        image.setPixelRgba(x, y, r, g, b, 255);
      }
    }
    File(path).writeAsBytesSync(img.encodePng(image));
  }

  static int _changedPixelCount(Uint8List a, Uint8List b) {
    var n = 0;
    for (var i = 0; i < a.length; i += 4) {
      if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) {
        n++;
      }
    }
    return n;
  }

  static String _hash(Uint8List bytes) {
    var h = 2166136261;
    for (var i = 0; i < bytes.length; i++) {
      h ^= bytes[i];
      h = 0x1fffffff & (h * 16777619);
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}
