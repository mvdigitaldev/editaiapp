import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/face_mesh_result.dart';
import '../displacement_field.dart';
import '../region_catalog.dart';
import 'face_slim_masks.dart';
import 'face_slim_metrics.dart';

class FaceSlimFieldBuild {
  const FaceSlimFieldBuild({
    required this.field,
    required this.masks,
    required this.metrics,
  });

  final DisplacementField field;
  final FaceSlimMasks masks;
  final FaceSlimFieldMetrics metrics;
}

/// Constrói o campo Face Slim (só Δx). Sem RGBA, sem render, sem produto.
///
/// Handles / hull são constantes deste módulo: ajustar aqui na Sprint A
/// não muda a arquitectura nem o renderer.
abstract final class FaceSlimField {
  FaceSlimField._();

  /// Primários vigentes. 123/352 foram os candidatos iniciais; 352 cai no
  /// disco da orelha em p01, por isso o direito passou a 411 (bochecha R).
  static const primaryLeft = 123;
  static const primaryRight = 411;
  static const primaryHandles = {primaryLeft, primaryRight};

  /// Resto das bochechas — sem domínio Jaw/Chin.
  static const leftCheekLandmarks = {
    116,
    123,
    147,
    187,
    207,
    206,
    203,
    142,
    126,
    217,
  };
  static const rightCheekLandmarks = {
    345,
    352,
    411,
    425,
    427,
    436,
    426,
    423,
    266,
    371,
  };

  static const secondaryHandles = {
    116,
    147,
    187,
    207,
    206,
    203,
    142,
    126,
    217,
    345,
    352,
    425,
    427,
    436,
    426,
    423,
    266,
    371,
  };

  static Set<int> get leftHullLandmarks => leftCheekLandmarks;
  static Set<int> get rightHullLandmarks => rightCheekLandmarks;

  /// Domínio primário Jaw — hard-zero no Field Face Slim.
  static const jawDomainPrimary = {58, 288, 132, 361};

  /// Secundários Jaw — hard-zero no Field Face Slim.
  static const jawDomainSecondary = {172, 136, 365, 397};

  static Set<int> get jawDomainLandmarks => {
        ...jawDomainPrimary,
        ...jawDomainSecondary,
      };

  /// Domínio Chin — hard-zero no Field Face Slim.
  static const chinDomainLandmarks = {152, 148, 176, 149, 377, 400, 378};

  static const gonionLeft = 58;
  static const gonionRight = 288;
  static const chinTip = 152;

  static const amplitudeFaceWidth = 0.04;
  static const hullPadFaceWidth = 0.05;
  static const lorentzSigmaXFaceWidth = 0.11;
  static const lorentzSigmaYFaceWidth = 0.09;
  static const midlineDeadZoneFaceWidth = 0.07;
  static const midlineRampFaceWidth = 0.06;

  static FaceSlimFieldBuild build({
    required FaceMeshResult face,
    required Size imageSize,
    required double t,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('face_slim_field_invalid_size: ${width}x$height');
    }

    final px = FaceSlimMasks.landmarkPixels(face, imageSize);
    final masks = FaceSlimMasks.build(
      face: face,
      imageSize: imageSize,
      leftHullLandmarks: leftHullLandmarks,
      rightHullLandmarks: rightHullLandmarks,
      jawDomainLandmarks: jawDomainLandmarks,
      chinDomainLandmarks: chinDomainLandmarks,
      hullPadFaceWidth: hullPadFaceWidth,
    );
    final faceWidth = _faceWidth(px);
    final intensity = t.clamp(0.0, 1.0);
    final amplitude = intensity * amplitudeFaceWidth * faceWidth;

    final field = DisplacementField.zeros(width: width, height: height);
    if (intensity > 0 && amplitude > 0 && masks.count(masks.slimActive) > 0) {
      _applyNarrowing(
        field: field,
        masks: masks,
        px: px,
        faceWidth: faceWidth,
        amplitude: amplitude,
      );
    }

    final metrics = FaceSlimFieldMetrics.compute(
      field: field,
      masks: masks,
      px: px,
      faceWidth: faceWidth,
      slimAmplitude: amplitude,
      primaryLeft: primaryLeft,
      primaryRight: primaryRight,
      gonionLeft: gonionLeft,
      gonionRight: gonionRight,
      chinTip: chinTip,
    );
    return FaceSlimFieldBuild(field: field, masks: masks, metrics: metrics);
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

  static double _midlineX(List<Offset?> px, double faceWidth) {
    final oval = <Offset>[];
    for (final id in V2RegionCatalog.faceOval) {
      final p = id >= 0 && id < px.length ? px[id] : null;
      if (p != null) {
        oval.add(p);
      }
    }
    if (oval.isEmpty) {
      return faceWidth * 0.5;
    }
    var minX = oval.first.dx;
    var maxX = oval.first.dx;
    for (final p in oval) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
    }
    return (minX + maxX) * 0.5;
  }

