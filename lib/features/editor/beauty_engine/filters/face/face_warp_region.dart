/// Grupos anatômicos para composição regional do warp facial (Sprint 8).
enum FaceWarpRegion {
  lowerFace,
  midFace,
  eyes,
  mouth,
  cheek,
  contour,
}

/// Mapeia parâmetros de slider → região de influência MLS.
abstract final class FaceWarpRegionMap {
  static FaceWarpRegion? regionForKey(String key) {
    switch (key) {
      case 'jaw':
      case 'chin':
      case 'v_face':
      case 'face_slim':
        return FaceWarpRegion.lowerFace;
      case 'nose_slim':
      case 'nose_length':
      case 'nose_height':
      case 'nose_tip':
      case 'nose_bridge':
        return FaceWarpRegion.midFace;
      case 'eye_scale':
      case 'eye_distance':
      case 'eye_height':
      case 'eye_rotation':
      case 'double_eyelid':
        return FaceWarpRegion.eyes;
      case 'mouth_width':
      case 'lip_thickness':
      case 'smile':
        return FaceWarpRegion.mouth;
      case 'cheekbone':
      case 'narrow_face':
        return FaceWarpRegion.cheek;
      case 'forehead':
      case 'temple':
      case 'head_size':
        return FaceWarpRegion.contour;
      default:
        return null;
    }
  }

  static const regionOrder = [
    FaceWarpRegion.contour,
    FaceWarpRegion.lowerFace,
    FaceWarpRegion.midFace,
    FaceWarpRegion.cheek,
    FaceWarpRegion.eyes,
    FaceWarpRegion.mouth,
  ];
}
