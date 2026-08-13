import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/face_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';

import 'skin_face_fixture.dart';

/// Perfil de rosto sintético para benchmark Stage 2.
enum MvpBenchmarkFaceShape {
  oval,
  round,
  square,
  long,
  wide,
}

class MvpBenchmarkFaceSpec {
  const MvpBenchmarkFaceSpec({
    required this.id,
    required this.shape,
    required this.imageSize,
    this.label,
  });

  final String id;
  final MvpBenchmarkFaceShape shape;
  final Size imageSize;
  final String? label;

  bool get isSynthetic => true;
}

class MvpBenchmarkRealFaceSpec {
  const MvpBenchmarkRealFaceSpec({
    required this.id,
    required this.landmarkJsonPath,
    required this.imageSize,
    this.label,
  });

  final String id;
  final String landmarkJsonPath;
  final Size imageSize;
  final String? label;

  bool get isSynthetic => false;
}

/// Constrói rosto sintético com proporções distintas (oval/redondo/quadrado/longo/largo).
FaceMeshResult syntheticFaceForShape(MvpBenchmarkFaceShape shape) {
  final (rx, ry, center) = switch (shape) {
    MvpBenchmarkFaceShape.oval => (0.20, 0.24, faceCenter),
    MvpBenchmarkFaceShape.round => (0.22, 0.22, faceCenter),
    MvpBenchmarkFaceShape.square => (0.24, 0.20, const Offset(0.5, 0.44)),
    MvpBenchmarkFaceShape.long => (0.18, 0.28, const Offset(0.5, 0.40)),
    MvpBenchmarkFaceShape.wide => (0.26, 0.21, const Offset(0.5, 0.43)),
  };

  final points = <int, Offset>{};

  void placeOnEllipse(Set<int> indices, Offset c, double rX, double rY) {
    final sorted = indices.toList()..sort();
    for (var i = 0; i < sorted.length; i++) {
      final angle = (i / sorted.length) * 2 * math.pi;
      points[sorted[i]] = Offset(
        c.dx + math.cos(angle) * rX,
        c.dy + math.sin(angle) * rY,
      );
    }
  }

  placeOnEllipse(faceOvalIndices, center, rx, ry);
  placeOnEllipse(leftEyeIndices, leftEyeCenter, 0.045, 0.022);
  placeOnEllipse(rightEyeIndices, rightEyeCenter, 0.045, 0.022);
  placeOnEllipse(leftBrowIndices, Offset(0.585, center.dy - 0.125), 0.05, 0.008);
  placeOnEllipse(rightBrowIndices, Offset(0.415, center.dy - 0.125), 0.05, 0.008);
  placeOnEllipse(innerMouthIndices, Offset(center.dx, center.dy + 0.13), 0.055, 0.018);

  final landmarks = List.generate(
    FaceMeshResult.expectedLandmarkCount,
    (index) {
      final placed = points[index];
      if (placed != null) {
        return FaceLandmark(index: index, normalized: placed);
      }
      final angle = index * 0.618 * 2 * math.pi;
      final radius = 0.35 + (index % 7) * 0.04;
      return FaceLandmark(
        index: index,
        normalized: Offset(
          (center.dx + math.cos(angle) * rx * radius).clamp(0.0, 1.0),
          (center.dy + math.sin(angle) * ry * radius).clamp(0.0, 1.0),
        ),
      );
    },
  );

  return FaceMeshResult(
    landmarks: landmarks,
    confidence: 0.95,
    boundingBox: Rect.fromCenter(
      center: center,
      width: rx * 2,
      height: ry * 2,
    ),
  );
}

