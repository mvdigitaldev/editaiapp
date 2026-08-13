import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/tri_mesh_spatial_index.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/tri_mesh.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/anatomical_intent.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_matte_roi.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_mesh_deformation_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_mesh_forward_warp.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_render_contract.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_renderer.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/tri_mesh_locate_diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';

import '../filters/skin/skin_face_fixture.dart';

void main() {
  const engine = FaceMeshDeformationEngine();

  group('TriMeshSpatialIndex locate Fase 3', () {
    Future<FaceMeshForwardPayload> payloadFor(Size imageSize) async {
      final face = syntheticFace();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final vertexField = engine.composeVertexField(
        parameters: const {'face_slim': 0.9},
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

    test('locate matches fullScan on face center', () async {
      const imageSize = Size(640, 960);
      final payload = await payloadFor(imageSize);
      final mesh = payload.mesh;
      final index = TriMeshSpatialIndex(
        mesh,
        imageWidth: imageSize.width,
        imageHeight: imageSize.height,
      );

      final cx = imageSize.width * 0.5;
      final cy = imageSize.height * 0.45;
      expect(index.locateTriangleIndex(cx, cy), isNotNull);
      expect(
        index.locateTriangleIndex(cx, cy),
        index.locateTriangleIndexFullScan(cx, cy),
      );
    });

    test('locate vs fullScan agree on deformed ROI', () async {
      const imageSize = Size(640, 960);
      final payload = await payloadFor(imageSize);
      final w = imageSize.width.round();
      final h = imageSize.height.round();
      final built = _buildDeformed(payload, w, h);
      final index = built.index;

      var mismatched = 0;
      var bothHit = 0;
      for (var y = built.roi.y0; y <= built.roi.y1; y++) {
        final py = y + 0.5;
        for (var x = built.roi.x0; x <= built.roi.x1; x++) {
          final px = x + 0.5;
          final a = index.locateTriangleIndex(px, py);
          final b = index.locateTriangleIndexFullScan(px, py);
          if (a == null && b == null) {
            continue;
          }
          bothHit++;
          if (a != b) {
            mismatched++;
          }
        }
      }
      expect(bothHit, greaterThan(1000));
      expect(mismatched / bothHit, lessThan(0.001));
    });

    test('fixture-640x960-90 locate matches fullScan source field', () async {
      const imageSize = Size(640, 960);
      final payload = await payloadFor(imageSize);
      final w = imageSize.width.round();
      final h = imageSize.height.round();
      final rgba = _gradientRgba(w, h);

      final metrics = TriMeshLocateDiagnostic.pureRemapMetricsFromPayload(
        payload: payload,
        width: w,
        height: h,
        sourceRgba: rgba,
      );

      // Com scanline coherence, saltos devem ficar bem abaixo do legado (~22px).
      expect(metrics['sourceCoordMaxHorizJump'] as double, lessThan(8.0));
      expect(metrics['sourceCoordP95HorizJump'] as double, lessThan(2.0));
      expect(metrics['coverageRatio'] as double, greaterThan(0.5));
    });

    test('deformed mesh @90% man-equivalent synthetic keeps coverage', () async {
      const imageSize = Size(695, 1024);
      final payload = await payloadFor(imageSize);
      final w = imageSize.width.round();
      final h = imageSize.height.round();

      final render = FaceWarpRenderer.renderFromPayload(
        rgba: _gradientRgba(w, h),
        width: w,
        height: h,
        payload: payload,
        runId: 'locate-regression',
      );

      expect(render.metrics.destinationCoverage, greaterThan(0.5));
    });
  });
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

({
  TriMeshSpatialIndex index,
  ({int x0, int y0, int x1, int y1}) roi,
}) _buildDeformed(FaceMeshForwardPayload payload, int width, int height) {
  final mesh = payload.mesh;
  final vf = payload.vertexField;
  final vertexCount = FaceWarpFieldMetrics.safeVertexCount(
    field: vf,
    mesh: mesh,
  );
  final supportWeights = GeometricSupport.computeWeights(
    mesh: mesh,
    coreField: vf,
    influenceMap: payload.influenceMap,
    params: const DeformationSupportParams(),
    imageWidth: width,
    imageHeight: height,
    personMask: payload.personMask,
  );

  final deformedVerts = Float32List.fromList(mesh.vertices);
  for (var i = 0; i < vertexCount; i++) {
    final core = vf.displacementAt(i);
    final eff = FaceWarpFieldMetrics.effectiveDelta(
      core,
      supportWeights[i].clamp(0.0, 1.0),
    );
    deformedVerts[i * 2] += eff.dx;
    deformedVerts[i * 2 + 1] += eff.dy;
  }

  final deformedMesh = TriMesh(
    vertices: deformedVerts,
    uvs: mesh.uvs,
    indices: mesh.indices,
    regionBuffers: mesh.regionBuffers,
    isPartial: mesh.isPartial,
  );

  final index = TriMeshSpatialIndex(
    deformedMesh,
    imageWidth: width.toDouble(),
    imageHeight: height.toDouble(),
  );

  var minX = width;
  var minY = height;
  var maxX = 0;
  var maxY = 0;
  for (var i = 0; i < deformedVerts.length; i += 2) {
    minX = math.min(minX, deformedVerts[i].floor());
    minY = math.min(minY, deformedVerts[i + 1].floor());
    maxX = math.max(maxX, deformedVerts[i].ceil());
    maxY = math.max(maxY, deformedVerts[i + 1].ceil());
  }
  const margin = 3;
  final roi = (
    x0: (minX - margin).clamp(0, width - 1),
    y0: (minY - margin).clamp(0, height - 1),
    x1: (maxX + margin).clamp(0, width - 1),
    y1: (maxY + margin).clamp(0, height - 1),
  );

  return (index: index, roi: roi);
}
