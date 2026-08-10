import 'dart:math' as math;
import 'dart:ui';

import '../../filters/face/face_warp_utils.dart';
import '../../filters/face/nose_slim.dart';
import '../../filters/face/smile.dart';
import '../../models/face_mesh_result.dart';
import '../../models/mesh_region.dart';
import '../../models/tri_mesh.dart';
import 'anatomical_zone.dart';
import 'face_model_specification.dart';
import 'pilot_warp_contour_nose.dart';
import 'vertex_role_map.dart';

/// Deslocamentos refinados V3 — espelham semântica MLS legada.
///
/// Sprint 34: contorno (`face_slim`, `nose_slim`) + `eye_scale`.
/// Sprint 35: demais olhos + boca (8 filtros olhos/boca no total).
abstract final class PilotWarpDisplacement {
  static const contourPilotToolKeys = {
    'face_slim',
    ...PilotWarpContourNose.contourVolumeToolKeys,
  };

  static const nosePilotToolKeys = {
    'nose_slim',
    ...PilotWarpContourNose.noseToolKeys,
  };

  static const eyeMouthPilotToolKeys = {
    'eye_scale',
    'eye_distance',
    'eye_height',
    'eye_rotation',
    'double_eyelid',
    'lip_thickness',
    'mouth_width',
    'smile',
  };

