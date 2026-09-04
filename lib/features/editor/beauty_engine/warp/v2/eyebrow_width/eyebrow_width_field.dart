import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_mesh_result.dart';
import '../boundary_feather.dart';
import '../displacement_field.dart';
import '../distance_transform.dart';
import '../region_catalog.dart';
import 'eyebrow_width_masks.dart';
import 'eyebrow_width_metrics.dart';

class EyebrowWidthFieldBuild {
  const EyebrowWidthFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
  });

  final DisplacementField field;
  final EyebrowWidthMasks masks;
  final EyebrowWidthFieldMetrics metrics;
}

/// Cache do peso unitário assinado (independente de t). O slider só escala `dy`.
class EyebrowWidthFieldRuntime {
  FaceMeshResult? face;
  int width = 0;
  int height = 0;
  double faceWidth = 1;
  Float32List? unitWeight;
  Float32List? leftFrac;
  List<int>? active;
  DisplacementField? field;
  EyebrowWidthMasks? masks;

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

/// Constrói o campo de largura da sobrancelha (engrossar / afinar, só Δy).
///
/// Abre a ilha a partir do eixo: arco sobe, base desce. Sem crista com pesos
/// a cair. Não importa outros Fields.
abstract final class EyebrowWidthField {
  EyebrowWidthField._();

  /// Arco superior. MediaPipe esquerdo = lado direito da foto.
  static const primaryLeft = 334;
  static const primaryRight = 105;

  /// Contorno inferior da ilha.
  static const lowerLeft = 282;
  static const lowerRight = 52;

  static const lidLeft = 386;
  static const lidRight = 159;
  static const hairlineTop = 10;

  /// Leonardo: leve engrossada, sem cara de edição. ~¼ da amplitude da Altura.
  static const amplitudeFaceWidth = 0.008;
  static const falloffFaceWidth = 0.12;
  static const hullPadFaceWidth = 0.14;
  static const lidFalloffFaceWidth = 0.08;
  static const outerLidLiftFaceWidth = 0.026;
  static const sideBlendFaceWidth = 0.12;
  static const boundarySmoothFaceWidth = 0.022;
  static const halfBandMinFaceWidth = 0.012;
  static const halfBandMaxFaceWidth = 0.024;

  /// Pares (superior, inferior) para o eixo da ilha. MP esquerdo / foto direita.
  static const _axisPairsLeft = [
    (300, 276),
    (293, 283),
    (334, 282),
    (296, 295),
    (336, 285),
  ];

  /// MP direito / foto esquerda.
  static const _axisPairsRight = [
    (70, 46),
    (63, 53),
    (105, 52),
    (66, 65),
    (107, 55),
  ];

  static EyebrowWidthFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    double t = 0,
    double? tPhotoLeft,
    double? tPhotoRight,
    bool computeMetrics = true,
    EyebrowWidthFieldRuntime? runtime,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('eyebrow_width_field_invalid_size: ${width}x$height');
    }

    final signedLeft = (tPhotoLeft ?? t).clamp(-1.0, 1.0);
    final signedRight = (tPhotoRight ?? t).clamp(-1.0, 1.0);

