import '../../filters/face/face_warp_utils.dart';
import '../../mesh/mesh_topology.dart';
import '../../models/face_mesh_result.dart';
import '../../models/mesh_region.dart';
import 'anatomical_zone.dart';

/// Mapa estático zona → landmarks MediaPipe + papel padrão por zona.
abstract final class VertexRoleMap {
  static const landmarkCount = FaceMeshResult.expectedLandmarkCount;

  static final skullContour =
      MeshTopology.faceRegionLandmarks[MeshRegion.faceOval]!;

  static final forehead =
      MeshTopology.faceRegionLandmarks[MeshRegion.forehead]!;

  static const templeLeft = {127, 162, 21, 54, 103, 67, 109};

  static const templeRight = {356, 389, 251, 284, 332, 297, 338};

  static const browLeft = {276, 283, 282, 295, 285, 336, 296, 334, 293, 300};

  static const browRight = {46, 53, 52, 65, 55, 107, 66, 105, 63, 70};

  static final eyeLeft = {
    ...MeshTopology.faceRegionLandmarks[MeshRegion.leftEye]!,
    468,
    469,
    470,
    471,
    472,
  };

  static final eyeRight = {
    ...MeshTopology.faceRegionLandmarks[MeshRegion.rightEye]!,
    473,
    474,
    475,
    476,
    477,
  };

  static const noseRoot = {168, 6, 197, 195, 5};

  static const noseDorsum = {4, 1, 19, 94, 2, 98, 97};

  static const noseTip = {1, 4, 5, 275, 440};

  static const noseAlae = {326, 327, 294, 278, 344, 45, 220, 115, 48, 64};

  static final cheekLeft = {
    ...MeshTopology.faceRegionLandmarks[MeshRegion.leftCheek]!,
    ...FaceWarpUtils.cheekboneLeft,
  };

  static final cheekRight = {
    ...MeshTopology.faceRegionLandmarks[MeshRegion.rightCheek]!,
    ...FaceWarpUtils.cheekboneRight,
  };

  static final jawLeft =
      MeshTopology.faceRegionLandmarks[MeshRegion.jawLeft]!;

  static final jawRight =
      MeshTopology.faceRegionLandmarks[MeshRegion.jawRight]!;

  static const chin = {152, 175, 199, 200, 17, 18, 148, 176, 149, 150};

  static const upperLip = FaceWarpUtils.lipOuterUpper;

  static const lowerLip = FaceWarpUtils.lipOuterLower;

  static const mouthCorner = {
    ...FaceWarpUtils.mouthCornerLeft,
    ...FaceWarpUtils.mouthCornerRight,
  };

  /// Interior da boca — **sempre rigid** (protege dentes).
  static const oralCavity = FaceWarpUtils.innerMouthExcluded;

  static const philtrum = {0, 37, 267, 164, 393};

  static final zoneLandmarks = {
    AnatomicalZone.skullContour: skullContour,
    AnatomicalZone.forehead: forehead,
    AnatomicalZone.templeLeft: templeLeft,
    AnatomicalZone.templeRight: templeRight,
    AnatomicalZone.browLeft: browLeft,
    AnatomicalZone.browRight: browRight,
    AnatomicalZone.eyeLeft: eyeLeft,
    AnatomicalZone.eyeRight: eyeRight,
    AnatomicalZone.noseRoot: noseRoot,
    AnatomicalZone.noseDorsum: noseDorsum,
    AnatomicalZone.noseTip: noseTip,
    AnatomicalZone.noseAlae: noseAlae,
    AnatomicalZone.cheekLeft: cheekLeft,
    AnatomicalZone.cheekRight: cheekRight,
    AnatomicalZone.jawLeft: jawLeft,
    AnatomicalZone.jawRight: jawRight,
    AnatomicalZone.chin: chin,
    AnatomicalZone.upperLip: upperLip,
    AnatomicalZone.lowerLip: lowerLip,
    AnatomicalZone.mouthCorner: mouthCorner,
    AnatomicalZone.oralCavity: oralCavity,
    AnatomicalZone.philtrum: philtrum,
  };

  static const defaultRole = {
    AnatomicalZone.skullContour: VertexRole.semiRigid,
    AnatomicalZone.forehead: VertexRole.free,
    AnatomicalZone.templeLeft: VertexRole.free,
    AnatomicalZone.templeRight: VertexRole.free,
    AnatomicalZone.browLeft: VertexRole.semiRigid,
    AnatomicalZone.browRight: VertexRole.semiRigid,
    AnatomicalZone.eyeLeft: VertexRole.free,
    AnatomicalZone.eyeRight: VertexRole.free,
    AnatomicalZone.noseRoot: VertexRole.semiRigid,
    AnatomicalZone.noseDorsum: VertexRole.free,
    AnatomicalZone.noseTip: VertexRole.free,
    AnatomicalZone.noseAlae: VertexRole.free,
    AnatomicalZone.cheekLeft: VertexRole.free,
    AnatomicalZone.cheekRight: VertexRole.free,
    AnatomicalZone.jawLeft: VertexRole.free,
    AnatomicalZone.jawRight: VertexRole.free,
    AnatomicalZone.chin: VertexRole.free,
    AnatomicalZone.upperLip: VertexRole.free,
    AnatomicalZone.lowerLip: VertexRole.free,
    AnatomicalZone.mouthCorner: VertexRole.free,
    AnatomicalZone.oralCavity: VertexRole.rigid,
    AnatomicalZone.philtrum: VertexRole.semiRigid,
  };

  static Set<int> landmarksFor(AnatomicalZone zone) =>
      zoneLandmarks[zone] ?? const {};

  static VertexRole roleFor(AnatomicalZone zone) =>
      defaultRole[zone] ?? VertexRole.free;

  static bool isValidLandmarkIndex(int index) =>
      index >= 0 && index < landmarkCount;

  static bool validateAllZones() {
    for (final entry in zoneLandmarks.entries) {
      for (final index in entry.value) {
        if (!isValidLandmarkIndex(index)) {
          return false;
        }
      }
    }
    return true;
  }
}
