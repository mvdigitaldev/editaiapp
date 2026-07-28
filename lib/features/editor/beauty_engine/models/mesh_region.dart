/// Regiões da malha legada reutilizável para warp e filtros.
///
/// O Body Reshape V2 usa `BodyRegion`, mantendo este enum para compatibilidade
/// com campos MLS e com a topologia facial existentes.
enum MeshRegion {
  faceOval,
  jawLeft,
  jawRight,
  nose,
  leftEye,
  rightEye,
  lips,
  leftCheek,
  rightCheek,
  forehead,
  torso,
  waist,
  leftArm,
  rightArm,
  leftLeg,
  rightLeg,
  neck,
}

/// Intervalo de índices dentro de uma [TriMesh].
class IndexRange {
  final int start;
  final int count;

  const IndexRange({required this.start, required this.count});
}
