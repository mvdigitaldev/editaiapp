import '../models/mesh_region.dart';

export 'face_mesh_topology.generated.dart';

/// Mapa estatico landmark index → regioes MediaPipe (indices 0–467).
abstract class MeshTopology {
  /// Landmarks por regiao facial (subset dos 468 pontos canonicos).
  static const Map<MeshRegion, Set<int>> faceRegionLandmarks = {
    MeshRegion.faceOval: {
      10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365,
      379, 378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93,
      234, 127, 162, 21, 54, 103, 67, 109,
    },
    MeshRegion.jawLeft: {132, 58, 172, 136, 150, 149, 176, 148, 152, 377},
    MeshRegion.jawRight: {361, 288, 397, 365, 379, 378, 400, 152, 323, 454},
    MeshRegion.nose: {
      168, 6, 197, 195, 5, 4, 1, 19, 94, 2, 98, 97, 326, 327, 294, 278,
      344, 440, 275, 45, 220, 115, 48, 64,
    },
    MeshRegion.leftEye: {
      263, 249, 390, 373, 374, 380, 381, 382, 362, 466, 388, 387, 386,
      385, 384, 398,
    },
    MeshRegion.rightEye: {
      33, 7, 163, 144, 145, 153, 154, 155, 133, 246, 161, 160, 159, 158,
      157, 173,
    },
    MeshRegion.lips: {
      61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 185, 40, 39, 37,
      0, 267, 269, 270, 409, 78, 95, 88, 178, 87, 14, 317, 402, 318, 324,
      308, 191, 80, 81, 82, 13, 312, 311, 310, 415,
    },
    MeshRegion.leftCheek: {116, 123, 147, 187, 207, 206, 203, 142, 126, 217},
    MeshRegion.rightCheek: {345, 352, 411, 425, 427, 436, 426, 423, 266, 371},
    MeshRegion.forehead: {9, 10, 151, 337, 338, 297, 332, 109, 67, 103, 54, 21},
  };

  /// Landmarks por regiao corporal (indices MediaPipe Pose 0–32).
  static const Map<MeshRegion, Set<int>> bodyRegionLandmarks = {
    MeshRegion.torso: {11, 12, 23, 24},
    MeshRegion.waist: {11, 12, 23, 24},
    MeshRegion.leftArm: {11, 13, 15},
    MeshRegion.rightArm: {12, 14, 16},
    MeshRegion.leftLeg: {23, 25, 27},
    MeshRegion.rightLeg: {24, 26, 28},
    MeshRegion.neck: {0, 11, 12},
  };

  /// Triangulos do torso (indices locais pose).
  static const List<int> bodyTriangleIndices = [
    // Torso
    11, 12, 23,
    12, 24, 23,
    // Bracos
    11, 13, 15,
    12, 14, 16,
    // Pernas
    23, 25, 27,
    24, 26, 28,
  ];

  /// Pontos de ponte pescoco (face landmark → pose landmark).
  static const Map<int, int> neckBridgePairs = {
    152: 0, // queixo → nariz pose
    377: 11, // mandibula esq → ombro esq
    400: 12, // mandibula dir → ombro dir
  };
}
