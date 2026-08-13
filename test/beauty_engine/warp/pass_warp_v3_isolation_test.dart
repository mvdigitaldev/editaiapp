import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/config/face_warp_v3_config.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/pass_warp.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/render_pass.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/texture_handle.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/texture_pool.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/anatomical_intent.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_matte_roi.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_mesh_deformation_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_mesh_forward_warp.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_render_contract.dart';
import 'package:flutter_test/flutter_test.dart';

import '../filters/skin/skin_face_fixture.dart';

void main() {
  const imageSize = Size(640, 960);
  const engine = FaceMeshDeformationEngine();

  setUp(() {
    FaceWarpV3Config.useForwardMeshWarpFaceSlim = true;
  });

  group('FaceSlimV3Routing', () {
    test('V3 payload active → block legacy + passId mesh-backward-preview', () {
      final payload = _samplePayload(intensity: 0.9);
      final routing = FaceSlimV3Routing.resolve(
        faceSlimOnly: true,
        mvpMeshPath: false,
        forwardPayload: payload,
        blockLegacyFlag: true,
        useForwardMeshWarp: true,
      );

      expect(routing.v3PayloadActive, isTrue);
      expect(routing.blockLegacyFaceSlim, isTrue);
      expect(FaceSlimV3Routing.meshBackwardPassId, 'mesh-backward-preview');
    });

    test('no payload → legacy authorized when flag false', () {
      final routing = FaceSlimV3Routing.resolve(
        faceSlimOnly: true,
        mvpMeshPath: false,
        forwardPayload: null,
        blockLegacyFlag: false,
        useForwardMeshWarp: true,
      );

      expect(routing.v3PayloadActive, isFalse);
      expect(routing.blockLegacyFaceSlim, isFalse);
    });

    test('identity payload → V3 not active', () {
      final payload = _samplePayload(intensity: 0);
      final routing = FaceSlimV3Routing.resolve(
        faceSlimOnly: true,
        mvpMeshPath: false,
        forwardPayload: payload,
        blockLegacyFlag: false,
        useForwardMeshWarp: true,
      );

      expect(routing.v3PayloadActive, isFalse);
    });

    test('478/468 consistent on payload', () {
      final payload = _samplePayload(intensity: 0.9);
      expect(payload.vertexField.landmarkCount, 478);
      expect(payload.mesh.vertices.length ~/ 2, 468);
      expect(
        FaceWarpFieldMetrics.safeVertexCount(
          field: payload.vertexField,
          mesh: payload.mesh,
        ),
        468,
      );
    });
  });

  group('PassWarp V3 isolation', () {
    test('forward payload → v3_mesh warp changes pixels (not legacy)', () async {
      final face = syntheticFace();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final vertexField = engine.composeVertexField(
        parameters: {'face_slim': 0.9},
        context: FaceAnatomyContext(
          face: face,
          imageSize: imageSize,
          mesh: mesh,
        ),
      );
      final field = engine.composeWarpField(
        face: face,
        mesh: mesh,
        imageSize: imageSize,
        parameters: {'face_slim': 0.9},
        interactivePreview: true,
      );
      expect(field, isNotNull);

      final influence = FaceMatteRoi.buildInfluenceMap(
        face: face,
        imageSize: imageSize,
        lateralRadiusExpand: 0.07,
      );
      final payload = FaceMeshForwardPayload(
        mesh: mesh,
        vertexField: vertexField,
        influenceMap: influence,
      );

      const w = 640;
      const h = 960;
      final rgba = _gradientRgba(w, h);
      final pool = TexturePool();
      final input = pool.acquireFromUpload(
        TextureUpload(bytes: rgba, width: w, height: h),
      );

      const pass = PassWarp(preferGpu: false);
      final out = await pass.execute(
        RenderPassContext(
          input: input,
          pool: pool,
          uniforms: {
            'warpField': field!,
            'faceMeshForward': payload,
            'blockLegacyFaceSlimFallback': true,
            'warpParameters': {'face_slim': 0.9},
            'influenceMap': influence,
            'interactivePreview': true,
          },
        ),
      );

      final entry = pool.store.get(out.id);
      expect(entry, isNotNull);
      expect(
        PassWarp.warpChangedPixels(rgba, entry!.rgba, minAccumDiff: 500),
        isTrue,
      );

      final routing = FaceSlimV3Routing.resolve(
        faceSlimOnly: true,
        mvpMeshPath: false,
        forwardPayload: payload,
        blockLegacyFlag: true,
        useForwardMeshWarp: true,
      );
      expect(routing.v3PayloadActive, isTrue);
      expect(routing.blockLegacyFaceSlim, isTrue);
    });

    test('block legacy without payload leaves output unchanged vs remapper skip',
        () async {
      final face = syntheticFace();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final field = engine.composeWarpField(
        face: face,
        mesh: mesh,
        imageSize: imageSize,
        parameters: {'face_slim': 0.9},
        interactivePreview: true,
      );
      expect(field, isNotNull);

      final influence = FaceMatteRoi.buildInfluenceMap(
        face: face,
        imageSize: imageSize,
        lateralRadiusExpand: 0.07,
      );

      const w = 640;
      const h = 960;
      final rgba = Uint8List.fromList(_gradientRgba(w, h));
      final pool = TexturePool();
      final input = pool.acquireFromUpload(
        TextureUpload(bytes: rgba, width: w, height: h),
      );

      const pass = PassWarp(preferGpu: false);
      final out = await pass.execute(
        RenderPassContext(
          input: input,
          pool: pool,
          uniforms: {
            'warpField': field!,
            'blockLegacyFaceSlimFallback': true,
            'warpParameters': {'face_slim': 0.9},
            'influenceMap': influence,
            'interactivePreview': true,
          },
        ),
      );

      final entry = pool.store.get(out.id)!;
      final routing = FaceSlimV3Routing.resolve(
        faceSlimOnly: true,
        mvpMeshPath: false,
        forwardPayload: null,
        blockLegacyFlag: true,
        useForwardMeshWarp: true,
      );
      expect(routing.blockLegacyFaceSlim, isTrue);
      expect(routing.v3PayloadActive, isFalse);

      // Legacy FaceSlimWarp suppressed — output equals input (identity pass).
      expect(
        PassWarp.warpChangedPixels(rgba, entry.rgba, minAccumDiff: 500),
        isFalse,
      );
    });

    test('legacy authorized when no payload and no block flag', () async {
      final face = syntheticFace();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final field = engine.composeWarpField(
        face: face,
        mesh: mesh,
        imageSize: imageSize,
        parameters: {'face_slim': 0.9},
        interactivePreview: true,
      );
      expect(field, isNotNull);

      final influence = FaceMatteRoi.buildInfluenceMap(
        face: face,
        imageSize: imageSize,
        lateralRadiusExpand: 0.07,
      );

      const w = 640;
      const h = 960;
      final rgba = _gradientRgba(w, h);
      final pool = TexturePool();
      final input = pool.acquireFromUpload(
        TextureUpload(bytes: rgba, width: w, height: h),
      );

      FaceWarpV3Config.useForwardMeshWarpFaceSlim = false;

      const pass = PassWarp(preferGpu: false);
      final out = await pass.execute(
        RenderPassContext(
          input: input,
          pool: pool,
          uniforms: {
            'warpField': field!,
            'warpParameters': {'face_slim': 0.9},
            'influenceMap': influence,
            'interactivePreview': true,
          },
        ),
      );

      FaceWarpV3Config.useForwardMeshWarpFaceSlim = true;

      final entry = pool.store.get(out.id);
      expect(entry, isNotNull);
      expect(
        PassWarp.warpChangedPixels(rgba, entry!.rgba, minAccumDiff: 500),
        isTrue,
      );
    });
  });
}

FaceMeshForwardPayload _samplePayload({required double intensity}) {
  const imageSize = Size(640, 960);
  const engine = FaceMeshDeformationEngine();
  final face = syntheticFace();
  final mesh = const FaceMeshBuilder().build(face, imageSize);
  final vertexField = engine.composeVertexField(
    parameters: {'face_slim': intensity},
    context: FaceAnatomyContext(
      face: face,
      imageSize: imageSize,
      mesh: mesh,
    ),
  );
  final influence = FaceMatteRoi.buildInfluenceMap(
    face: face,
    imageSize: imageSize,
    lateralRadiusExpand: 0.07,
  );
  return FaceMeshForwardPayload(
    mesh: mesh,
    vertexField: vertexField,
    influenceMap: influence,
  );
}

Uint8List _gradientRgba(int w, int h) {
  final rgba = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final o = (y * w + x) * 4;
      rgba[o] = x % 256;
      rgba[o + 1] = y % 256;
      rgba[o + 2] = (x + y) % 256;
      rgba[o + 3] = 255;
    }
  }
  return rgba;
}