  static const pilotToolKeys = {
    ...contourPilotToolKeys,
    ...nosePilotToolKeys,
    ...eyeMouthPilotToolKeys,
  };

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
    required bool linkEyes,
    required double fse,
  }) {
    return switch (toolKey) {
      'face_slim' => _faceSlim(
          index: landmarkIndex,
          base: base,
          spec: spec,
          face: face,
          imageSize: imageSize,
          magnitude: magnitude,
          fse: fse,
        ),
      'nose_slim' => _noseSlim(
          index: landmarkIndex,
          base: base,
          spec: spec,
          mesh: mesh,
          imageSize: imageSize,
          magnitude: magnitude,
          fse: fse,
        ),
      'eye_scale' => _eyeScale(
          index: landmarkIndex,
          base: base,
          spec: spec,
          mesh: mesh,
          rawIntensity: rawIntensity,
        ),
      'eye_distance' => _eyeDistance(
          index: landmarkIndex,
          base: base,
          spec: spec,
          face: face,
          mesh: mesh,
          imageSize: imageSize,
          magnitude: magnitude,
          fse: fse,
        ),
      'eye_height' => _eyeHeight(
          index: landmarkIndex,
          spec: spec,
          mesh: mesh,
          magnitude: magnitude,
          fse: fse,
        ),
      'eye_rotation' => _eyeRotation(
          index: landmarkIndex,
          base: base,
          spec: spec,
          mesh: mesh,
          magnitude: magnitude,
          linkEyes: linkEyes,
        ),
      'double_eyelid' => _doubleEyelid(
          index: landmarkIndex,
          spec: spec,
          magnitude: magnitude,
          fse: fse,
        ),
      'lip_thickness' => _lipThickness(
          index: landmarkIndex,
          base: base,
          spec: spec,
          mesh: mesh,
          imageSize: imageSize,
          magnitude: magnitude,
          rawIntensity: rawIntensity,
          fse: fse,
        ),
      'mouth_width' => _mouthWidth(
          index: landmarkIndex,
          base: base,
          spec: spec,
          mesh: mesh,
          magnitude: magnitude,
          fse: fse,
        ),
      'smile' => _smile(
          index: landmarkIndex,
          spec: spec,
          rawIntensity: rawIntensity,
          magnitude: magnitude,
          fse: fse,
        ),
      _ when PilotWarpContourNose.contourVolumeToolKeys.contains(toolKey) ||
          PilotWarpContourNose.noseToolKeys.contains(toolKey) =>
        PilotWarpContourNose.deltaFor(
          toolKey: toolKey,
          landmarkIndex: landmarkIndex,
          base: base,
          spec: spec,
          face: face,
          mesh: mesh,
          imageSize: imageSize,
          magnitude: magnitude,
          rawIntensity: rawIntensity,
          fse: fse,
        ),
      _ => Offset.zero,
    };
  }

  /// B1 — bochechas/mandíbula/têmporas entram horizontalmente em direção ao eixo facial.
  ///
  /// Peso lateral concentra deslocamento no contorno externo; bochecha interna
  /// move menos → mais afinamento visível sem quadricular a pele central.
  static Offset _faceSlim({
    required int index,
    required Offset base,
    required FaceToolSpecification spec,
    required FaceMeshResult face,
    required Size imageSize,
    required double magnitude,
    required double fse,
  }) {
    if (!_inZones(index, spec.primaryZones) &&
        !_inZones(index, spec.freeZones)) {
      return Offset.zero;
    }

    final centerX = FaceWarpUtils.faceCenterX(face, imageSize);
    final towardCenter = centerX - base.dx;
    // Curva suave: slider alto não estoura displacement (73%+ deformava demais).
    final effectiveMag = math.pow(magnitude.clamp(0.0, 1.0), 1.35).toDouble();
    final maxPx = (spec.maxDisplacementFse ?? 0.08) * fse * effectiveMag;
    if (maxPx <= 0) {
      return Offset.zero;
    }

    final lateral = (base.dx - centerX).abs();
    final halfFace = fse * 0.48;
    if (halfFace <= 1e-6) {
      return Offset.zero;
    }

    final ny = base.dy / imageSize.height;
    // Orelha/têmpora alta: menos pull (evita deformar orelha).
    var zoneWeight = 1.0;
    if (ny < 0.40) {
      zoneWeight = (0.42 + 0.58 * (ny / 0.40)).clamp(0.42, 1.0);
    }
    // Mandíbula/barba baixa: atenua esmagamento horizontal da barba.
    if (ny > 0.66) {
      zoneWeight *= (1.0 - (ny - 0.66) / 0.24).clamp(0.0, 1.0);
      zoneWeight = zoneWeight.clamp(0.30, 1.0);
    }

    // Contorno ~100%, meio da bochecha ~50% — expoente maior = menos extremo.
    final edgeWeight = math.pow((lateral / halfFace).clamp(0.0, 1.0), 0.72)
        .toDouble();
    final shiftX = towardCenter.sign * maxPx * edgeWeight * zoneWeight;
    return Offset(shiftX, 0);
  }

  /// B2 — asas do nariz movem em direção ao eixo nasal.
  static Offset _noseSlim({
    required int index,
    required Offset base,
    required FaceToolSpecification spec,
    required TriMesh mesh,
    required Size imageSize,
    required double magnitude,
    required double fse,
  }) {
    final inPrimary = _inZones(index, spec.primaryZones);
    final inLateral = NoseSlimFilter.lateralIndices.contains(index);
    if (!inPrimary && !inLateral) {
      return Offset.zero;
    }

    final axis = FaceWarpUtils.noseAxisCenter(mesh);
    final towardAxis = axis.dx - base.dx;
    final maxPx = (spec.maxDisplacementFse ?? 0.08) * fse * magnitude;
    if (maxPx <= 0) {
      return Offset.zero;
    }
    final falloff =
        (towardAxis.abs() / imageSize.width).clamp(0.2, 1.0);
    final shiftX = towardAxis.sign * maxPx * falloff;
    return Offset(shiftX, 0);
  }

  /// B5 — escala local por olho (pivot no centro ocular, slider linear).
  static Offset _eyeScale({
    required int index,
    required Offset base,
    required FaceToolSpecification spec,
    required TriMesh mesh,
    required double rawIntensity,
  }) {
    final minS = spec.minScale ?? 1.0;
    final maxS = spec.maxScale ?? 1.26;
    // Slider linear (como MLS); magnitude eased fica no ACE para outros clamps.
    final t = rawIntensity.clamp(0.0, 1.0);
    final scale = minS + (maxS - minS) * t;
    if (scale <= 1.0 + 1e-6) {
      return Offset.zero;
    }

    MeshRegion? region;
    if (VertexRoleMap.eyeLeft.contains(index) ||
        const {468, 469, 470, 471, 472}.contains(index)) {
      region = MeshRegion.leftEye;
    } else if (VertexRoleMap.eyeRight.contains(index) ||
        const {473, 474, 475, 476, 477}.contains(index)) {
      region = MeshRegion.rightEye;
    }
    if (region == null) {
      return Offset.zero;
    }

    final center = FaceWarpUtils.eyeCenter(mesh, region);
    if (center == null) {
      return Offset.zero;
    }
    return _scaleAbout(base, center, scale);
  }

  /// Afasta olhos lateralmente (E←, D→) + leve stretch da ponte nasal.
  static Offset _eyeDistance({
    required int index,
    required Offset base,
    required FaceToolSpecification spec,
    required FaceMeshResult face,
    required TriMesh mesh,
    required Size imageSize,
    required double magnitude,
    required double fse,
  }) {
    if (FaceWarpUtils.isIrisLandmark(index)) {
      return Offset.zero;
    }
    final maxPx = (spec.maxDisplacementFse ?? 0.04) * fse * magnitude;
    if (maxPx <= 0) {
      return Offset.zero;
    }
    if (VertexRoleMap.eyeLeft.contains(index)) {
      return Offset(-maxPx, 0);
    }
    if (VertexRoleMap.eyeRight.contains(index)) {
      return Offset(maxPx, 0);
    }

    // Ponte nasal acompanha parcialmente — evita fantasma entre os olhos.
    if (VertexRoleMap.noseRoot.contains(index) ||
        VertexRoleMap.noseDorsum.contains(index)) {
      final centerX = FaceWarpUtils.faceCenterX(face, imageSize);
      final side = base.dx - centerX;
      if (side.abs() < 1e-6) {
        return Offset.zero;
      }
      final ratio = (side.abs() / (fse * 0.14)).clamp(0.25, 1.0);
      return Offset(side.sign * maxPx * 0.38 * ratio, 0);
    }
    return Offset.zero;
  }

  /// Eleva olhos verticalmente.
  static Offset _eyeHeight({
    required int index,
    required FaceToolSpecification spec,
    required TriMesh mesh,
    required double magnitude,
    required double fse,
  }) {
    if (FaceWarpUtils.isIrisLandmark(index)) {
      return Offset.zero;
    }
    final maxPx = (spec.maxDisplacementFse ?? 0.03) * fse * magnitude;
    if (maxPx <= 0) {
      return Offset.zero;
    }
    if (!_inEye(index)) {
      return Offset.zero;
    }
    return Offset(0, -maxPx);
  }

  /// Rotação sutil por olho em torno do centro ocular.
  static Offset _eyeRotation({
    required int index,
    required Offset base,
    required FaceToolSpecification spec,
    required TriMesh mesh,
    required double magnitude,
    required bool linkEyes,
  }) {
    if (FaceWarpUtils.isIrisLandmark(index)) {
      return Offset.zero;
    }

    final maxDeg = spec.maxRotationDegrees ?? 3.0;
    if (maxDeg <= 0) {
      return Offset.zero;
    }

    if (VertexRoleMap.eyeLeft.contains(index)) {
      final center = FaceWarpUtils.eyeCenter(mesh, MeshRegion.leftEye);
      if (center == null) {
        return Offset.zero;
      }
      final radians = maxDeg * magnitude * math.pi / 180.0;
      return _rotateAbout(base, center, radians);
    }
    if (VertexRoleMap.eyeRight.contains(index)) {
      final center = FaceWarpUtils.eyeCenter(mesh, MeshRegion.rightEye);
      if (center == null) {
        return Offset.zero;
      }
      final sign = linkEyes ? -1.0 : 1.0;
      final radians = maxDeg * magnitude * sign * math.pi / 180.0;
      return _rotateAbout(base, center, radians);
    }
    return Offset.zero;
  }

  /// Pálpebra superior — fold sutil para baixo.
  static Offset _doubleEyelid({
    required int index,
    required FaceToolSpecification spec,
    required double magnitude,
    required double fse,
  }) {
    final inEyelid = FaceWarpUtils.upperEyelidLeft.contains(index) ||
        FaceWarpUtils.upperEyelidRight.contains(index);
    if (!inEyelid) {
      return Offset.zero;
    }
    final maxPx = (spec.maxDisplacementFse ?? 0.02) * fse * magnitude;
    if (maxPx <= 0) {
      return Offset.zero;
    }
    return Offset(0, maxPx);
  }

  /// B6 — volume labial radial a partir do centro (linha média da boca).
  static Offset _lipThickness({
    required int index,
    required Offset base,
    required FaceToolSpecification spec,
    required TriMesh mesh,
    required Size imageSize,
    required double magnitude,
    required double rawIntensity,
    required double fse,
  }) {
    if (FaceWarpUtils.innerMouthExcluded.contains(index)) {
      return Offset.zero;
    }
    final inUpper = FaceWarpUtils.lipOuterUpper.contains(index);
    final inLower = FaceWarpUtils.lipOuterLower.contains(index);
    if (!inUpper && !inLower) {
      return Offset.zero;
    }

    // Centro/filotro fixos — preserva arco do cupido (invariante B6).
    if (VertexRoleMap.philtrum.contains(index) || index == 17) {
      return Offset.zero;
    }

    final center = FaceWarpUtils.lipCenter(mesh);
    if (center == null) {
      return Offset.zero;
    }

    // Semântica MLS (~1.4% altura), cap pela spec.
    final mlsPx = imageSize.height * 0.014 * rawIntensity.clamp(0.0, 1.0);
    final specPx = (spec.maxDisplacementFse ?? 0.04) * fse * magnitude;
    final expand = math.min(mlsPx, specPx);
    if (expand <= 0) {
      return Offset.zero;
    }

    final radial = base - center;
    final dist = radial.distance;
    if (dist < 1e-6) {
      return Offset.zero;
    }
    final dir = radial / dist;
    final edgeFalloff = (dist / (fse * 0.09)).clamp(0.45, 1.0);

    // Expansão radial externa — evita separar lábios como duas faixas opostas.
    if (inUpper && dir.dy <= -0.08) {
      return Offset(
        dir.dx * expand * 0.35 * edgeFalloff,
        dir.dy * expand * edgeFalloff,
      );
    }
    if (inLower && dir.dy >= 0.08) {
      return Offset(
        dir.dx * expand * 0.35 * edgeFalloff,
        dir.dy * expand * edgeFalloff,
      );
    }

    if (inUpper) {
      return Offset(
        dir.dx * expand * 0.25 * edgeFalloff,
        -expand * 0.65 * edgeFalloff,
      );
    }
    return Offset(
      dir.dx * expand * 0.25 * edgeFalloff,
      expand * 0.65 * edgeFalloff,
    );
  }

  /// Cantos e contorno labial afastam horizontalmente a partir do centro.
  static Offset _mouthWidth({
    required int index,
    required Offset base,
    required FaceToolSpecification spec,
    required TriMesh mesh,
    required double magnitude,
    required double fse,
  }) {
    final maxPx = (spec.maxDisplacementFse ?? 0.05) * fse * magnitude;
    if (maxPx <= 0) {
      return Offset.zero;
    }

    final center = FaceWarpUtils.lipCenter(mesh);
    if (center == null) {
      return Offset.zero;
    }

    final inLip = VertexRoleMap.upperLip.contains(index) ||
        VertexRoleMap.lowerLip.contains(index) ||
        VertexRoleMap.mouthCorner.contains(index);
    if (!inLip || FaceWarpUtils.innerMouthExcluded.contains(index)) {
      return Offset.zero;
    }

    final offsetX = base.dx - center.dx;
    if (offsetX.abs() < 1e-6) {
      return Offset.zero;
    }
    final ratio = (offsetX.abs() / (fse * 0.12)).clamp(0.35, 1.0);
    return Offset(offsetX.sign * maxPx * ratio, 0);
  }

  /// Sorriso sutil — cantos (e lábio em slider alto).
  static Offset _smile({
    required int index,
    required FaceToolSpecification spec,
    required double rawIntensity,
    required double magnitude,
    required double fse,
  }) {
    if (FaceWarpUtils.innerMouthExcluded.contains(index)) {
      return Offset.zero;
    }

    final indices = rawIntensity <= 0.5
        ? SmileFilter.smileLowIndices
        : {
            ...SmileFilter.smileLowIndices,
            ...SmileFilter.smileHighExtraIndices,
          };
    if (!indices.contains(index)) {
      return Offset.zero;
    }

    final maxPx = (spec.maxDisplacementFse ?? 0.04) * fse * magnitude;
    if (maxPx <= 0) {
      return Offset.zero;
    }
    return Offset(0, -maxPx);
  }

  static Offset scaleAbout(Offset base, Offset pivot, double scale) {
    return _scaleAbout(base, pivot, scale);
  }

  static Offset _scaleAbout(Offset base, Offset pivot, double scale) {
    final v = base - pivot;
    return pivot + v * scale - base;
  }

  static Offset _rotateAbout(Offset base, Offset pivot, double radians) {
    final v = base - pivot;
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    final rotated = Offset(
      v.dx * cos - v.dy * sin,
      v.dx * sin + v.dy * cos,
    );
    return pivot + rotated - base;
  }

  static bool _inEye(int index) {
    return VertexRoleMap.eyeLeft.contains(index) ||
        VertexRoleMap.eyeRight.contains(index);
  }

  static bool _inZones(int index, Set<AnatomicalZone> zones) {
    for (final zone in zones) {
      if (VertexRoleMap.landmarksFor(zone).contains(index)) {
        return true;
      }
    }
    return false;
  }
}
