import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_mesh_result.dart';
import '../displacement_field.dart';
import '../region_catalog.dart';
import 'chin_masks.dart';
import 'chin_metrics.dart';

class ChinFieldBuild {
  const ChinFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
  });

  final DisplacementField field;
  final ChinMasks masks;
  final ChinFieldMetrics metrics;
}

/// Constrói o campo chin (só Δy). Sem RGBA, sem render, sem produto.
///
/// Handles / hull são constantes deste módulo: ajustar aqui na Sprint A
/// não muda a arquitectura nem o renderer.
abstract final class ChinField {
  ChinField._();

  /// Handle principal inicial (MediaPipe mento). Ajustável neste módulo.
  static const primaryHandles = {152};

  /// Handles secundários do mento — sem domínio primário Jaw.
  static const secondaryHandles = {148, 377, 176, 400};

  /// Hull activo inicial. Sem 58/288/132/361.
  static const hullLandmarks = {152, 148, 176, 149, 377, 400, 378};

  /// Domínio primário Jaw — hard-zero no Field Chin.
  static const jawDomainPrimary = {58, 288, 132, 361};

  /// Secundários Jaw — hard-zero no Field Chin.
  static const jawDomainSecondary = {172, 136, 365, 397};

  static Set<int> get jawDomainLandmarks => {
        ...jawDomainPrimary,
        ...jawDomainSecondary,
      };

  static const amplitudeFaceWidth = 0.04;
  static const falloffFaceWidth = 0.12;
  static const hullPadFaceWidth = 0.06;
  static const handleSigmaFaceWidth = 0.08;

  static ChinFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    required double t,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('chin_field_invalid_size: ${width}x$height');
    }

    final px = ChinMasks.landmarkPixels(face, imageSize);
    final masks = ChinMasks.build(
      face: face,
      imageSize: imageSize,
      hullLandmarks: hullLandmarks,
      jawDomainLandmarks: jawDomainLandmarks,
      hullPadFaceWidth: hullPadFaceWidth,
    );
    final faceWidth = _faceWidth(px);
    final intensity = t.clamp(0.0, 1.0);
    final amplitude = intensity * amplitudeFaceWidth * faceWidth;

    final field = DisplacementField.zeros(width: width, height: height);
    if (intensity > 0 && amplitude > 0 && masks.count(masks.chinActive) > 0) {
      _applyShortening(
        field: field,
        masks: masks,
        px: px,
        amplitude: amplitude,
        falloff: math.max(12.0, falloffFaceWidth * faceWidth),
        handleSigma: math.max(8.0, handleSigmaFaceWidth * faceWidth),
      );
    }

    final primary = primaryHandles.isEmpty ? 152 : primaryHandles.first;
    final metrics = ChinFieldMetrics.compute(
      field: field,
      masks: masks,
      px: px,
      faceWidth: faceWidth,
      chinAmplitude: amplitude,
      primaryHandle: primary,
      gonionLeft: V2RegionCatalog.gonionLeft,
      gonionRight: V2RegionCatalog.gonionRight,
    );
    return ChinFieldBuild(field: field, masks: masks, metrics: metrics);
  }

  static double _faceWidth(List<Offset?> px) {
    final oval = <Offset>[];
    for (final id in V2RegionCatalog.faceOval) {
      final p = id >= 0 && id < px.length ? px[id] : null;
      if (p != null) {
        oval.add(p);
      }
    }
    if (oval.isEmpty) {
      return 1.0;
    }
    var minX = oval.first.dx;
    var maxX = oval.first.dx;
    for (final p in oval) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
    }
    return math.max(maxX - minX, 1.0);
  }

  static void _applyShortening({
    required DisplacementField field,
    required ChinMasks masks,
    required List<Offset?> px,
    required double amplitude,
    required double falloff,
    required double handleSigma,
  }) {
    final dist = _distanceToInactive(masks.chinActive, field.width, field.height);
    final handles = _handles(px);
    if (handles.isEmpty) {
      return;
    }
    final twoS2 = 2 * handleSigma * handleSigma;
    for (var i = 0; i < field.pixelCount; i++) {
      if (masks.chinActive[i] == 0) {
        continue;
      }
      final x = (i % field.width) + 0.5;
      final y = (i ~/ field.width) + 0.5;
      final boundary = math.min(1.0, dist[i] / falloff);
      var handleW = 0.0;
      for (final h in handles) {
        final ddx = x - h.p.dx;
        final ddy = y - h.p.dy;
        final g = h.weight * math.exp(-(ddx * ddx + ddy * ddy) / twoS2);
        if (g > handleW) {
          handleW = g;
        }
      }
      final weight = boundary * handleW;
      if (weight <= 1e-6) {
        continue;
      }
      field.dx[i] = 0;
      field.dy[i] = -amplitude * weight;
    }
  }

  static List<({Offset p, double weight})> _handles(List<Offset?> px) {
    final out = <({Offset p, double weight})>[];
    void add(Set<int> ids, double w) {
      for (final id in ids) {
        final p = id < px.length ? px[id] : null;
        if (p != null) {
          out.add((p: p, weight: w));
        }
      }
    }

    add(primaryHandles, 1.0);
    add(secondaryHandles, 0.85);
    return out;
  }

  static Float32List _distanceToInactive(Uint8List active, int width, int height) {
    const inf = 1e8;
    final dist = Float32List(width * height);
    for (var i = 0; i < dist.length; i++) {
      dist[i] = active[i] == 0 ? 0 : inf;
    }
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = y * width + x;
        if (x > 0) {
          dist[i] = math.min(dist[i], dist[i - 1] + 1);
        }
        if (y > 0) {
          dist[i] = math.min(dist[i], dist[i - width] + 1);
        }
      }
    }
    for (var y = height - 1; y >= 0; y--) {
      for (var x = width - 1; x >= 0; x--) {
        final i = y * width + x;
        if (x + 1 < width) {
          dist[i] = math.min(dist[i], dist[i + 1] + 1);
        }
        if (y + 1 < height) {
          dist[i] = math.min(dist[i], dist[i + width] + 1);
        }
      }
    }
    return dist;
  }
}
