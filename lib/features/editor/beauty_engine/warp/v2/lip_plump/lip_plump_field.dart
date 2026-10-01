import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_mesh_result.dart';
import '../boundary_feather.dart';
import '../displacement_field.dart';
import '../distance_transform.dart';
import 'lip_plump_masks.dart';
import 'lip_plump_metrics.dart';

class LipPlumpFieldBuild {
  const LipPlumpFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
  });

  final DisplacementField field;
  final LipPlumpMasks masks;
  final LipPlumpFieldMetrics metrics;
}

/// Cache dos pesos unitários (independente de t). O slider só escala `dy`.
class LipPlumpFieldRuntime {
  FaceMeshResult? face;
  int width = 0;
  int height = 0;
  double faceWidth = 1;
  Float32List? unitUpper;
  Float32List? unitLower;
  List<int>? active;
  DisplacementField? field;
  LipPlumpMasks? masks;

  bool matches(FaceMeshResult face, int width, int height) {
    return identical(this.face, face) &&
        this.width == width &&
        this.height == height &&
        unitUpper != null &&
        unitLower != null &&
        active != null &&
        field != null &&
        masks != null;
  }
}

/// Engrossa ou afina o beiço a partir da fenda. Só Δy.
///
/// Direita do slider engrossa. Esquerda afina.
/// Geral / apenas superior / apenas inferior. Não importa outros Fields.
abstract final class LipPlumpField {
  LipPlumpField._();

  /// Canto da foto à esquerda / direita. Fenda = média de 13 e 14.
  static const cornerLeft = 61;
  static const cornerRight = 291;
  static const innerUpper = 13;
  static const innerLower = 14;

  /// `s = 1 + k t`. t>0 abre o beiço; t<0 fecha sem cruzar a fenda.
  static const scaleGain = 0.22;
  static const falloffFaceWidth = 0.055;
  static const hullPadFaceWidth = 0.040;
  static const guardFalloffFaceWidth = 0.045;
  static const boundarySmoothFaceWidth = 0.022;
  static const bandBlendFaceWidth = 0.010;
  static const cornerFade = 0.12;

  static double scaleOf(double t) {
    return 1.0 + scaleGain * t.clamp(-1.0, 1.0);
  }

  static double alphaOf(double t) {
    final s = scaleOf(t);
    if ((s - 1.0).abs() < 1e-9) {
      return 0;
    }
    return 1.0 - 1.0 / s;
  }

