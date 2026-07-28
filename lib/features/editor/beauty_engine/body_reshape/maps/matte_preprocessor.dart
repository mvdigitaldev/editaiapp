import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../models/person_matte.dart';
import 'protection_maps.dart';
import 'signed_distance_field.dart';

/// Resultado do pré-processamento do matte para o Warp Engine.
class ProcessedPersonMatte {
  final PersonMatte matte;
  final SignedDistanceField sdf;
  final Uint8List contour;
  final Rect boundingRegion;
  final ProtectionMaps protection;

  const ProcessedPersonMatte({
    required this.matte,
    required this.sdf,
    required this.contour,
    required this.boundingRegion,
    required this.protection,
  });
}

/// Deriva SDF, contorno, bounds e mapas de proteção a partir do matte.
class MattePreprocessor {
  const MattePreprocessor({
    this.insideThreshold = 0.42,
    this.defaultTransitionFraction = 0.035,
    this.minTransitionPx = 2,
    this.maxTransitionPx = 28,
  });

  /// Alfa mínimo para considerar pixel interior.
  final double insideThreshold;

  /// Fração da menor dimensão usada como banda de transição.
  final double defaultTransitionFraction;

  final double minTransitionPx;
  final double maxTransitionPx;

  ProcessedPersonMatte process(
    PersonMatte matte, {
    Size? imageSize,
    double? transitionPx,
  }) {
    if (matte.isEmpty) {
      return _empty(matte);
    }

    final width = matte.width;
    final height = matte.height;
    final binary = Uint8List(width * height);
    var minX = width;
    var minY = height;
    var maxX = -1;
    var maxY = -1;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final idx = y * width + x;
        final inside = matte.alpha[idx] / 255.0 >= insideThreshold;
        binary[idx] = inside ? 1 : 0;
        if (!inside) {
          continue;
        }
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }

    final hasPerson = maxX >= 0;
    final bounds = hasPerson
        ? Rect.fromLTRB(
            minX / math.max(width - 1, 1),
            minY / math.max(height - 1, 1),
            maxX / math.max(width - 1, 1),
            maxY / math.max(height - 1, 1),
          )
        : Rect.zero;

    final sdf = _buildSignedDistance(binary, width, height);
    final contour = _buildContour(binary, width, height);
    final resolvedTransition = _resolveTransitionPx(
      imageSize: imageSize,
      matteWidth: width,
      matteHeight: height,
      overridePx: transitionPx,
    );

    final protection = _buildProtectionMaps(
      matte: matte.copyWith(boundingRegion: bounds),
      sdf: sdf,
      contour: contour,
      boundingRegion: bounds,
      transitionPx: resolvedTransition,
    );

