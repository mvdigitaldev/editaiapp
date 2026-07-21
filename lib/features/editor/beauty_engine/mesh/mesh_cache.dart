import 'dart:ui';

import '../models/face_landmark.dart';
import '../models/face_mesh_result.dart';
import '../models/pose_landmark.dart';
import '../models/pose_result.dart';
import '../models/tri_mesh.dart';
import 'mesh_utils.dart';

/// Cache de malhas por hash quantizado de landmarks.
class MeshCache {
  final Map<int, TriMesh> _faceCache = {};
  final Map<int, TriMesh> _bodyCache = {};
  final Map<int, TriMesh> _mergedCache = {};

  TriMesh? getFace(int key) => _faceCache[key];

  TriMesh? getBody(int key) => _bodyCache[key];

  TriMesh? getMerged(int key) => _mergedCache[key];

  void putFace(int key, TriMesh mesh) => _faceCache[key] = mesh;

  void putBody(int key, TriMesh mesh) => _bodyCache[key] = mesh;

  void putMerged(int key, TriMesh mesh) => _mergedCache[key] = mesh;

  void clear() {
    _faceCache.clear();
    _bodyCache.clear();
    _mergedCache.clear();
  }

  static int hashFace(FaceMeshResult face, Size imageSize) {
    return Object.hash(
      imageSize.width.round(),
      imageSize.height.round(),
      _hashLandmarks(face.landmarks.take(FaceMeshResult.expectedLandmarkCount)),
    );
  }

  static int hashPose(PoseResult pose, Size imageSize) {
    return Object.hash(
      imageSize.width.round(),
      imageSize.height.round(),
      pose.isPartial,
      _hashLandmarksPose(pose.landmarks),
    );
  }

  static int hashMerged(int faceKey, int bodyKey) => Object.hash(faceKey, bodyKey);

  static int _hashLandmarks(Iterable<FaceLandmark> landmarks) {
    var hash = 0;
    for (final landmark in landmarks) {
      hash = Object.hash(
        hash,
        landmark.index,
        MeshUtils.quantizeHash(landmark.normalized.dx),
        MeshUtils.quantizeHash(landmark.normalized.dy),
      );
    }
    return hash;
  }

  static int _hashLandmarksPose(Iterable<PoseLandmark> landmarks) {
    var hash = 0;
    for (final landmark in landmarks) {
      hash = Object.hash(
        hash,
        landmark.index,
        MeshUtils.quantizeHash(landmark.normalized.dx),
        MeshUtils.quantizeHash(landmark.normalized.dy),
        MeshUtils.quantizeHash(landmark.visibility),
      );
    }
    return hash;
  }
}
