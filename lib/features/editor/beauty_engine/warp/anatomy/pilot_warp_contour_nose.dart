import 'dart:math' as math;
import 'dart:ui';

import '../../filters/face/face_warp_utils.dart';
import '../../filters/face/forehead.dart';
import '../../models/face_mesh_result.dart';
import '../../models/mesh_region.dart';
import '../../models/tri_mesh.dart';
import 'face_model_specification.dart';
import 'pilot_warp_displacement.dart';
import 'vertex_role_map.dart';

/// Deslocamentos pilot Sprint 36 — contorno/volume + nariz (12 tools).
abstract final class PilotWarpContourNose {
  static const contourVolumeToolKeys = {
    'narrow_face',
    'v_face',
    'jaw',
    'chin',
    'cheekbone',
    'forehead',
    'temple',
    'head_size',
  };

  static const noseToolKeys = {
    'nose_length',
    'nose_height',
    'nose_tip',
    'nose_bridge',
  };

  static const _chinIndices = {152, 175, 199, 200, 18, 313, 421, 428};
  static const _foreheadLower = {297, 332, 109, 67, 103, 54, 21};
  static const _templeLeft = {234, 127, 162, 93, 21};
  static const _templeRight = {251, 284, 356, 389, 297};
  static const _noseLengthIndices = {1, 2, 4, 5, 19, 94, 98, 97, 326, 327, 294, 278};
  static const _noseTipIndices = {1, 2, 98, 97, 326, 327, 4, 5, 19};
  static const _noseBridgeIndices = {168, 6, 197, 195, 5, 4, 45, 275};

  static Offset deltaFor({
    required String toolKey,
    required int landmarkIndex,
    required Offset base,
    required FaceToolSpecification spec,
    required FaceMeshResult face,
    required TriMesh mesh,
    required Size imageSize,
    required double magnitude,
    required double rawIntensity,
    required double fse,
  }) {
    return switch (toolKey) {
      'narrow_face' => _narrowFace(
          index: landmarkIndex,
          base: base,
          spec: spec,
          face: face,
          imageSize: imageSize,
          magnitude: magnitude,
          fse: fse,
        ),
      'v_face' => _vFace(
          index: landmarkIndex,
          base: base,
          face: face,
          imageSize: imageSize,
          rawIntensity: rawIntensity,
        ),
      'jaw' => _jaw(
          index: landmarkIndex,
          base: base,
          face: face,
          imageSize: imageSize,
          rawIntensity: rawIntensity,
        ),
      'chin' => _chin(
          index: landmarkIndex,
          base: base,
          face: face,
          mesh: mesh,
          imageSize: imageSize,
          rawIntensity: rawIntensity,
        ),
      'cheekbone' => _cheekbone(
          index: landmarkIndex,
          imageSize: imageSize,
          rawIntensity: rawIntensity,
        ),
      'forehead' => _forehead(
          index: landmarkIndex,
          imageSize: imageSize,
          rawIntensity: rawIntensity,
        ),
      'temple' => _temple(
          index: landmarkIndex,
          imageSize: imageSize,
          rawIntensity: rawIntensity,
        ),
      'head_size' => _headSize(
          index: landmarkIndex,
          base: base,
          face: face,
          imageSize: imageSize,
          rawIntensity: rawIntensity,
        ),
      'nose_length' => _noseLength(
          index: landmarkIndex,
          imageSize: imageSize,
          rawIntensity: rawIntensity,
        ),
      'nose_height' => _noseHeight(
          index: landmarkIndex,
          imageSize: imageSize,
          rawIntensity: rawIntensity,
        ),
      'nose_tip' => _noseTip(
          index: landmarkIndex,
          base: base,
          mesh: mesh,
          imageSize: imageSize,
          rawIntensity: rawIntensity,
        ),
      'nose_bridge' => _noseBridge(
          index: landmarkIndex,
          base: base,
          mesh: mesh,
          imageSize: imageSize,
          rawIntensity: rawIntensity,
        ),
      _ => Offset.zero,
    };
  }

