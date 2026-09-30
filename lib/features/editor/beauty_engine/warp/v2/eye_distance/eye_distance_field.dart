import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_mesh_result.dart';
import '../boundary_feather.dart';
import '../displacement_field.dart';
import '../distance_transform.dart';
import '../region_catalog.dart';
import 'eye_distance_masks.dart';
import 'eye_distance_metrics.dart';

class EyeDistanceFieldBuild {
  const EyeDistanceFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
  });

  final DisplacementField field;
  final EyeDistanceMasks masks;
  final EyeDistanceFieldMetrics metrics;
}

/// Cache do peso de cada olho. O slider só escala `dx`.
class EyeDistanceFieldRuntime {
  FaceMeshResult? face;
  int width = 0;
  int height = 0;
  double faceWidth = 1;
  Float32List? unitDxLeft;
  Float32List? unitDxRight;
  List<int>? active;
  DisplacementField? field;
  EyeDistanceMasks? masks;

  bool matches(FaceMeshResult face, int width, int height) {
    return identical(this.face, face) &&
        this.width == width &&
        this.height == height &&
        unitDxLeft != null &&
        unitDxRight != null &&
        active != null &&
        field != null &&
        masks != null;
  }
}

/// Afasta ou aproxima cada olho da linha do meio. Só Δx. A íris anda.
///
/// Esquerda do slider aproxima. Direita afasta. Não importa outros Fields.
abstract final class EyeDistanceField {
  EyeDistanceField._();

  /// Íris. 468 = foto esquerda. 473 = foto direita. Anda com o olho.
  static const centerPhotoLeft = 468;
  static const centerPhotoRight = 473;

  static const outerPhotoLeft = 33;
  static const outerPhotoRight = 263;

  /// Centro da pálpebra de cima. Tem de andar com a íris.
  static const lidPhotoLeft = 159;
  static const lidPhotoRight = 386;

  static const browPhotoLeft = 105;
  static const browPhotoRight = 334;
  static const hairlineTop = 10;

  /// Translação horizontal, em fracção da largura da cara.
  static const amplitudeFaceWidth = 0.030;
  static const falloffFaceWidth = 0.07;

  /// O contorno fica dentro do planalto. Com 0.025 o canto externo
  /// ainda estava na rampa e a íris andava sozinha.
  static const hullPadFaceWidth = 0.09;

  /// Porta do nariz. A da sobrancelha não usa esta fracção: mede o vão
  /// real até à pálpebra, senão a pálpebra fica presa e a íris anda sozinha.
  static const guardFalloffFaceWidth = 0.10;
  static const boundarySmoothFaceWidth = 0.022;

