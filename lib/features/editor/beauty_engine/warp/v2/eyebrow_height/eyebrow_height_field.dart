import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_mesh_result.dart';
import '../boundary_feather.dart';
import '../displacement_field.dart';
import '../distance_transform.dart';
import '../region_catalog.dart';
import 'eyebrow_height_masks.dart';
import 'eyebrow_height_metrics.dart';

class EyebrowHeightFieldBuild {
  const EyebrowHeightFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
  });

  final DisplacementField field;
  final EyebrowHeightMasks masks;
  final EyebrowHeightFieldMetrics metrics;
}

/// Cache do peso unitário (independente de t). O slider só escala `dy` por lado.
class EyebrowHeightFieldRuntime {
  FaceMeshResult? face;
  int width = 0;
  int height = 0;
  double faceWidth = 1;
  Float32List? unitWeight;
  Float32List? leftFrac;
  List<int>? active;
  DisplacementField? field;
  EyebrowHeightMasks? masks;

  bool matches(FaceMeshResult face, int width, int height) {
    return identical(this.face, face) &&
        this.width == width &&
        this.height == height &&
        unitWeight != null &&
        leftFrac != null &&
        active != null &&
        field != null &&
        masks != null;
  }
}

/// Constrói o campo de altura da sobrancelha (só Δy). Sem RGBA, sem render.
///
/// Planalto no hull. Sem crista com pesos a cair. Não importa outros Fields.
abstract final class EyebrowHeightField {
  EyebrowHeightField._();

  /// Arco superior. MediaPipe esquerdo = lado direito da foto.
  static const primaryLeft = 334;
  static const primaryRight = 105;

  /// Contorno inferior da ilha.
  static const lowerLeft = 282;
  static const lowerRight = 52;

  /// Pálpebra superior.
  static const lidLeft = 386;
  static const lidRight = 159;

  static const hairlineTop = 10;

  static const amplitudeFaceWidth = 0.035;
  static const falloffFaceWidth = 0.12;
  static const hullPadFaceWidth = 0.14;
  static const lidFalloffFaceWidth = 0.08;
  static const outerLidLiftFaceWidth = 0.026;
  static const sideBlendFaceWidth = 0.12;
  static const boundarySmoothFaceWidth = 0.022;