  static LipPlumpFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    double t = 0,
    double? tUpper,
    double? tLower,
    bool computeMetrics = true,
    LipPlumpFieldRuntime? runtime,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('lip_plump_field_invalid_size: ${width}x$height');
    }

    final signedUpper = (tUpper ?? t).clamp(-1.0, 1.0);
    final signedLower = (tLower ?? t).clamp(-1.0, 1.0);

    if (runtime != null && runtime.matches(face, width, height)) {
      _scaleActive(
        field: runtime.field!,
        unitUpper: runtime.unitUpper!,
        unitLower: runtime.unitLower!,
        active: runtime.active!,
        alphaUpper: alphaOf(signedUpper),
        alphaLower: alphaOf(signedLower),
      );
      final metrics = computeMetrics
          ? LipPlumpFieldMetrics.compute(
              field: runtime.field!,
              masks: runtime.masks!,
              px: LipPlumpMasks.landmarkPixels(face, imageSize),
              faceWidth: runtime.faceWidth,
            )
          : LipPlumpFieldMetrics.skipped;
      return LipPlumpFieldBuild(
        field: runtime.field!,
        masks: runtime.masks!,
        metrics: metrics,
      );
    }

    final px = LipPlumpMasks.landmarkPixels(face, imageSize);
    final faceWidth = LipPlumpMasks.faceWidthOf(px);
    final masks = LipPlumpMasks.build(
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
    _scaleActive(
      field: field,
      unitUpper: packed.unitUpper,
      unitLower: packed.unitLower,
      active: packed.active,
      alphaUpper: alphaOf(signedUpper),
      alphaLower: alphaOf(signedLower),
    );

    if (runtime != null) {
      runtime
        ..face = face
        ..width = width
        ..height = height
        ..faceWidth = faceWidth
        ..unitUpper = packed.unitUpper
        ..unitLower = packed.unitLower
        ..active = packed.active
        ..field = field
        ..masks = masks;
    }

    final metrics = computeMetrics
        ? LipPlumpFieldMetrics.compute(
            field: field,
            masks: masks,
            px: px,
            faceWidth: faceWidth,
          )
        : LipPlumpFieldMetrics.skipped;
    return LipPlumpFieldBuild(
      field: field,
      masks: masks,
      metrics: metrics,
    );
  }

  static ({
    Float32List unitUpper,
    Float32List unitLower,
    List<int> active,
  }) _packUnits({
    required int width,
    required int height,
    required LipPlumpMasks masks,
    required List<Offset?> px,
    required double faceWidth,
  }) {
    final falloff = math.max(6.0, falloffFaceWidth * faceWidth);
    final guard = math.max(5.0, guardFalloffFaceWidth * faceWidth);
    final sigma = math.max(1.0, boundarySmoothFaceWidth * faceWidth);
    final blend = math.max(2.0, bandBlendFaceWidth * faceWidth);
    final left = _point(px, cornerLeft) ?? Offset(width * 0.35, height * 0.62);
    final right = _point(px, cornerRight) ?? Offset(width * 0.65, height * 0.62);
    final innerUp = _point(px, innerUpper) ?? left;
    final innerDn = _point(px, innerLower) ?? right;
    final slitY = 0.5 * (innerUp.dy + innerDn.dy);
    final axisDx = right.dx - left.dx;
    final axisDy = right.dy - left.dy;
    final axisLen = math.sqrt(axisDx * axisDx + axisDy * axisDy);
    final ramp = BoundaryFeather.insideActive(
      mask: masks.lips,
      width: width,
      height: height,
      falloffPx: falloff,
      sigmaPx: sigma,
    );
    final distNose = EuclideanDistanceTransform.toNonZeroOf(
      masks.nose,
      width,
      height,
    );
    final distChin = EuclideanDistanceTransform.toNonZeroOf(
      masks.chin,
      width,
      height,
    );
    final distEyes = EuclideanDistanceTransform.toNonZeroOf(
      masks.eyes,
      width,
      height,
    );
    final distBrows = EuclideanDistanceTransform.toNonZeroOf(
      masks.brows,
      width,
      height,
    );

    final active = <int>[];
    final upper = <double>[];
    final lower = <double>[];
    for (var i = 0; i < width * height; i++) {
      final r = ramp[i];
      if (r <= 1e-6) {
        continue;
      }
      final guardW = _smoothstep(distNose[i] / guard) *
          _smoothstep(distChin[i] / guard) *
          _smoothstep(distEyes[i] / guard) *
          _smoothstep(distBrows[i] / guard);
      if (guardW <= 1e-6) {
        continue;
      }
      final x = (i % width) + 0.5;
      final y = (i ~/ width) + 0.5;
      final signed = y - slitY;
      final along = _alongAxis(x, y, left, axisDx, axisDy, axisLen);
      final corner = _smoothstep((along - cornerFade) / cornerFade) *
          _smoothstep((1.0 - cornerFade - along) / cornerFade);
      if (corner <= 1e-6) {
        continue;
      }
      final w = r * guardW * corner;
      if (w <= 1e-6) {
        continue;
      }
      final upperFrac = _smoothstep(-signed / blend);
      final lowerFrac = _smoothstep(signed / blend);
      final wu = w * upperFrac * signed;
      final wl = w * lowerFrac * signed;
      if (wu.abs() <= 1e-6 && wl.abs() <= 1e-6) {
        continue;
      }
      active.add(i);
      upper.add(wu);
      lower.add(wl);
    }
    return (
      unitUpper: Float32List.fromList(upper),
      unitLower: Float32List.fromList(lower),
      active: active,
    );
  }

  static void _scaleActive({
    required DisplacementField field,
    required Float32List unitUpper,
    required Float32List unitLower,
    required List<int> active,
    required double alphaUpper,
    required double alphaLower,
  }) {
    for (var k = 0; k < active.length; k++) {
      final i = active[k];
      field.dx[i] = 0;
      field.dy[i] =
          alphaUpper * unitUpper[k] + alphaLower * unitLower[k];
    }
  }

  static Offset? _point(List<Offset?> px, int id) {
    if (id < 0 || id >= px.length) {
      return null;
    }
    return px[id];
  }

  static double _alongAxis(
    double x,
    double y,
    Offset a,
    double dx,
    double dy,
    double len,
  ) {
    if (len < 1e-6) {
      return 0.5;
    }
    return ((x - a.dx) * dx + (y - a.dy) * dy) / (len * len);
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