    return ProcessedPersonMatte(
      matte: matte.copyWith(boundingRegion: bounds),
      sdf: sdf,
      contour: contour,
      boundingRegion: bounds,
      protection: protection,
    );
  }

  /// Atalho: só os mapas de proteção usados pelo WarpFieldBuilder.
  ProtectionMaps buildProtectionMaps(
    PersonMatte matte, {
    Size? imageSize,
    double? transitionPx,
  }) {
    return process(
      matte,
      imageSize: imageSize,
      transitionPx: transitionPx,
    ).protection;
  }

  double _resolveTransitionPx({
    required Size? imageSize,
    required int matteWidth,
    required int matteHeight,
    required double? overridePx,
  }) {
    final matteMin = math.min(matteWidth, matteHeight).toDouble();
    final cap = math.max(1.0, matteMin * 0.25);

    if (overridePx != null) {
      return overridePx.clamp(1.0, math.min(maxTransitionPx, cap));
    }

    final reference = imageSize == null
        ? matteMin
        : math.min(imageSize.width, imageSize.height);
    // Banda na resolução da imagem, depois escalada para o matte.
    final imageTransition = (reference * defaultTransitionFraction)
        .clamp(minTransitionPx, maxTransitionPx);
    if (imageSize == null) {
      return imageTransition.clamp(1.0, math.min(maxTransitionPx, cap));
    }

    final scale = matteWidth / math.max(imageSize.width, 1.0);
    return (imageTransition * scale).clamp(1.0, math.min(maxTransitionPx, cap));
  }

  ProtectionMaps _buildProtectionMaps({
    required PersonMatte matte,
    required SignedDistanceField sdf,
    required Uint8List contour,
    required Rect boundingRegion,
    required double transitionPx,
  }) {
    final count = matte.width * matte.height;
    final warpWeight = Float32List(count);
    final transitionBand = Float32List(count);
    final confidence = matte.confidence.clamp(0.0, 1.0);

    for (var i = 0; i < count; i++) {
      final distance = sdf.distances[i];
      if (distance > 0) {
        // Exterior: peso identicamente zero (sem anel de fundo).
        warpWeight[i] = 0;
        transitionBand[i] = 0;
        continue;
      }

      final depthInside = -distance;
      if (depthInside >= transitionPx) {
        warpWeight[i] = confidence;
        transitionBand[i] = 0;
        continue;
      }

      final t = (depthInside / math.max(transitionPx, 1e-6)).clamp(0.0, 1.0);
      final edge = _smoothstep(t);
      // Borda interna suave; nunca estende para fora do matte.
      warpWeight[i] = confidence * edge;
      transitionBand[i] = 1.0 - edge;
    }

    return ProtectionMaps(
      warpWeight: warpWeight,
      transitionBand: transitionBand,
      sdf: sdf,
      contour: contour,
      boundingRegion: boundingRegion,
      confidence: confidence,
      width: matte.width,
      height: matte.height,
      transitionPx: transitionPx,
    );
  }

  SignedDistanceField _buildSignedDistance(
    Uint8List binary,
    int width,
    int height,
  ) {
    // Distância ao foreground (pessoa) e ao background (fora).
    final toPerson = _chamferDistance(binary, width, height, seedValue: 1);
    final toBackground = _chamferDistance(binary, width, height, seedValue: 0);
    final signed = Float32List(width * height);
    for (var i = 0; i < signed.length; i++) {
      if (binary[i] == 1) {
        signed[i] = -toBackground[i];
      } else {
        signed[i] = toPerson[i];
      }
    }
    return SignedDistanceField(
      distances: signed,
      width: width,
      height: height,
    );
  }

  /// Chamfer 3-4 aproximado; [seedValue] define pixels com distância 0.
  Float32List _chamferDistance(
    Uint8List binary,
    int width,
    int height, {
    required int seedValue,
  }) {
    const large = 1e6;
    final dist = Float32List(width * height);
    for (var i = 0; i < dist.length; i++) {
      dist[i] = binary[i] == seedValue ? 0.0 : large;
    }

    // Forward pass.
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final idx = y * width + x;
        var best = dist[idx];
        if (x > 0) {
          best = math.min(best, dist[idx - 1] + 3);
        }
        if (y > 0) {
          best = math.min(best, dist[idx - width] + 3);
        }
        if (x > 0 && y > 0) {
          best = math.min(best, dist[idx - width - 1] + 4);
        }
        if (x + 1 < width && y > 0) {
          best = math.min(best, dist[idx - width + 1] + 4);
        }
        dist[idx] = best;
      }
    }

    // Backward pass.
    for (var y = height - 1; y >= 0; y--) {
      for (var x = width - 1; x >= 0; x--) {
        final idx = y * width + x;
        var best = dist[idx];
        if (x + 1 < width) {
          best = math.min(best, dist[idx + 1] + 3);
        }
        if (y + 1 < height) {
          best = math.min(best, dist[idx + width] + 3);
        }
        if (x + 1 < width && y + 1 < height) {
          best = math.min(best, dist[idx + width + 1] + 4);
        }
        if (x > 0 && y + 1 < height) {
          best = math.min(best, dist[idx + width - 1] + 4);
        }
        dist[idx] = best;
      }
    }

    // Converte pesos 3-4 para pixels aproximados.
    for (var i = 0; i < dist.length; i++) {
      dist[i] = dist[i] >= large * 0.5 ? large : dist[i] / 3.0;
    }
    return dist;
  }

  Uint8List _buildContour(Uint8List binary, int width, int height) {
    final contour = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final idx = y * width + x;
        if (binary[idx] == 0) {
          continue;
        }
        final edge = x == 0 ||
            y == 0 ||
            x == width - 1 ||
            y == height - 1 ||
            binary[idx - 1] == 0 ||
            binary[idx + 1] == 0 ||
            binary[idx - width] == 0 ||
            binary[idx + width] == 0;
        if (edge) {
          contour[idx] = 255;
        }
      }
    }
    return contour;
  }

  ProcessedPersonMatte _empty(PersonMatte matte) {
    final emptySdf = SignedDistanceField(
      distances: Float32List(0),
      width: 0,
      height: 0,
    );
    final emptyProtection = ProtectionMaps(
      warpWeight: Float32List(0),
      transitionBand: Float32List(0),
      sdf: emptySdf,
      contour: Uint8List(0),
      boundingRegion: Rect.zero,
      confidence: matte.confidence,
      width: 0,
      height: 0,
      transitionPx: 0,
    );
    return ProcessedPersonMatte(
      matte: matte,
      sdf: emptySdf,
      contour: Uint8List(0),
      boundingRegion: Rect.zero,
      protection: emptyProtection,
    );
  }

  static double _smoothstep(double t) => t * t * (3 - 2 * t);
}