  /// Kernel próprio do Face Slim: lóbulos Lorentzianos anisotrópicos
  /// combinados por união probabilística, polaridade pela midline, rampa
  /// lateral (zona morta no centro). Não é o gaussiano+chamfer do Chin/Jaw.
  static void _applyNarrowing({
    required DisplacementField field,
    required FaceSlimMasks masks,
    required List<Offset?> px,
    required double faceWidth,
    required double amplitude,
  }) {
    final handles = _handles(px);
    if (handles.isEmpty) {
      return;
    }
    final midX = _midlineX(px, faceWidth);
    final sigmaX = math.max(10.0, lorentzSigmaXFaceWidth * faceWidth);
    final sigmaY = math.max(8.0, lorentzSigmaYFaceWidth * faceWidth);
    final dead = math.max(6.0, midlineDeadZoneFaceWidth * faceWidth);
    final ramp = math.max(6.0, midlineRampFaceWidth * faceWidth);
    final edgeLayers = math.max(8, (0.045 * faceWidth).round());
    final edgeFade = _onionFade(
      masks.slimActive,
      field.width,
      field.height,
      edgeLayers,
    );

    for (var i = 0; i < field.pixelCount; i++) {
      if (masks.slimActive[i] == 0) {
        continue;
      }
      final x = (i % field.width) + 0.5;
      final y = (i ~/ field.width) + 0.5;
      final toward = midX - x;
      final lateral = toward.abs();
      if (lateral < dead) {
        continue;
      }
      final sign = toward > 0 ? 1.0 : -1.0;
      final lateralGate = _smoothstep(dead, dead + ramp, lateral);

      var survival = 1.0;
      for (final h in handles) {
        final handleSide = h.p.dx - midX;
        final pixelSide = x - midX;
        if (handleSide * pixelSide <= 0) {
          continue;
        }
        final lx = (x - h.p.dx) / sigmaX;
        final ly = (y - h.p.dy) / sigmaY;
        final lorentz = h.weight / ((1 + lx * lx) * (1 + ly * ly));
        final w = lorentz.clamp(0.0, 0.999);
        survival *= 1.0 - w;
      }
      final weight = (1.0 - survival) * lateralGate * edgeFade[i];
      if (weight <= 1e-6) {
        continue;
      }
      field.dx[i] = sign * amplitude * weight;
      field.dy[i] = 0;
    }
  }

  /// Rampa de fronteira por camadas de erosão (não é o chamfer do Chin/Jaw).
  static List<double> _onionFade(
    Uint8List active,
    int width,
    int height,
    int layers,
  ) {
    final fade = List<double>.filled(active.length, 0);
    final remaining = Uint8List.fromList(active);
    var alive = 0;
    for (final v in remaining) {
      if (v != 0) {
        alive++;
      }
    }
    var layer = 0;
    while (alive > 0 && layer < layers) {
      layer++;
      final border = <int>[];
      for (var i = 0; i < remaining.length; i++) {
        if (remaining[i] == 0) {
          continue;
        }
        final x = i % width;
        final y = i ~/ width;
        final exposed = (x > 0 && remaining[i - 1] == 0) ||
            (x + 1 < width && remaining[i + 1] == 0) ||
            (y > 0 && remaining[i - width] == 0) ||
            (y + 1 < height && remaining[i + width] == 0);
        if (exposed) {
          border.add(i);
        }
      }
      if (border.isEmpty) {
        for (var i = 0; i < remaining.length; i++) {
          if (remaining[i] != 0) {
            fade[i] = 1;
            remaining[i] = 0;
            alive--;
          }
        }
        break;
      }
      final t = layer / layers;
      for (final i in border) {
        fade[i] = t;
        remaining[i] = 0;
        alive--;
      }
    }
    for (var i = 0; i < remaining.length; i++) {
      if (remaining[i] != 0) {
        fade[i] = 1;
      }
    }
    return fade;
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
    add(secondaryHandles, 0.72);
    return out;
  }

  static double _smoothstep(double edge0, double edge1, double x) {
    if (x <= edge0) {
      return 0;
    }
    if (x >= edge1) {
      return 1;
    }
    final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }
}
