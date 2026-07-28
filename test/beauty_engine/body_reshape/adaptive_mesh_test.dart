import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/body_reshape/mesh/adaptive_mesh_generator.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/mesh/constrained_triangulator.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/mesh/mesh_resolution_profile.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_frame_assets.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_joint.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_reshape_request.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/person_matte.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/providers/vision_capabilities.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/mesh_engine_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MeshResolutionProfile', () {
    test('LOD scales interactive < preview < export', () {
      const size = Size(1080, 1920);
      final interactive =
          MeshResolutionProfile.fromQuality(WarpQualityProfile.interactive, size);
      final preview =
          MeshResolutionProfile.fromQuality(WarpQualityProfile.preview, size);
      final export =
          MeshResolutionProfile.fromQuality(WarpQualityProfile.export, size);

      expect(interactive.maxVertices, lessThan(preview.maxVertices));
      expect(preview.maxVertices, lessThan(export.maxVertices));
      expect(interactive.baseCellPx, greaterThan(preview.baseCellPx));
      expect(preview.baseCellPx, greaterThan(export.baseCellPx));
    });
  });

  group('ConstrainedTriangulator', () {
    test('fills a square domain without degenerate triangles', () {
      const triangulator = ConstrainedTriangulator();
      final result = triangulator.triangulate(
        bounds: const Rect.fromLTWH(0, 0, 100, 100),
        isInside: (p) => p.dx >= 0 && p.dx <= 100 && p.dy >= 0 && p.dy <= 100,
        cellSizeAt: (_) => 12,
        maxVertices: 2000,
      );

      expect(result.vertexCount, greaterThan(20));
      expect(result.triangleCount, greaterThan(20));
      expect(_hasDegenerate(result.vertices, result.indices), isFalse);
    });
  });

  group('AdaptiveMeshGenerator', () {
    const generator = AdaptiveMeshGenerator();
    const imageSize = Size(320, 640);

    test('mesh follows person matte contour and stays inside silhouette', () {
      final assets = _standingPersonAssets(imageSize);
      final mesh = generator.generate(
        assets: assets,
        imageSize: imageSize,
        qualityProfile: WarpQualityProfile.preview,
      );

      expect(mesh.vertexCount, greaterThan(100));
      expect(mesh.triangleCount, greaterThan(100));
      expect(mesh.hasDegenerateTriangles(), isFalse);

      final matte = assets.personMatte!;
      var outside = 0;
      for (var i = 0; i < mesh.vertexCount; i++) {
        final nx = mesh.uvs[i * 2];
        final ny = mesh.uvs[i * 2 + 1];
        if (matte.sampleNormalized(nx, ny) < 0.2) {
          outside++;
        }
      }
      // Permite pequena folga de quantização/contorno; a maioria fica no matte.
      expect(outside / mesh.vertexCount, lessThan(0.12));
      expect(mesh.bounds.width, greaterThan(40));
      expect(mesh.bounds.height, greaterThan(80));
    });

    test('waist/hip/limbs denser than torso interior', () {
      final assets = _standingPersonAssets(imageSize);
      final mesh = generator.generate(
        assets: assets,
        imageSize: imageSize,
        qualityProfile: WarpQualityProfile.preview,
      );

      final counts = mesh.vertexCountsByRegion();
      final focus =
          (counts[BodyRegion.waist] ?? 0) +
          (counts[BodyRegion.hip] ?? 0) +
          (counts[BodyRegion.leftArm] ?? 0) +
          (counts[BodyRegion.rightArm] ?? 0) +
          (counts[BodyRegion.leftThigh] ?? 0) +
          (counts[BodyRegion.rightThigh] ?? 0);
      final torso = counts[BodyRegion.torso] ?? 0;

      expect(focus, greaterThan(0));
      // Densidade regional: foco deve superar torso genérico.
      expect(focus, greaterThan(torso));
    });

    test('export supports thousands of vertices without degenerates', () {
      final assets = _standingPersonAssets(const Size(720, 1280));
      final mesh = generator.generate(
        assets: assets,
        imageSize: const Size(720, 1280),
        qualityProfile: WarpQualityProfile.export,
      );

      expect(mesh.vertexCount, greaterThanOrEqualTo(1000));
      expect(mesh.hasDegenerateTriangles(), isFalse);
      expect(mesh.profile.quality, WarpQuality.export);

      final tri = mesh.toTriMesh();
      expect(tri.vertices.length, mesh.vertices.length);
      expect(tri.indices.length, mesh.indices.length);
    });

    test('fallback without matte still produces a usable mesh', () {
      final assets = _standingPersonAssets(imageSize, withMatte: false);
      final mesh = generator.generate(
        assets: assets,
        imageSize: imageSize,
        qualityProfile: WarpQualityProfile.interactive,
      );

      expect(mesh.vertexCount, greaterThan(30));
      expect(mesh.hasDegenerateTriangles(), isFalse);
      for (final w in mesh.weights) {
        expect(w, closeTo(0.65, 1e-6));
      }
    });

    test('MeshEngine exposes adaptive body mesh', () {
      final engine = MeshEngineImpl();
      final assets = _standingPersonAssets(imageSize);
      final mesh = engine.buildAdaptiveBodyMesh(
        assets: assets,
        imageSize: imageSize,
        qualityProfile: WarpQualityProfile.preview,
      );
      expect(mesh.vertexCount, greaterThan(50));
    });
  });
}

