import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_mesh_result.dart';
import '../boundary_feather.dart';
import '../displacement_field.dart';
import '../distance_transform.dart';
import 'lip_smile_masks.dart';
import 'lip_smile_metrics.dart';

class LipSmileFieldBuild {
  const LipSmileFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
    required this.center,
  });

  final DisplacementField field;
  final LipSmileMasks masks;
  final LipSmileFieldMetrics metrics;
  final Offset? center;
}

/// Cache do vector unitário (independente de t). O slider só escala dx/dy.
class LipSmileFieldRuntime {
  FaceMeshResult? face;
  int width = 0;
  int height = 0;
  double faceWidth = 1;
  Offset? center;
  Float32List? unitDx;
  Float32List? unitDy;
  List<int>? active;
  DisplacementField? field;
  LipSmileMasks? masks;

  bool matches(FaceMeshResult face, int width, int height) {
    return identical(this.face, face) &&
        this.width == width &&
        this.height == height &&
        unitDx != null &&
        unitDy != null &&
        active != null &&
        field != null &&
        masks != null;
  }
}

/// Levanta ou baixa os cantos da boca. Δy nos cantos + Δx curto para fora.
///
/// Direita do slider: sorriso. Esquerda: carranca. Não importa outros Fields.
abstract final class LipSmileField {
  LipSmileField._();

  static const cornerA = 61;
  static const cornerB = 291;
  static const amplitudeYFaceWidth = 0.030;
  static const amplitudeXFaceWidth = 0.010;
  static const falloffFaceWidth = 0.055;
  static const hullPadFaceWidth = 0.040;
  static const guardFalloffFaceWidth = 0.045;
  static const boundarySmoothFaceWidth = 0.022;

  static LipSmileFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    double t = 0,
    bool computeMetrics = true,
    LipSmileFieldRuntime? runtime,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('lip_smile_field_invalid_size: ${width}x$height');
    }

    final intensity = t.clamp(-1.0, 1.0);

    if (runtime != null && runtime.matches(face, width, height)) {
      _scaleActive(
        field: runtime.field!,
        unitDx: runtime.unitDx!,
        unitDy: runtime.unitDy!,
        active: runtime.active!,
        dx: intensity * amplitudeXFaceWidth * runtime.faceWidth,
        dy: -intensity * amplitudeYFaceWidth * runtime.faceWidth,
      );
      final metrics = computeMetrics
          ? LipSmileFieldMetrics.compute(
              field: runtime.field!,
              masks: runtime.masks!,
              px: LipSmileMasks.landmarkPixels(face, imageSize),
              center: runtime.center ?? Offset.zero,
              faceWidth: runtime.faceWidth,
            )
          : LipSmileFieldMetrics.skipped;
      return LipSmileFieldBuild(
        field: runtime.field!,
        masks: runtime.masks!,
        metrics: metrics,
        center: runtime.center,
      );
    }

    final px = LipSmileMasks.landmarkPixels(face, imageSize);
    final faceWidth = LipSmileMasks.faceWidthOf(px);
    final center = LipSmileMasks.centroid(px) ??
        Offset(width * 0.5, height * 0.62);
    final masks = LipSmileMasks.build(
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
      unitDx: packed.unitDx,
      unitDy: packed.unitDy,
      active: packed.active,
      dx: intensity * amplitudeXFaceWidth * faceWidth,
      dy: -intensity * amplitudeYFaceWidth * faceWidth,
    );

    if (runtime != null) {
      runtime
        ..face = face
        ..width = width
        ..height = height
        ..faceWidth = faceWidth
        ..center = center
        ..unitDx = packed.unitDx
        ..unitDy = packed.unitDy
        ..active = packed.active
        ..field = field
        ..masks = masks;
    }

    final metrics = computeMetrics
        ? LipSmileFieldMetrics.compute(
            field: field,
            masks: masks,
            px: px,
            center: center,
            faceWidth: faceWidth,
          )
        : LipSmileFieldMetrics.skipped;
    return LipSmileFieldBuild(
      field: field,
      masks: masks,
      metrics: metrics,
      center: center,
    );
  }

  static ({
    Float32List unitDx,
    Float32List unitDy,
    List<int> active,
  }) _packUnits({
    required int width,
    required int height,
    required LipSmileMasks masks,
    required List<Offset?> px,
    required double faceWidth,
  }) {
    final a = _point(px, cornerA);
    final b = _point(px, cornerB);
    final left = a == null
        ? b
        : b == null
            ? a
            : a.dx <= b.dx
                ? a
                : b;
    final right = a == null
        ? b
        : b == null
            ? a
            : a.dx > b.dx
                ? a
                : b;
    final axisStart = left ?? Offset(width * 0.35, height * 0.62);
    final axisEnd = right ?? Offset(width * 0.65, height * 0.62);
    final axisDx = axisEnd.dx - axisStart.dx;
    final axisDy = axisEnd.dy - axisStart.dy;
    final axisLen = math.sqrt(axisDx * axisDx + axisDy * axisDy);

    final falloff = math.max(6.0, falloffFaceWidth * faceWidth);
    final guard = math.max(5.0, guardFalloffFaceWidth * faceWidth);
    final sigma = math.max(1.0, boundarySmoothFaceWidth * faceWidth);
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
    final dx = <double>[];
    final dy = <double>[];
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
      final u = _alongAxis(x, y, axisStart, axisDx, axisDy, axisLen)
          .clamp(0.0, 1.0);
      final mid = 2.0 * u - 1.0;
      final profile = mid * mid;
      if (profile <= 1e-6) {
        continue;
      }
      final w = r * guardW * profile;
      if (w <= 1e-6) {
        continue;
      }
      active.add(i);
      dx.add(w * mid);
      dy.add(w);
    }
    return (
      unitDx: Float32List.fromList(dx),
      unitDy: Float32List.fromList(dy),
      active: active,
    );
  }

  static void _scaleActive({
    required DisplacementField field,
    required Float32List unitDx,
    required Float32List unitDy,
    required List<int> active,
    required double dx,
    required double dy,
  }) {
    for (var k = 0; k < active.length; k++) {
      final i = active[k];
      field.dx[i] = dx * unitDx[k];
      field.dy[i] = dy * unitDy[k];
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
