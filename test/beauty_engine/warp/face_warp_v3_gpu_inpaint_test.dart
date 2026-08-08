import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/config/face_warp_v3_config.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/tri_mesh_spatial_index.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_mesh_deformation_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_mesh_cell_index.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_mesh_gpu_payload.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_post_inpaint.dart';
import 'package:flutter_test/flutter_test.dart';

import '../filters/skin/skin_face_fixture.dart';

void main() {
  const imageSize = Size(640, 960);
  const engine = FaceMeshDeformationEngine();

  group('Sprint 37 — GPU piecewise + inpaint', () {
    setUp(() {
      FaceWarpV3Config.useGpuPiecewiseAffine = true;
      FaceWarpV3Config.useDirectMeshRender = true;
      FaceWarpV3Config.usePostWarpInpaint = true;
    });

    test('composeGpuPayload builds atlas with valid dimensions', () {
      final face = syntheticFace();
      final mesh = const FaceMeshBuilder().build(face, imageSize);

      final payload = engine.composeGpuPayload(
        face: face,
        mesh: mesh,
        imageSize: imageSize,
        parameters: const {'eye_distance': 0.85},
      );

      expect(payload, isNotNull);
      final atlas = payload!.atlas;
      expect(atlas.vertexCount, greaterThan(400));
      expect(atlas.triangleCount, greaterThan(100));
      expect(atlas.cellTriWidth, greaterThan(10));
      expect(atlas.vertexData.length, atlas.vertexDataWidth * atlas.vertexCount * 4);
    });

    test('composeWarpField uses face_mesh_v3_gpu passId when GPU enabled', () {
      final face = syntheticFace();
      final mesh = const FaceMeshBuilder().build(face, imageSize);

      final field = engine.composeWarpField(
        face: face,
        mesh: mesh,
        imageSize: imageSize,
        parameters: const {'face_slim': 0.85},
        interactivePreview: false,
      );

      expect(field?.passId, 'face_mesh_v3_gpu');
    });

    test('TriMeshSpatialIndex.locateTriangleIndex finds triangle in face center', () {
      final face = syntheticFace();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final index = TriMeshSpatialIndex(
        mesh,
        imageWidth: imageSize.width,
        imageHeight: imageSize.height,
      );

      final cx = imageSize.width * 0.5;
      final cy = imageSize.height * 0.45;
      final tri = index.locateTriangleIndex(cx, cy);
      expect(tri, isNotNull);
      expect(index.locate(cx, cy), isNotNull);
    });

    test('FaceMeshCellIndex maps cells inside face oval', () {
      final face = syntheticFace();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final cellIndex = FaceMeshCellIndex.build(
        mesh: mesh,
        imageSize: imageSize,
      );

      var hits = 0;
      for (final tri in cellIndex.triangleIndices) {
        if (tri >= 0) {
          hits++;
        }
      }
      expect(hits, greaterThan(100));
    });

    test('countGhostPixels detects bands for eye_distance', () {
      FaceWarpV3Config.useDirectMeshRender = false;
      final face = syntheticFace();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final field = engine.composeWarpField(
        face: face,
        mesh: mesh,
        imageSize: imageSize,
        parameters: const {'eye_distance': 1.0},
        interactivePreview: true,
      );
      expect(field, isNotNull);

      final ghosts = FaceWarpPostInpaint.countGhostPixels(
        field: field!,
        parameters: const {'eye_distance': 1.0},
      );
      expect(ghosts, greaterThan(0));
    });

    test('FaceWarpPostInpaint is no-op without lateral tools', () {
      final face = syntheticFace();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final field = engine.composeWarpField(
        face: face,
        mesh: mesh,
        imageSize: imageSize,
        parameters: const {'eye_scale': 0.8},
      );
      expect(field, isNotNull);

      final rgba = Uint8List(640 * 960 * 4)..fillRange(0, 640 * 960 * 4, 128);
      final out = FaceWarpPostInpaint.apply(
        rgba: rgba,
        width: 640,
        height: 960,
        field: field!,
        parameters: const {'eye_scale': 0.8},
      );
      expect(out, same(rgba));
    });

    test('FaceWarpPostInpaint modifies rgba when ghost pixels exist', () {
      FaceWarpV3Config.useDirectMeshRender = false;
      final face = syntheticFace();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final field = engine.composeWarpField(
        face: face,
        mesh: mesh,
        imageSize: imageSize,
        parameters: const {'eye_distance': 1.0},
        interactivePreview: true,
      );
      expect(field, isNotNull);

      final rgba = Uint8List(640 * 960 * 4);
      for (var y = 0; y < 960; y++) {
        for (var x = 0; x < 640; x++) {
          final o = (y * 640 + x) * 4;
          rgba[o] = (x % 256);
          rgba[o + 1] = (y % 256);
          rgba[o + 2] = ((x + y) % 256);
          rgba[o + 3] = 255;
        }
      }

      final out = FaceWarpPostInpaint.apply(
        rgba: rgba,
        width: 640,
        height: 960,
        field: field!,
        parameters: const {'eye_distance': 1.0},
      );

      var changed = 0;
      for (var i = 0; i < rgba.length; i += 4) {
        if (out[i] != rgba[i] || out[i + 1] != rgba[i + 1]) {
          changed++;
        }
      }
      expect(changed, greaterThan(0));
    });
  });
}