  static EyebrowHeightFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    double t = 0,
    double? tPhotoLeft,
    double? tPhotoRight,
    bool computeMetrics = true,
    EyebrowHeightFieldRuntime? runtime,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError(
          'eyebrow_height_field_invalid_size: ${width}x$height');
    }

    final signedLeft = (tPhotoLeft ?? t).clamp(-1.0, 1.0);
    final signedRight = (tPhotoRight ?? t).clamp(-1.0, 1.0);

    if (runtime != null && runtime.matches(face, width, height)) {
      final ampScale = amplitudeFaceWidth * runtime.faceWidth;
      // Direita (t>0) = sobe (dy < 0). Foto esquerda = cadeia MP direita.
      final amplitudeMpLeft = -signedRight * ampScale;
      final amplitudeMpRight = -signedLeft * ampScale;
      _scaleActive(
        field: runtime.field!,
        unitWeight: runtime.unitWeight!,
        leftFrac: runtime.leftFrac!,
        active: runtime.active!,
        amplitudeMpLeft: amplitudeMpLeft,
        amplitudeMpRight: amplitudeMpRight,
      );
      final amplitude = math.max(amplitudeMpLeft.abs(), amplitudeMpRight.abs());
      final metrics = computeMetrics
          ? EyebrowHeightFieldMetrics.compute(
              field: runtime.field!,
              masks: runtime.masks!,
              px: EyebrowHeightMasks.landmarkPixels(face, imageSize),
              faceWidth: runtime.faceWidth,
              amplitude: amplitude,
              primaryLeft: primaryLeft,
              primaryRight: primaryRight,
              lowerLeft: lowerLeft,
              lowerRight: lowerRight,
              lidLeft: lidLeft,
              lidRight: lidRight,
              hairlineTop: hairlineTop,
            )
          : EyebrowHeightFieldMetrics.skipped;
      return EyebrowHeightFieldBuild(
        field: runtime.field!,
        masks: runtime.masks!,
        metrics: metrics,
      );
    }

    final px = EyebrowHeightMasks.landmarkPixels(face, imageSize);
    final faceWidth = EyebrowHeightMasks.faceWidthOf(px);
    final masks = EyebrowHeightMasks.build(
      face: face,
      imageSize: imageSize,
      hullPadFaceWidth: hullPadFaceWidth,
      outerLidLiftFaceWidth: outerLidLiftFaceWidth,
    );
    final ampScale = amplitudeFaceWidth * faceWidth;
    final amplitudeMpLeft = -signedRight * ampScale;
    final amplitudeMpRight = -signedLeft * ampScale;
    final amplitude = math.max(amplitudeMpLeft.abs(), amplitudeMpRight.abs());
    final packed = _packUnitWeights(
      width: width,
      height: height,
      masks: masks,
      px: px,
      faceWidth: faceWidth,
    );
    final field = DisplacementField.zeros(width: width, height: height);
    if (amplitude > 1e-6) {
      _scaleActive(
        field: field,
        unitWeight: packed.unitWeight,
        leftFrac: packed.leftFrac,
        active: packed.active,
        amplitudeMpLeft: amplitudeMpLeft,
        amplitudeMpRight: amplitudeMpRight,
      );
    }

    if (runtime != null) {
      runtime
        ..face = face
        ..width = width
        ..height = height
        ..faceWidth = faceWidth
        ..unitWeight = packed.unitWeight
        ..leftFrac = packed.leftFrac
        ..active = packed.active
        ..field = field
        ..masks = masks;
    }

    final metrics = computeMetrics
        ? EyebrowHeightFieldMetrics.compute(
            field: field,
            masks: masks,
            px: px,
            faceWidth: faceWidth,
            amplitude: amplitude,
            primaryLeft: primaryLeft,
            primaryRight: primaryRight,
            lowerLeft: lowerLeft,
            lowerRight: lowerRight,
            lidLeft: lidLeft,
            lidRight: lidRight,
            hairlineTop: hairlineTop,
          )
        : EyebrowHeightFieldMetrics.skipped;
    return EyebrowHeightFieldBuild(
      field: field,
      masks: masks,
      metrics: metrics,
    );
  }

  static ({
    Float32List unitWeight,
    Float32List leftFrac,
    List<int> active,
  }) _packUnitWeights({
    required int width,
    required int height,
    required EyebrowHeightMasks masks,
    required List<Offset?> px,
    required double faceWidth,
  }) {
    final falloff = math.max(12.0, falloffFaceWidth * faceWidth);
    final lidFalloff = math.max(8.0, lidFalloffFaceWidth * faceWidth);
    final sideBlend = math.max(10.0, sideBlendFaceWidth * faceWidth);
    final leftC = _centroid(px, V2RegionCatalog.browLeft);
    final rightC = _centroid(px, V2RegionCatalog.browRight);
    final boundaryRamp = BoundaryFeather.insideActive(
      mask: masks.browActive,
      width: width,
      height: height,
      falloffPx: falloff,
      sigmaPx: math.max(1.0, boundarySmoothFaceWidth * faceWidth),
    );
    final distToEyes = EuclideanDistanceTransform.toNonZeroOf(
      masks.eyes,
      width,
      height,
    );
    final pixelCount = width * height;
    final active = <int>[];
    final weights = <double>[];
    final leftFracs = <double>[];
    for (var i = 0; i < pixelCount; i++) {
      if (masks.browActive[i] == 0) {
        continue;
      }
      if (masks.eyes[i] != 0) {
        continue;
      }
      final boundary = boundaryRamp[i];
      if (boundary <= 1e-6) {
        continue;
      }
      final lidT = distToEyes[i] / lidFalloff;
      final lidGate = lidT >= 1.0 ? 1.0 : lidT * lidT * (3.0 - 2.0 * lidT);
      final weight = boundary * lidGate;
      if (weight <= 1e-6) {
        continue;
      }
      final x = (i % width) + 0.5;
      final y = (i ~/ width) + 0.5;
      active.add(i);
      weights.add(weight);
      leftFracs.add(_leftFrac(x, y, leftC, rightC, sideBlend));
    }
    return (
      unitWeight: Float32List.fromList(weights),
      leftFrac: Float32List.fromList(leftFracs),
      active: active,
    );
  }

  static void _scaleActive({
    required DisplacementField field,
    required Float32List unitWeight,
    required Float32List leftFrac,
    required List<int> active,
    required double amplitudeMpLeft,
    required double amplitudeMpRight,
  }) {
    for (var k = 0; k < active.length; k++) {
      final i = active[k];
      final frac = leftFrac[k];
      final amp = frac * amplitudeMpLeft + (1.0 - frac) * amplitudeMpRight;
      field.dx[i] = 0;
      field.dy[i] = amp * unitWeight[k];
    }
  }

  static Offset? _centroid(List<Offset?> px, Set<int> ids) {
    var sx = 0.0;
    var sy = 0.0;
    var n = 0;
    for (final id in ids) {
      final p = id < px.length ? px[id] : null;
      if (p == null) {
        continue;
      }
      sx += p.dx;
      sy += p.dy;
      n++;
    }
    if (n == 0) {
      return null;
    }
    return Offset(sx / n, sy / n);
  }

  static double _leftFrac(
    double x,
    double y,
    Offset? left,
    Offset? right,
    double blend,
  ) {
    if (left == null) {
      return 0;
    }
    if (right == null) {
      return 1;
    }
    final dl = math.sqrt(
      (x - left.dx) * (x - left.dx) + (y - left.dy) * (y - left.dy),
    );
    final dr = math.sqrt(
      (x - right.dx) * (x - right.dx) + (y - right.dy) * (y - right.dy),
    );
    final t = ((dr - dl) / blend + 1.0) * 0.5;
    if (t <= 0) {
      return 0;
    }
    if (t >= 1) {
      return 1;
    }
    return t * t * (3.0 - 2.0 * t);
  }
}