    if (runtime != null && runtime.matches(face, width, height)) {
      final ampScale = amplitudeFaceWidth * runtime.faceWidth;
      // t>0 engrossa. Foto esquerda = cadeia MP direita.
      final amplitudeMpLeft = signedRight * ampScale;
      final amplitudeMpRight = signedLeft * ampScale;
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
          ? EyebrowWidthFieldMetrics.compute(
              field: runtime.field!,
              masks: runtime.masks!,
              px: EyebrowWidthMasks.landmarkPixels(face, imageSize),
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
          : EyebrowWidthFieldMetrics.skipped;
      return EyebrowWidthFieldBuild(
        field: runtime.field!,
        masks: runtime.masks!,
        metrics: metrics,
      );
    }

    final px = EyebrowWidthMasks.landmarkPixels(face, imageSize);
    final faceWidth = EyebrowWidthMasks.faceWidthOf(px);
    final masks = EyebrowWidthMasks.build(
      face: face,
      imageSize: imageSize,
      hullPadFaceWidth: hullPadFaceWidth,
      outerLidLiftFaceWidth: outerLidLiftFaceWidth,
    );
    final ampScale = amplitudeFaceWidth * faceWidth;
    final amplitudeMpLeft = signedRight * ampScale;
    final amplitudeMpRight = signedLeft * ampScale;
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
        ? EyebrowWidthFieldMetrics.compute(
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
        : EyebrowWidthFieldMetrics.skipped;
    return EyebrowWidthFieldBuild(
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
    required EyebrowWidthMasks masks,
    required List<Offset?> px,
    required double faceWidth,
  }) {
    final falloff = math.max(12.0, falloffFaceWidth * faceWidth);
    final lidFalloff = math.max(8.0, lidFalloffFaceWidth * faceWidth);
    final sideBlend = math.max(10.0, sideBlendFaceWidth * faceWidth);
    final halfBand = _halfBand(px, faceWidth);
    final axis = _axisChains(px);
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
      final frac = _leftFrac(x, y, leftC, rightC, sideBlend);
      final s = _tanh(_axisSignedY(x, y, axis, frac) / halfBand);
      final unit = weight * s;
      if (unit.abs() <= 1e-6) {
        continue;
      }
      active.add(i);
      weights.add(unit);
      leftFracs.add(frac);
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

  static double _halfBand(List<Offset?> px, double faceWidth) {
    var sum = 0.0;
    var n = 0;
    for (final pair in [..._axisPairsLeft, ..._axisPairsRight]) {
      final upper = pair.$1 < px.length ? px[pair.$1] : null;
      final lower = pair.$2 < px.length ? px[pair.$2] : null;
      if (upper == null || lower == null) {
        continue;
      }
      sum += (upper - lower).distance;
      n++;
    }
    final measured = n == 0 ? 0.018 * faceWidth : 0.5 * sum / n;
    return measured.clamp(
      halfBandMinFaceWidth * faceWidth,
      halfBandMaxFaceWidth * faceWidth,
    );
  }

  /// Um Y por X em cada ilha. Sem argmin de segmento: na medial dois
  /// segmentos empatam e o `s` dá degrau — o núcleo vive nessas bandas.
  static ({List<Offset> left, List<Offset> right}) _axisChains(
    List<Offset?> px,
  ) {
    return (
      left: _axisMids(px, _axisPairsLeft),
      right: _axisMids(px, _axisPairsRight),
    );
  }

  static List<Offset> _axisMids(
    List<Offset?> px,
    List<(int, int)> pairs,
  ) {
    final mids = <Offset>[];
    for (final pair in pairs) {
      final upper = pair.$1 < px.length ? px[pair.$1] : null;
      final lower = pair.$2 < px.length ? px[pair.$2] : null;
      if (upper == null || lower == null) {
        continue;
      }
      mids.add(
          Offset((upper.dx + lower.dx) * 0.5, (upper.dy + lower.dy) * 0.5));
    }
    mids.sort((a, b) => a.dx.compareTo(b.dx));
    return mids;
  }

  static double _tanh(double x) {
    if (x > 20) {
      return 1;
    }
    if (x < -20) {
      return -1;
    }
    final e = math.exp(2.0 * x);
    return (e - 1.0) / (e + 1.0);
  }

  static double _axisSignedY(
    double x,
    double y,
    ({List<Offset> left, List<Offset> right}) chains,
    double leftFrac,
  ) {
    final yLeft = chains.left.isEmpty ? y : _interpAxisY(chains.left, x);
    final yRight = chains.right.isEmpty ? y : _interpAxisY(chains.right, x);
    if (chains.left.isEmpty) {
      return y - yRight;
    }
    if (chains.right.isEmpty) {
      return y - yLeft;
    }
    return y - (leftFrac * yLeft + (1.0 - leftFrac) * yRight);
  }

  static double _interpAxisY(List<Offset> mids, double x) {
    if (mids.length == 1) {
      return mids.first.dy;
    }
    if (x <= mids.first.dx) {
      return mids.first.dy;
    }
    if (x >= mids.last.dx) {
      return mids.last.dy;
    }
    for (var i = 0; i + 1 < mids.length; i++) {
      final a = mids[i];
      final b = mids[i + 1];
      if (x <= b.dx) {
        final span = b.dx - a.dx;
        if (span.abs() <= 1e-12) {
          return a.dy;
        }
        final t = (x - a.dx) / span;
        return a.dy + t * (b.dy - a.dy);
      }
    }
    return mids.last.dy;
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
