/// Regiões corporais semânticas usadas pelo Body Reshape V2.
///
/// Não inclui regiões faciais: o face warp mantém domínio e topologia próprios.
enum BodyRegion {
  torso,
  waist,
  chest,
  hip,
  butt,
  leftArm,
  rightArm,
  leftForearm,
  rightForearm,
  leftThigh,
  rightThigh,
  leftCalf,
  rightCalf,
  neck,
  shoulders,
}

extension BodyRegionSide on BodyRegion {
  bool get isLeft => switch (this) {
        BodyRegion.leftArm ||
        BodyRegion.leftForearm ||
        BodyRegion.leftThigh ||
        BodyRegion.leftCalf =>
          true,
        _ => false,
      };

  bool get isRight => switch (this) {
        BodyRegion.rightArm ||
        BodyRegion.rightForearm ||
        BodyRegion.rightThigh ||
        BodyRegion.rightCalf =>
          true,
        _ => false,
      };
}