  static Offset _narrowFace({
    required int index,
    required Offset base,
    required FaceToolSpecification spec,
    required FaceMeshResult face,
    required Size imageSize,
    required double magnitude,
    required double fse,
  }) {
    if (!_inCheek(index)) {
      return Offset.zero;
    }
    final maxPx = math.min(
      imageSize.width * 0.08 * magnitude,
      (spec.maxDisplacementFse ?? 0.06) * fse * magnitude,
    );
    if (maxPx <= 0) {
      return Offset.zero;
    }
    final centerX = FaceWarpUtils.faceCenterX(face, imageSize);
    final towardCenter = centerX - base.dx;
    return Offset(towardCenter.sign * maxPx * 0.85, 0);
  }

  static Offset _vFace({
    required int index,
    required Offset base,
    required FaceMeshResult face,
    required Size imageSize,
    required double rawIntensity,
  }) {
    final t = rawIntensity.clamp(0.0, 1.0);
    final jawShift = imageSize.width * 0.14 * t;
    final chinLift = imageSize.height * 0.025 * t;
    final centerX = FaceWarpUtils.faceCenterX(face, imageSize);

    if (_inJawRegion(index)) {
      final towardCenter = centerX - base.dx;
      final ratio = towardCenter.abs() / (imageSize.width * 0.5);
      return Offset(
        towardCenter.sign * jawShift * ratio,
        -chinLift * 0.3,
      );
    }
    if (_chinIndices.contains(index)) {
      return Offset(0, -chinLift);
    }
    return Offset.zero;
  }

  static Offset _jaw({
    required int index,
    required Offset base,
    required FaceMeshResult face,
    required Size imageSize,
    required double rawIntensity,
  }) {
    if (!VertexRoleMap.jawLeft.contains(index) &&
        !VertexRoleMap.jawRight.contains(index)) {
      return Offset.zero;
    }
    final t = rawIntensity.clamp(0.0, 1.0);
    final maxShift = imageSize.width * 0.09 * t;
    final centerX = FaceWarpUtils.faceCenterX(face, imageSize);
    final towardCenter = centerX - base.dx;
    final ratio =
        towardCenter.abs() / (imageSize.width * 0.5).clamp(1.0, double.infinity);
    return Offset(towardCenter.sign * maxShift * ratio, 0);
  }

  static Offset _chin({
    required int index,
    required Offset base,
    required FaceMeshResult face,
    required TriMesh mesh,
    required Size imageSize,
    required double rawIntensity,
  }) {
    if (!VertexRoleMap.chin.contains(index)) {
      return Offset.zero;
    }
    final t = rawIntensity.clamp(0.0, 1.0);
    final lift = imageSize.height * 0.035 * t;
    final narrow = imageSize.width * 0.04 * t;
    final centerX = FaceWarpUtils.faceCenterX(face, imageSize);
    final chinPivot = FaceWarpUtils.landmarkPoint(face, 152, imageSize) ??
        FaceWarpUtils.faceCenter(face, imageSize);
    if (chinPivot == null) {
      return Offset.zero;
    }
    final towardCenter = centerX - base.dx;
    final distFromPivot = (base.dy - chinPivot.dy).abs();
    final narrowFactor =
        (distFromPivot / (imageSize.height * 0.08)).clamp(0.35, 1.0);
    final ratio =
        (towardCenter.abs() / (imageSize.width * 0.5)).clamp(0.2, 1.0);
    return Offset(
      towardCenter.sign * narrow * ratio * narrowFactor,
      -lift * narrowFactor,
    );
  }

  static Offset _cheekbone({
    required int index,
    required Size imageSize,
    required double rawIntensity,
  }) {
    final t = rawIntensity.clamp(0.0, 1.0);
    final lift = imageSize.height * 0.012 * t;
    final outward = imageSize.width * 0.018 * t;
    if (FaceWarpUtils.cheekboneLeft.contains(index)) {
      return Offset(-outward, -lift);
    }
    if (FaceWarpUtils.cheekboneRight.contains(index)) {
      return Offset(outward, -lift);
    }
    return Offset.zero;
  }

