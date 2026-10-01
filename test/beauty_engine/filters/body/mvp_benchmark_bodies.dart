import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/pose_result.dart';
import 'package:image/image.dart' as img;

const bodyBenchmarkManifestPath =
    'test/beauty_engine/warp/fixtures/body/real/manifest.json';

class BodyBenchmarkPhoto {
  const BodyBenchmarkPhoto({
    required this.id,
    required this.dumpId,
    required this.label,
    required this.imagePath,
    required this.imageSize,
    required this.sex,
    required this.framing,
    required this.notes,
    required this.rgba,
    required this.width,
    required this.height,
    this.pose,
    this.poseJsonPath,
  });

  final String id;
  final String dumpId;
  final String label;
  final String imagePath;
  final Size imageSize;
  final String sex;
  final String framing;
  final String notes;
  final Uint8List rgba;
  final int width;
  final int height;
  final PoseResult? pose;
  final String? poseJsonPath;

  bool get hasPose => pose != null;
}

/// Fotos de corpo do laboratório. Pose JSON é opcional até existir detecção.
List<BodyBenchmarkPhoto> loadAvailableRealBenchmarkBodies() {
  final manifestFile = File(bodyBenchmarkManifestPath);
  if (!manifestFile.existsSync()) {
    throw StateError('missing_body_benchmark_manifest: $bodyBenchmarkManifestPath');
  }
  final manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  final out = <BodyBenchmarkPhoto>[];
  for (final entry
      in (manifest['photos'] as List).cast<Map<String, dynamic>>()) {
    final imagePath = entry['image'] as String;
    final imageFile = File(imagePath);
    if (!imageFile.existsSync()) {
      continue;
    }
    final decoded = img.decodeImage(imageFile.readAsBytesSync());
    if (decoded == null) {
      throw StateError('body_benchmark_decode_failed: $imagePath');
    }
    final width = decoded.width;
    final height = decoded.height;
    final expectedW = (entry['width'] as num).toInt();
    final expectedH = (entry['height'] as num).toInt();
    if (width != expectedW || height != expectedH) {
      throw StateError(
        'body_benchmark_size_mismatch: $imagePath '
        'got ${width}x$height expected ${expectedW}x$expectedH',
      );
    }
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

    final poseJsonPath = entry['poseJson'] as String?;
    PoseResult? pose;
    if (poseJsonPath != null && File(poseJsonPath).existsSync()) {
      pose = PoseResult.fromJson(
        jsonDecode(File(poseJsonPath).readAsStringSync())
            as Map<String, dynamic>,
      );
    }

    out.add(
      BodyBenchmarkPhoto(
        id: entry['id'] as String,
        dumpId: entry['dumpId'] as String,
        label: entry['label'] as String,
        imagePath: imagePath,
        imageSize: Size(width.toDouble(), height.toDouble()),
        sex: entry['sex'] as String,
        framing: entry['framing'] as String,
        notes: entry['notes'] as String,
        rgba: rgba,
        width: width,
        height: height,
        pose: pose,
        poseJsonPath: poseJsonPath,
      ),
    );
  }
  return out;
}