BodyFrameAssets _standingPersonAssets(Size size, {bool withMatte = true}) {
  BodyLandmark lm(BodyJoint joint, double x, double y) {
    return BodyLandmark(
      joint: joint,
      normalized: Offset(x, y),
      confidence: 0.95,
    );
  }

  final landmarks = <BodyJoint, BodyLandmark>{
    BodyJoint.leftShoulder: lm(BodyJoint.leftShoulder, 0.38, 0.22),
    BodyJoint.rightShoulder: lm(BodyJoint.rightShoulder, 0.62, 0.22),
    BodyJoint.leftElbow: lm(BodyJoint.leftElbow, 0.30, 0.36),
    BodyJoint.rightElbow: lm(BodyJoint.rightElbow, 0.70, 0.36),
    BodyJoint.leftWrist: lm(BodyJoint.leftWrist, 0.28, 0.48),
    BodyJoint.rightWrist: lm(BodyJoint.rightWrist, 0.72, 0.48),
    BodyJoint.leftHip: lm(BodyJoint.leftHip, 0.42, 0.48),
    BodyJoint.rightHip: lm(BodyJoint.rightHip, 0.58, 0.48),
    BodyJoint.leftKnee: lm(BodyJoint.leftKnee, 0.43, 0.68),
    BodyJoint.rightKnee: lm(BodyJoint.rightKnee, 0.57, 0.68),
    BodyJoint.leftAnkle: lm(BodyJoint.leftAnkle, 0.44, 0.88),
    BodyJoint.rightAnkle: lm(BodyJoint.rightAnkle, 0.56, 0.88),
  };

  PersonMatte? matte;
  if (withMatte) {
    final width = size.width.round();
    final height = size.height.round();
    final alpha = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final nx = x / math.max(width - 1, 1);
        final ny = y / math.max(height - 1, 1);
        final inside = _silhouetteContains(nx, ny);
        alpha[y * width + x] = inside ? 255 : 0;
      }
    }
    matte = PersonMatte(
      alpha: alpha,
      width: width,
      height: height,
      providerId: 'test_matte',
      boundingRegion: const Rect.fromLTRB(0.24, 0.14, 0.76, 0.92),
    );
  }

  return BodyFrameAssets(
    landmarks: landmarks,
    boundingBox: const Rect.fromLTRB(0.24, 0.14, 0.76, 0.92),
    providerId: 'test',
    capabilities: withMatte
        ? VisionCapabilities.mediapipePoseAndMatte
        : VisionCapabilities.mediapipePoseOnly,
    personMatte: matte,
  );
}

bool _silhouetteContains(double nx, double ny) {
  // Tronco retangular + cabeça/membros aproximados.
  final torso = nx >= 0.34 && nx <= 0.66 && ny >= 0.20 && ny <= 0.52;
  final hips = nx >= 0.36 && nx <= 0.64 && ny >= 0.48 && ny <= 0.60;
  final leftArm = (nx - 0.34).abs() < 0.08 && ny >= 0.22 && ny <= 0.50;
  final rightArm = (nx - 0.66).abs() < 0.08 && ny >= 0.22 && ny <= 0.50;
  final leftLeg = (nx - 0.43).abs() < 0.07 && ny >= 0.52 && ny <= 0.90;
  final rightLeg = (nx - 0.57).abs() < 0.07 && ny >= 0.52 && ny <= 0.90;
  final head = math.pow(nx - 0.5, 2) / 0.045 + math.pow(ny - 0.14, 2) / 0.03 <= 1;
  return torso || hips || leftArm || rightArm || leftLeg || rightLeg || head;
}

bool _hasDegenerate(Float32List vertices, Uint32List indices) {
  for (var t = 0; t < indices.length; t += 3) {
    final a = indices[t];
    final b = indices[t + 1];
    final c = indices[t + 2];
    if (a == b || b == c || a == c) {
      return true;
    }
    final ax = vertices[a * 2];
    final ay = vertices[a * 2 + 1];
    final bx = vertices[b * 2];
    final by = vertices[b * 2 + 1];
    final cx = vertices[c * 2];
    final cy = vertices[c * 2 + 1];
    final area2 = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
    if (area2.abs() <= 1e-8) {
      return true;
    }
  }
  return false;
}