  static EyeDistanceFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    double t = 0,
    double? tPhotoLeft,
    double? tPhotoRight,
    bool computeMetrics = true,
    EyeDistanceFieldRuntime? runtime,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError(
        'eye_distance_field_invalid_size: ${width}x$height',
      );
    }

    final signedLeft = (tPhotoLeft ?? t).clamp(-1.0, 1.0);
    final signedRight = (tPhotoRight ?? t).clamp(-1.0, 1.0);

    if (runtime != null && runtime.matches(face, width, height)) {
      final amp = amplitudeFaceWidth * runtime.faceWidth;
      _scaleActive(
        field: runtime.field!,
        active: runtime.active!,
        unitDxLeft: runtime.unitDxLeft!,
        unitDxRight: runtime.unitDxRight!,
        dxLeft: signedLeft * amp,
        dxRight: signedRight * amp,
      );
      final metrics = computeMetrics
          ? EyeDistanceFieldMetrics.compute(
              field: runtime.field!,
              masks: runtime.masks!,
              px: EyeDistanceMasks.landmarkPixels(face, imageSize),
              faceWidth: runtime.faceWidth,
              centerLeft: centerPhotoLeft,
              centerRight: centerPhotoRight,
              outerLeft: outerPhotoLeft,
              outerRight: outerPhotoRight,
              lidLeft: lidPhotoLeft,
              lidRight: lidPhotoRight,
              browLeft: browPhotoLeft,
              browRight: browPhotoRight,
              hairlineTop: hairlineTop,
            )
          : EyeDistanceFieldMetrics.skipped;
      return EyeDistanceFieldBuild(
        field: runtime.field!,
        masks: runtime.masks!,
        metrics: metrics,
      );
    }

    final px = EyeDistanceMasks.landmarkPixels(face, imageSize);
    final faceWidth = EyeDistanceMasks.faceWidthOf(px);
    final masks = EyeDistanceMasks.build(
      face: face,
      imageSize: imageSize,
      hullPadFaceWidth: hullPadFaceWidth,
    );
    final packed = _packUnits(
      width: width,
      height: height,
      masks: masks,
      px: px,
      faceWidth: faceWidth,
    );
    final field = DisplacementField.zeros(width: width, height: height);
    final amp = amplitudeFaceWidth * faceWidth;
    _scaleActive(
      field: field,
      active: packed.active,
      unitDxLeft: packed.unitDxLeft,
      unitDxRight: packed.unitDxRight,
      dxLeft: signedLeft * amp,
      dxRight: signedRight * amp,
    );

    if (runtime != null) {
      runtime
        ..face = face
        ..width = width
        ..height = height
        ..faceWidth = faceWidth
        ..unitDxLeft = packed.unitDxLeft
        ..unitDxRight = packed.unitDxRight
        ..active = packed.active
        ..field = field
        ..masks = masks;
    }

    final metrics = computeMetrics
        ? EyeDistanceFieldMetrics.compute(
            field: field,
            masks: masks,
            px: px,
            faceWidth: faceWidth,
            centerLeft: centerPhotoLeft,
            centerRight: centerPhotoRight,
            outerLeft: outerPhotoLeft,
            outerRight: outerPhotoRight,
            lidLeft: lidPhotoLeft,
            lidRight: lidPhotoRight,
            browLeft: browPhotoLeft,
            browRight: browPhotoRight,
            hairlineTop: hairlineTop,
          )
        : EyeDistanceFieldMetrics.skipped;
    return EyeDistanceFieldBuild(
      field: field,
      masks: masks,
      metrics: metrics,
    );
  }

  static ({
    Float32List unitDxLeft,
    Float32List unitDxRight,
    List<int> active,
  }) _packUnits({
    required int width,
    required int height,
    required EyeDistanceMasks masks,
    required List<Offset?> px,
    required double faceWidth,
  }) {
    final falloff = math.max(8.0, falloffFaceWidth * faceWidth);
    final guard = math.max(8.0, guardFalloffFaceWidth * faceWidth);
    final sigma = math.max(1.0, boundarySmoothFaceWidth * faceWidth);
    final rampLeft = BoundaryFeather.insideActive(
      mask: masks.photoLeft,
      width: width,
      height: height,
      falloffPx: falloff,
      sigmaPx: sigma,
    );
    final rampRight = BoundaryFeather.insideActive(
      mask: masks.photoRight,
      width: width,
      height: height,
      falloffPx: falloff,
      sigmaPx: sigma,
    );
    final distBrow = EuclideanDistanceTransform.toNonZeroOf(
      masks.brows,
      width,
      height,
    );
    final distNose = EuclideanDistanceTransform.toNonZeroOf(
      masks.nose,
      width,
      height,
    );
    final cLeft = _center(px, centerPhotoLeft, V2RegionCatalog.rightEye);
    final cRight = _center(px, centerPhotoRight, V2RegionCatalog.leftEye);
    final midX = (cLeft.dx + cRight.dx) * 0.5;
    final sideLeft = (cLeft.dx - midX).sign;
    final sideRight = (cRight.dx - midX).sign;
    final gapLeft = _browGap(
      distBrow,
      _center(px, lidPhotoLeft, V2RegionCatalog.rightEye),
      width,
    );
    final gapRight = _browGap(
      distBrow,
      _center(px, lidPhotoRight, V2RegionCatalog.leftEye),
      width,
    );
    final browGateLeft = _softGate(distBrow, gapLeft, width, height);
    final browGateRight = _softGate(distBrow, gapRight, width, height);

    final active = <int>[];
    final dxL = <double>[];
    final dxR = <double>[];
    for (var i = 0; i < width * height; i++) {
      final rampL = rampLeft[i];
      final rampR = rampRight[i];
      if (rampL <= 1e-6 && rampR <= 1e-6) {
        continue;
      }
      final noseW = _smoothstep(distNose[i] / guard);
      if (noseW <= 1e-6 &&
          browGateLeft[i] <= 1e-6 &&
          browGateRight[i] <= 1e-6) {
        continue;
      }
      var wL = rampL * noseW * browGateLeft[i];
      var wR = rampR * noseW * browGateRight[i];
      if (wL <= 1e-6 && wR <= 1e-6) {
        continue;
      }
      active.add(i);
      dxL.add(wL * sideLeft);
      dxR.add(wR * sideRight);
    }
    return (
      unitDxLeft: Float32List.fromList(dxL),
      unitDxRight: Float32List.fromList(dxR),
      active: active,
    );
  }

  static void _scaleActive({
    required DisplacementField field,
    required List<int> active,
    required Float32List unitDxLeft,
    required Float32List unitDxRight,
    required double dxLeft,
    required double dxRight,
  }) {
    for (var k = 0; k < active.length; k++) {
      final i = active[k];
      field.dx[i] = dxLeft * unitDxLeft[k] + dxRight * unitDxRight[k];
      field.dy[i] = 0;
    }
  }

  static Offset _center(List<Offset?> px, int id, Set<int> fallback) {
    final p = id < px.length ? px[id] : null;
    if (p != null) {
      return p;
    }
    var sx = 0.0;
    var sy = 0.0;
    var n = 0;
    for (final i in fallback) {
      final q = i < px.length ? px[i] : null;
      if (q == null) {
        continue;
      }
      sx += q.dx;
      sy += q.dy;
      n++;
    }
    if (n == 0) {
      return Offset.zero;
    }
    return Offset(sx / n, sy / n);
  }

  /// Porta 1 na pálpebra, 0 na sobrancelha, borrada para não vincar o vão.
  static Float32List _softGate(
    Float32List distBrow,
    double gap,
    int width,
    int height,
  ) {
    final gate = Float32List(distBrow.length);
    for (var i = 0; i < distBrow.length; i++) {
      gate[i] = _smoothstep(distBrow[i] / gap);
    }
    final scratch = Float32List(gate.length);
    const radius = 3;
    for (var pass = 0; pass < 2; pass++) {
      _boxHorizontal(gate, scratch, width, height, radius);
      _boxVertical(scratch, gate, width, height, radius);
    }
    return gate;
  }

  static void _boxHorizontal(
    Float32List src,
    Float32List dst,
    int width,
    int height,
    int radius,
  ) {
    final window = 2 * radius + 1;
    final norm = 1.0 / window;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      var sum = src[row] * (radius + 1);
      for (var x = 1; x <= radius; x++) {
        sum += src[row + math.min(x, width - 1)];
      }
      for (var x = 0; x < width; x++) {
        dst[row + x] = sum * norm;
        sum += src[row + math.min(x + radius + 1, width - 1)] -
            src[row + math.max(x - radius, 0)];
      }
    }
  }

  static void _boxVertical(
    Float32List src,
    Float32List dst,
    int width,
    int height,
    int radius,
  ) {
    final window = 2 * radius + 1;
    final norm = 1.0 / window;
    for (var x = 0; x < width; x++) {
      var sum = src[x] * (radius + 1);
      for (var y = 1; y <= radius; y++) {
        sum += src[math.min(y, height - 1) * width + x];
      }
      for (var y = 0; y < height; y++) {
        dst[y * width + x] = sum * norm;
        final addY = math.min(y + radius + 1, height - 1);
        final dropY = math.max(y - radius, 0);
        sum += src[addY * width + x] - src[dropY * width + x];
      }
    }
  }

  /// Vão da máscara da sobrancelha até à pálpebra. A pálpebra fica em peso 1.
  static double _browGap(Float32List distBrow, Offset lid, int width) {
    final x = lid.dx.round();
    final y = lid.dy.round();
    if (x < 0 || y < 0 || x >= width) {
      return 8;
    }
    final i = y * width + x;
    if (i < 0 || i >= distBrow.length) {
      return 8;
    }
    return math.max(6.0, distBrow[i]);
  }

  static double _smoothstep(double u) {
    if (u <= 0) {
      return 0;
    }
    if (u >= 1) {
      return 1;
    }
    return u * u * (3.0 - 2.0 * u);
  }
}
