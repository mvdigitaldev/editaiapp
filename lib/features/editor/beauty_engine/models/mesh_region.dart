/// Regiões da malha reutilizável para warp e filtros.
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