/// Lista padrão — 5 sintéticos + 5 reais (JSON cacheado).
List<MvpBenchmarkFaceSpec> defaultSyntheticBenchmarkFaces() {
  return const [
    MvpBenchmarkFaceSpec(
      id: 'syn-oval',
      shape: MvpBenchmarkFaceShape.oval,
      imageSize: Size(640, 960),
      label: 'oval',
    ),
    MvpBenchmarkFaceSpec(
      id: 'syn-round',
      shape: MvpBenchmarkFaceShape.round,
      imageSize: Size(640, 960),
      label: 'round',
    ),
    MvpBenchmarkFaceSpec(
      id: 'syn-square',
      shape: MvpBenchmarkFaceShape.square,
      imageSize: Size(640, 960),
      label: 'square',
    ),
    MvpBenchmarkFaceSpec(
      id: 'syn-long',
      shape: MvpBenchmarkFaceShape.long,
      imageSize: Size(640, 960),
      label: 'long',
    ),
    MvpBenchmarkFaceSpec(
      id: 'syn-wide',
      shape: MvpBenchmarkFaceShape.wide,
      imageSize: Size(720, 960),
      label: 'wide',
    ),
  ];
}

List<MvpBenchmarkRealFaceSpec> defaultRealBenchmarkFaces() {
  return const [
    MvpBenchmarkRealFaceSpec(
      id: 'real-p01',
      landmarkJsonPath:
          'test/beauty_engine/warp/fixtures/benchmark/real/p01-man-5021469.json',
      imageSize: Size(695, 1024),
      label: 'man-5021469',
    ),
    MvpBenchmarkRealFaceSpec(
      id: 'real-p05',
      landmarkJsonPath:
          'test/beauty_engine/warp/fixtures/benchmark/real/p05-young-woman.json',
      imageSize: Size(640, 960),
      label: 'young-woman',
    ),
    MvpBenchmarkRealFaceSpec(
      id: 'real-p06',
      landmarkJsonPath:
          'test/beauty_engine/warp/fixtures/benchmark/real/p06-senior-woman.json',
      imageSize: Size(640, 960),
      label: 'senior-woman',
    ),
    MvpBenchmarkRealFaceSpec(
      id: 'real-p12',
      landmarkJsonPath:
          'test/beauty_engine/warp/fixtures/benchmark/real/p12-pexels-774909.json',
      imageSize: Size(640, 960),
      label: 'oval-man',
    ),
    MvpBenchmarkRealFaceSpec(
      id: 'real-p21',
      landmarkJsonPath:
          'test/beauty_engine/warp/fixtures/benchmark/real/p21-pexels-220453.json',
      imageSize: Size(640, 960),
      label: 'square-jaw',
    ),
  ];
}

FaceMeshResult loadRealBenchmarkFace(String jsonPath) {
  final file = File(jsonPath);
  if (!file.existsSync()) {
    throw StateError('missing_real_landmark_fixture: $jsonPath');
  }
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return FaceMeshResult.fromJson(json);
}

/// Rostos reais disponíveis (ignora fixtures ausentes).
List<({String id, String label, FaceMeshResult face, Size imageSize})>
    loadAvailableRealBenchmarkFaces() {
  final out = <({String id, String label, FaceMeshResult face, Size imageSize})>[];

  final manifestFile = File(
    'test/beauty_engine/warp/fixtures/benchmark/real/manifest.json',
  );
  if (manifestFile.existsSync()) {
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    for (final entry in (manifest['photos'] as List).cast<Map<String, dynamic>>()) {
      final jsonPath = entry['landmarkJson'] as String;
      if (!File(jsonPath).existsSync()) {
        continue;
      }
      out.add((
        id: entry['id'] as String,
        label: entry['label'] as String,
        face: loadRealBenchmarkFace(jsonPath),
        imageSize: Size(
          (entry['width'] as num).toDouble(),
          (entry['height'] as num).toDouble(),
        ),
      ));
    }
    return out;
  }

  for (final spec in defaultRealBenchmarkFaces()) {
    final file = File(spec.landmarkJsonPath);
    if (!file.existsSync()) {
      continue;
    }
    out.add((
      id: spec.id,
      label: spec.label ?? spec.id,
      face: loadRealBenchmarkFace(spec.landmarkJsonPath),
      imageSize: spec.imageSize,
    ));
  }
  return out;
}
