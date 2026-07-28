import 'dart:ui';

import '../body_reshape/mesh/adaptive_body_mesh.dart';
import '../body_reshape/models/body_frame_assets.dart';
import '../body_reshape/models/body_reshape_request.dart';
import '../models/face_mesh_result.dart';
import '../models/pose_result.dart';
import '../models/tri_mesh.dart';

/// Malha triangulada compartilhada — base de todos os filtros.
abstract class MeshEngine {
  TriMesh buildFaceMesh(FaceMeshResult face, Size imageSize);

  /// Malha corporal legada (33 landmarks) para o pipeline MLS atual.
  TriMesh buildBodyMesh(PoseResult pose, Size imageSize);

  /// Malha corporal adaptativa V2 (milhares de vértices, LOD por qualidade).
  AdaptiveBodyMesh buildAdaptiveBodyMesh({
    required BodyFrameAssets assets,
    required Size imageSize,
    WarpQualityProfile qualityProfile,
  });

  TriMesh merge(TriMesh face, TriMesh body);
}
