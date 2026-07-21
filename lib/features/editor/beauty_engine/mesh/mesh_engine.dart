import 'dart:ui';

import '../models/face_mesh_result.dart';
import '../models/pose_result.dart';
import '../models/tri_mesh.dart';

/// Malha triangulada compartilhada — base de todos os filtros.
abstract class MeshEngine {
  TriMesh buildFaceMesh(FaceMeshResult face, Size imageSize);

  TriMesh buildBodyMesh(PoseResult pose, Size imageSize);

  TriMesh merge(TriMesh face, TriMesh body);
}
