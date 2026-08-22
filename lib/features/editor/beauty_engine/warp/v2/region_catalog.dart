import '../../mesh/mesh_topology.dart';
import '../../models/mesh_region.dart';

/// Índices MediaPipe usados pelo domínio V2.
///
/// Olhos, nariz, boca, oval e jaw: [MeshTopology.faceRegionLandmarks].
/// Sobrancelhas: os mesmos conjuntos já listados em `VertexRoleMap.browLeft` /
/// `browRight` (não se importa anatomy). Orelhas: 323 e 454, presentes em
/// `jawRight` e por isso **subtraídas** do domínio jaw.
abstract final class V2RegionCatalog {
  V2RegionCatalog._();

  static final jawLeft =
      MeshTopology.faceRegionLandmarks[MeshRegion.jawLeft]!;

  static final jawRight =
      MeshTopology.faceRegionLandmarks[MeshRegion.jawRight]!;

  static const ears = {323, 454};

  static final jawLandmarks = {...jawLeft, ...jawRight}.difference(ears);

  static final leftEye =
      MeshTopology.faceRegionLandmarks[MeshRegion.leftEye]!;

  static final rightEye =
      MeshTopology.faceRegionLandmarks[MeshRegion.rightEye]!;

  static final eyes = {...leftEye, ...rightEye};

  static final nose = MeshTopology.faceRegionLandmarks[MeshRegion.nose]!;

  static final lips = MeshTopology.faceRegionLandmarks[MeshRegion.lips]!;

  static final faceOval =
      MeshTopology.faceRegionLandmarks[MeshRegion.faceOval]!;

  static const browLeft = {276, 283, 282, 295, 285, 336, 296, 334, 293, 300};

  static const browRight = {46, 53, 52, 65, 55, 107, 66, 105, 63, 70};

  static const brows = {...browLeft, ...browRight};

  static final faceCenter = {...eyes, ...nose, ...lips};

  static const chinTip = 152;

  /// Gônios MediaPipe (mandíbula). Melhor proxy visual de largura jaw que os
  /// extremos do hull.
  static const gonionLeft = 58;
  static const gonionRight = 288;

  /// Silhueta mandibular (sem orelhas, sem 152). Pesos no campo, não na V1.
  static const silhouettePrimary = {58, 288, 132, 361};
  static const silhouetteSecondary = {172, 136, 365, 397};
}
