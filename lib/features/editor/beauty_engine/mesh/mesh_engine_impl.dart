import 'dart:ui';

import '../body_reshape/mesh/adaptive_body_mesh.dart';
import '../body_reshape/mesh/adaptive_mesh_generator.dart';
import '../body_reshape/models/body_frame_assets.dart';
import '../body_reshape/models/body_reshape_request.dart';
import '../models/face_mesh_result.dart';
import '../models/pose_result.dart';
import '../models/tri_mesh.dart';
import 'body_mesh_builder.dart';
import 'face_mesh_builder.dart';
import 'mesh_cache.dart';
import 'mesh_engine.dart';
import 'mesh_merger.dart';

/// Facade do Mesh Engine com cache por hash de landmarks.
class MeshEngineImpl implements MeshEngine {
  MeshEngineImpl({
    FaceMeshBuilder? faceBuilder,
    BodyMeshBuilder? bodyBuilder,
    AdaptiveMeshGenerator? adaptiveBodyGenerator,
    MeshMerger? merger,
    MeshCache? cache,
  })  : _faceBuilder = faceBuilder ?? const FaceMeshBuilder(),
        _bodyBuilder = bodyBuilder ?? const BodyMeshBuilder(),
        _adaptiveBodyGenerator =
            adaptiveBodyGenerator ?? const AdaptiveMeshGenerator(),
        _merger = merger ?? const MeshMerger(),
        _cache = cache ?? MeshCache();

  final FaceMeshBuilder _faceBuilder;
  final BodyMeshBuilder _bodyBuilder;
  final AdaptiveMeshGenerator _adaptiveBodyGenerator;
  final MeshMerger _merger;
  final MeshCache _cache;

  @override
  TriMesh buildFaceMesh(FaceMeshResult face, Size imageSize) {
    final key = MeshCache.hashFace(face, imageSize);
    return _cache.getFace(key) ??
        _putFace(key, _faceBuilder.build(face, imageSize));
  }

  @override
  TriMesh buildBodyMesh(PoseResult pose, Size imageSize) {
    final key = MeshCache.hashPose(pose, imageSize);
    return _cache.getBody(key) ??
        _putBody(key, _bodyBuilder.build(pose, imageSize));
  }

  @override
  AdaptiveBodyMesh buildAdaptiveBodyMesh({
    required BodyFrameAssets assets,
    required Size imageSize,
    WarpQualityProfile qualityProfile = WarpQualityProfile.preview,
  }) {
    return _adaptiveBodyGenerator.generate(
      assets: assets,
      imageSize: imageSize,
      qualityProfile: qualityProfile,
    );
  }

  @override
  TriMesh merge(TriMesh face, TriMesh body) {
    final key = Object.hash(
      face.vertices.length,
      body.vertices.length,
      face.indices.length,
      body.indices.length,
    );
    return _cache.getMerged(key) ?? _putMerged(key, _merger.merge(face, body));
  }

  TriMesh _putFace(int key, TriMesh mesh) {
    _cache.putFace(key, mesh);
    return mesh;
  }

  TriMesh _putBody(int key, TriMesh mesh) {
    _cache.putBody(key, mesh);
    return mesh;
  }

  TriMesh _putMerged(int key, TriMesh mesh) {
    _cache.putMerged(key, mesh);
    return mesh;
  }
}
