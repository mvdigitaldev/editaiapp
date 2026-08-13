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

  static const _foreheadLower = {297, 332, 109, 67, 103, 54, 21};
  static const _foreheadExpanded = {
    ..._foreheadLower,
    127,
    162,
    356,
    389,
  };
  static const _cheekboneRingLeft = {207, 206, 203, 142, 126, 217};
  static const _cheekboneRingRight = {427, 436, 426, 423, 266, 371};
  static const _templeLeft = {234, 127, 162, 93, 21};
  static const _templeRight = {251, 284, 356, 389, 297};
  static const _noseLengthIndices = {1, 2, 4, 5, 19, 94, 98, 97, 326, 327, 294, 278};
  static const _noseTipIndices = {1, 2, 98, 97, 326, 327, 4, 5, 19};
  static const _noseBridgeIndices = {168, 6, 197, 195, 5, 4, 45, 275};

  static double _effectiveMag(double magnitude) =>
      math.pow(magnitude.clamp(0.0, 1.0), 1.35).toDouble();

  static double _maxPxFromSpec({
    required FaceToolSpecification spec,
    required double fse,
    required double magnitude,
    double capFactor = 0.95,
  }) {
    return (spec.maxDisplacementFse ?? 0.08) *
        fse *
        _effectiveMag(magnitude) *
        capFactor;
  }

  static double _edgeWeight({
    required Offset base,
    required double centerX,
    required double fse,
  }) {
    final halfFace = fse * 0.48;
    if (halfFace <= 1e-6) {
      return 0;
    }
    final lateral = (base.dx - centerX).abs();
    return math.pow((lateral / halfFace).clamp(0.0, 1.0), 0.72).toDouble();
  }

  static double _zoneWeightNy(double ny) {
    var zoneWeight = 1.0;
    if (ny < 0.40) {
      zoneWeight = (0.42 + 0.58 * (ny / 0.40)).clamp(0.42, 1.0);
    }
    if (ny > 0.66) {
      zoneWeight *= (1.0 - (ny - 0.66) / 0.24).clamp(0.0, 1.0);
      zoneWeight = zoneWeight.clamp(0.30, 1.0);
    }
    return zoneWeight;
  }

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
          spec: spec,
          magnitude: magnitude,
          fse: fse,
        ),
      'jaw' => _jaw(
          index: landmarkIndex,
          base: base,
          face: face,
          imageSize: imageSize,
          spec: spec,
          rawIntensity: rawIntensity,
          fse: fse,
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
          spec: spec,
          magnitude: magnitude,
          fse: fse,
        ),
      'forehead' => _forehead(
          index: landmarkIndex,
          base: base,
          face: face,
          imageSize: imageSize,
          spec: spec,
          magnitude: magnitude,
          fse: fse,
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
    final maxPx = _maxPxFromSpec(
      spec: spec,
      fse: fse,
      magnitude: magnitude,
      capFactor: 0.95,
    );
    if (maxPx <= 0) {
      return Offset.zero;
    }
    final centerX = FaceWarpUtils.faceCenterX(face, imageSize);
    final towardCenter = centerX - base.dx;
    final ny = base.dy / imageSize.height;
    final edge = _edgeWeight(base: base, centerX: centerX, fse: fse);
    final zone = _zoneWeightNy(ny);
    return Offset(towardCenter.sign * maxPx * edge * zone, 0);
  }

  static Offset _vFace({
    required int index,
    required Offset base,
    required FaceMeshResult face,
    required Size imageSize,
    required FaceToolSpecification spec,
    required double magnitude,
    required double fse,
  }) {
    final t = magnitude.clamp(0.0, 1.0);
    final jawShift = imageSize.width * 0.14 * t;
    final chinLift = imageSize.height * 0.025 * t;
    final centerX = FaceWarpUtils.faceCenterX(face, imageSize);

    if (_inJawRegion(index)) {
      final towardCenter = centerX - base.dx;
      final ratio =
          (towardCenter.abs() / (imageSize.width * 0.5)).clamp(0.0, 1.0);
      return Offset(
        towardCenter.sign * jawShift * ratio,
        -chinLift * 0.3 * ratio,
      );
    }
    if (VertexRoleMap.chin.contains(index)) {
      return Offset(0, -chinLift);
    }
    return Offset.zero;
  }

  static Offset _jaw({
    required int index,
    required Offset base,
    required FaceMeshResult face,
    required Size imageSize,
    required FaceToolSpecification spec,
    required double rawIntensity,
    required double fse,
  }) {
    if (!VertexRoleMap.jawLeft.contains(index) &&
        !VertexRoleMap.jawRight.contains(index)) {
      return Offset.zero;
    }
    final t = rawIntensity.clamp(0.0, 1.0);
    final maxShift = math.min(
      imageSize.width * 0.09 * t,
      (spec.maxDisplacementFse ?? 0.07) * fse * t,
    );
    final centerX = FaceWarpUtils.faceCenterX(face, imageSize);
    final towardCenter = centerX - base.dx;
    final ratio =
        (towardCenter.abs() / (imageSize.width * 0.5)).clamp(1.0, double.infinity);
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
        (distFromPivot / (imageSize.height * 0.08)).clamp(0.55, 1.0);
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
    required FaceToolSpecification spec,
    required double magnitude,
    required double fse,
  }) {
    final maxMag = _maxPxFromSpec(
      spec: spec,
      fse: fse,
      magnitude: magnitude,
      capFactor: 0.95,
    );
    if (maxMag <= 0) {
      return Offset.zero;
    }

    double tierWeight = 0;
    double outwardSign = 0;
    if (FaceWarpUtils.cheekboneLeft.contains(index)) {
      tierWeight = 1.0;
      outwardSign = -1.0;
    } else if (_cheekboneRingLeft.contains(index)) {
      tierWeight = 0.65;
      outwardSign = -1.0;
    } else if (FaceWarpUtils.cheekboneRight.contains(index)) {
      tierWeight = 1.0;
      outwardSign = 1.0;
    } else if (_cheekboneRingRight.contains(index)) {
      tierWeight = 0.65;
      outwardSign = 1.0;
    } else {
      return Offset.zero;
    }

    const outwardRatio = 0.81;
    const liftRatio = 0.59;
    final amp = maxMag * tierWeight;
    return Offset(outwardSign * amp * outwardRatio, -amp * liftRatio);
  }

  static Offset _forehead({
    required int index,
    required Offset base,
    required FaceMeshResult face,
    required Size imageSize,
    required FaceToolSpecification spec,
    required double magnitude,
    required double fse,
  }) {
    if (ForeheadFilter.hairlineLandmarkIndices.contains(index)) {
      return Offset.zero;
    }
    if (!_foreheadExpanded.contains(index)) {
      return Offset.zero;
    }

    final ny = base.dy / imageSize.height;
    var vertWeight = 1.0;
    if ({127, 162, 356, 389}.contains(index)) {
      vertWeight = 0.65;
    } else if (ny < 0.24) {
      vertWeight = (ny / 0.24).clamp(0.70, 1.0);
    }

    final lift = imageSize.height * 0.022 * magnitude.clamp(0.0, 1.0) * vertWeight;
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
