import 'dart:typed_data';
import 'dart:ui';

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
  TriMesh merge(TriMesh face, TriMesh body) => face;
}
