import 'dart:typed_data';
import 'dart:ui';

import '../body_reshape/mesh/adaptive_body_mesh.dart';
import '../body_reshape/mesh/mesh_resolution_profile.dart';
import '../body_reshape/models/body_frame_assets.dart';
import '../body_reshape/models/body_reshape_request.dart';
import '../models/face_mesh_result.dart';
import '../models/pose_result.dart';
import '../models/tri_mesh.dart';
import 'mesh_engine.dart';

/// Stub para testes que nao precisam de malha real.
class MeshEngineStub implements MeshEngine {
  const MeshEngineStub();

  @override
  TriMesh buildFaceMesh(FaceMeshResult face, Size imageSize) {
    return TriMesh(
      vertices: Float32List(0),
      uvs: Float32List(0),
      indices: Uint32List(0),
    );
  }

  @override
  TriMesh buildBodyMesh(PoseResult pose, Size imageSize) {
    return TriMesh(
      vertices: Float32List(0),
      uvs: Float32List(0),
      indices: Uint32List(0),
    );
  }

  @override
  AdaptiveBodyMesh buildAdaptiveBodyMesh({
    required BodyFrameAssets assets,
    required Size imageSize,
    WarpQualityProfile qualityProfile = WarpQualityProfile.preview,
  }) {
    return AdaptiveBodyMesh(
      vertices: Float32List(0),
      uvs: Float32List(0),
      indices: Uint32List(0),
      weights: Float32List(0),
      vertexRegionCodes: Int32List(0),
      regionTriangleIndices: const {},
      profile: MeshResolutionProfile.fromQuality(qualityProfile, imageSize),
      imageSize: imageSize,
      bounds: Rect.zero,
    );
  }

  @override
  TriMesh merge(TriMesh face, TriMesh body) => face;
}