  static Offset _forehead({
    required int index,
    required Size imageSize,
    required double rawIntensity,
  }) {
    if (ForeheadFilter.hairlineLandmarkIndices.contains(index)) {
      return Offset.zero;
    }
    if (!_foreheadLower.contains(index)) {
      return Offset.zero;
    }
    final lift = imageSize.height * 0.022 * rawIntensity.clamp(0.0, 1.0);
    return Offset(0, -lift);
  }

  static Offset _temple({
    required int index,
    required Size imageSize,
    required double rawIntensity,
  }) {
    final maxShift = imageSize.width * 0.06 * rawIntensity.clamp(0.0, 1.0);
    if (_templeLeft.contains(index)) {
      return Offset(maxShift, 0);
    }
    if (_templeRight.contains(index)) {
      return Offset(-maxShift, 0);
    }
    return Offset.zero;
  }

  static Offset _headSize({
    required int index,
    required Offset base,
    required FaceMeshResult face,
    required Size imageSize,
    required double rawIntensity,
  }) {
    if (FaceWarpUtils.isIrisLandmark(index)) {
      return Offset.zero;
    }
    if (!FaceWarpUtils.regionIndices(MeshRegion.faceOval).contains(index)) {
      return Offset.zero;
    }
    final center = FaceWarpUtils.faceOvalCenter(face, imageSize) ??
        FaceWarpUtils.faceCenter(face, imageSize);
    if (center == null) {
      return Offset.zero;
    }
    final scale = 1.0 - 0.1 * rawIntensity.clamp(0.0, 1.0);
    return PilotWarpDisplacement.scaleAbout(base, center, scale);
  }

  static Offset _noseLength({
    required int index,
    required Size imageSize,
    required double rawIntensity,
  }) {
    if (!_noseLengthIndices.contains(index)) {
      return Offset.zero;
    }
    final shiftY = imageSize.height * 0.04 * rawIntensity.clamp(0.0, 1.0);
    return Offset(0, shiftY);
  }

  static Offset _noseHeight({
    required int index,
    required Size imageSize,
    required double rawIntensity,
  }) {
    if (!FaceWarpUtils.regionIndices(MeshRegion.nose).contains(index)) {
      return Offset.zero;
    }
    final shiftY = -imageSize.height * 0.025 * rawIntensity.clamp(0.0, 1.0);
    return Offset(0, shiftY);
  }

  static Offset _noseTip({
    required int index,
    required Offset base,
    required TriMesh mesh,
    required Size imageSize,
    required double rawIntensity,
  }) {
    if (!_noseTipIndices.contains(index)) {
      return Offset.zero;
    }
    final axis = FaceWarpUtils.noseAxisCenter(mesh);
    final lift = -imageSize.height * 0.02 * rawIntensity.clamp(0.0, 1.0);
    final slim = imageSize.width * 0.02 * rawIntensity.clamp(0.0, 1.0);
    final towardAxis = axis.dx - base.dx;
    return Offset(towardAxis.sign * slim * 0.5, lift);
  }

  static Offset _noseBridge({
    required int index,
    required Offset base,
    required TriMesh mesh,
    required Size imageSize,
    required double rawIntensity,
  }) {
    if (!_noseBridgeIndices.contains(index)) {
      return Offset.zero;
    }
    final axis = FaceWarpUtils.noseAxisCenter(mesh);
    final slim = imageSize.width * 0.025 * rawIntensity.clamp(0.0, 1.0);
    final lift = -imageSize.height * 0.012 * rawIntensity.clamp(0.0, 1.0);
    final towardAxis = axis.dx - base.dx;
    return Offset(towardAxis.sign * slim * 0.6, lift);
  }

  static bool _inCheek(int index) {
    return VertexRoleMap.cheekLeft.contains(index) ||
        VertexRoleMap.cheekRight.contains(index);
  }

  static bool _inJawRegion(int index) {
    return VertexRoleMap.jawLeft.contains(index) ||
        VertexRoleMap.jawRight.contains(index);
  }
}
