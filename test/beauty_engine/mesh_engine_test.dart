import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/mesh/body_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_topology.generated.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/mesh_cache.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/mesh_engine_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/mesh_merger.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/mesh_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const imageSize = Size(1080, 1920);

  group('FaceMeshBuilder', () {
    test('builds mesh with MediaPipe topology and no degenerate triangles', () {
      final face = _fakeFaceMesh();
      final mesh = const FaceMeshBuilder().build(face, imageSize);

      expect(mesh.vertices.length, FaceMeshTopology.landmarkCount * 2);
      expect(mesh.triangleCount, greaterThan(700));
      expect(mesh.hasDegenerateTriangles(), isFalse);
    });

    test('regions are queryable', () {
      final face = _fakeFaceMesh();
      final mesh = const FaceMeshBuilder().build(face, imageSize);

      expect(mesh.region(MeshRegion.jawLeft), isNotNull);
      expect(mesh.regionIndices(MeshRegion.jawLeft).length, greaterThan(0));
      expect(mesh.region(MeshRegion.lips), isNotNull);
      expect(mesh.region(MeshRegion.leftEye), isNotNull);
    });
  });

  group('BodyMeshBuilder', () {
    test('builds body mesh with torso and limbs regions', () {
      final pose = _fakeFullBodyPose();
      final mesh = const BodyMeshBuilder().build(pose, imageSize);

      expect(mesh.vertices.length, PoseResult.expectedLandmarkCount * 2);
      expect(mesh.region(MeshRegion.torso), isNotNull);
      expect(mesh.region(MeshRegion.leftLeg), isNotNull);
      expect(mesh.region(MeshRegion.rightLeg), isNotNull);
      expect(mesh.isPartial, isFalse);
    });

    test('partial pose flagged on mesh', () {
      final pose = _fakePartialPose();
      final mesh = const BodyMeshBuilder().build(pose, imageSize);

      expect(mesh.isPartial, isTrue);
    });
  });

  group('MeshMerger', () {
    test('merge adds neck region without degenerate triangles', () {
      final face = const FaceMeshBuilder().build(_fakeFaceMesh(), imageSize);
      final body = const BodyMeshBuilder().build(_fakeFullBodyPose(), imageSize);

      final merged = const MeshMerger().merge(face, body);

      expect(merged.vertices.length, face.vertices.length + body.vertices.length);
      expect(merged.region(MeshRegion.neck), isNotNull);
      expect(merged.regionIndices(MeshRegion.neck).length, greaterThanOrEqualTo(9));
      expect(merged.hasDegenerateTriangles(), isFalse);
    });

    test('face regions preserved after merge', () {
      final face = const FaceMeshBuilder().build(_fakeFaceMesh(), imageSize);
      final body = const BodyMeshBuilder().build(_fakeFullBodyPose(), imageSize);
      final merged = const MeshMerger().merge(face, body);

      expect(merged.region(MeshRegion.jawLeft), isNotNull);
      expect(merged.region(MeshRegion.torso), isNotNull);
    });
  });

  group('MeshCache', () {
    test('returns same instance for identical face input', () {
      final cache = MeshCache();
      final engine = MeshEngineImpl(cache: cache);
      final face = _fakeFaceMesh();

      final a = engine.buildFaceMesh(face, imageSize);
      final b = engine.buildFaceMesh(face, imageSize);

      expect(identical(a, b), isTrue);
    });

    test('hash changes when landmarks move', () {
      final faceA = _fakeFaceMesh();
      final faceB = _fakeFaceMesh(chinY: 0.75);

      expect(
        MeshCache.hashFace(faceA, imageSize),
        isNot(MeshCache.hashFace(faceB, imageSize)),
      );
    });
  });
}

FaceMeshResult _fakeFaceMesh({double chinY = 0.7}) {
  final landmarks = List.generate(
    FaceMeshResult.expectedLandmarkCount,
    (index) {
      final x = 0.3 + (index % 50) * 0.008;
      final y = 0.2 + (index ~/ 50) * 0.01;
      return FaceLandmark(
        index: index,
        normalized: Offset(x, index == 152 ? chinY : y),
      );
    },
  );

  return FaceMeshResult(
    landmarks: landmarks,
    boundingBox: const Rect.fromLTRB(0.2, 0.2, 0.8, 0.8),
    confidence: 0.9,
  );
}

PoseResult _fakeFullBodyPose() {
  return PoseResult(
    landmarks: _poseLandmarks({
      for (var i = 0; i < 33; i++) i: 0.95,
    }),
    boundingBox: const Rect.fromLTRB(0.25, 0.1, 0.75, 0.95),
    isPartial: false,
  );
}

PoseResult _fakePartialPose() {
  return PoseResult(
    landmarks: _poseLandmarks({
      for (var i = 0; i < 33; i++)
        i: (i >= 25) ? 0.1 : 0.9,
    }),
    boundingBox: const Rect.fromLTRB(0.3, 0.15, 0.7, 0.6),
    isPartial: true,
  );
}

List<PoseLandmark> _poseLandmarks(Map<int, double> visibility) {
  Offset positionFor(int index) {
    switch (index) {
      case 11:
        return const Offset(0.38, 0.28);
      case 12:
        return const Offset(0.62, 0.28);
      case 13:
        return const Offset(0.32, 0.42);
      case 14:
        return const Offset(0.68, 0.42);
      case 15:
        return const Offset(0.28, 0.55);
      case 16:
        return const Offset(0.72, 0.55);
      case 23:
        return const Offset(0.40, 0.58);
      case 24:
        return const Offset(0.60, 0.58);
      case 25:
        return const Offset(0.35, 0.75);
      case 26:
        return const Offset(0.65, 0.75);
      case 27:
        return const Offset(0.42, 0.92);
      case 28:
        return const Offset(0.58, 0.92);
      default:
        return Offset(0.5, 0.15 + index * 0.02);
    }
  }

  return List.generate(PoseResult.expectedLandmarkCount, (index) {
    return PoseLandmark(
      index: index,
      normalized: positionFor(index),
      visibility: visibility[index] ?? 0.9,
    );
  });
}
