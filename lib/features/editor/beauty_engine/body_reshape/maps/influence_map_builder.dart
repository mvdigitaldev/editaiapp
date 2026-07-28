import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../mesh/adaptive_body_mesh.dart';
import '../models/body_adjustment.dart';
import '../models/body_frame_assets.dart';
import '../models/body_joint.dart';
import '../models/body_region.dart';
import '../models/body_reshape_request.dart';
import 'influence_map.dart';
import 'protection_maps.dart';
import 'region_distance_field.dart';

/// Combina SDF/proteção, distância ao eixo, ângulo, curvatura, malha e confiança.
class InfluenceMapBuilder {
  const InfluenceMapBuilder({
    this.distanceFieldBuilder = const RegionDistanceFieldBuilder(),
  });

  final RegionDistanceFieldBuilder distanceFieldBuilder;

  InfluenceMap build({
    required Size imageSize,
    required Set<BodyRegion> regions,
    BodyFrameAssets? assets,
    Map<BodyJoint, Offset>? landmarkPx,
    AdaptiveBodyMesh? mesh,
    ProtectionMaps? protection,
    BodyAdjustment? adjustment,
    double confidence = 1,
    WarpQualityProfile qualityProfile = WarpQualityProfile.preview,
    int? mapWidth,
    int? mapHeight,
  }) {
    final resolvedConfidence = confidence.clamp(0.0, 1.0);
    final size = _resolveMapSize(
      imageSize: imageSize,
      qualityProfile: qualityProfile,
      mapWidth: mapWidth,
      mapHeight: mapHeight,
      protection: protection,
    );

    if (size.width <= 0 || size.height <= 0 || regions.isEmpty) {
      return InfluenceMap(
        values: Float32List(0),
        width: 0,
        height: 0,
        imageSize: imageSize,
        regions: regions,
        confidence: resolvedConfidence,
        maxValue: 0,
      );
    }

    final width = size.width;
    final height = size.height;
    final rdf = distanceFieldBuilder.build(
      imageSize: imageSize,
      regions: regions,
      width: width,
      height: height,
      assets: assets,
      landmarkPx: landmarkPx,
    );

    final direction = adjustment?.direction;
    final influenceLimit = (adjustment?.influence ?? 1.0).clamp(0.0, 1.0);
    final minConfidence = adjustment?.minimumConfidence ?? 0.0;
    final confidenceGate = resolvedConfidence < minConfidence
        ? (resolvedConfidence / math.max(minConfidence, 1e-6)).clamp(0.0, 1.0)
        : 1.0;

    final meshDensity = mesh == null
        ? null
        : _buildMeshDensityGrid(mesh, width, height, regions);

    final values = Float32List(width * height);
    var maxValue = 0.0;

    for (var y = 0; y < height; y++) {
      final ny = height == 1 ? 0.5 : y / (height - 1);
      for (var x = 0; x < width; x++) {
        final nx = width == 1 ? 0.5 : x / (width - 1);
        final idx = y * width + x;

        // 1) Proteção / SDF — fora do matte → 0 (não expande ao fundo).
        final protectionWeight = protection == null || protection.isEmpty
            ? 0.65
            : protection.sampleWarpWeight(nx, ny);
        if (protectionWeight <= 1e-4) {
          values[idx] = 0;
          continue;
        }

        // 2) Distância ao eixo regional.
        final distanceWeight = rdf.isEmpty ? 0.35 : rdf.falloff[idx];
        if (distanceWeight <= 1e-4) {
          values[idx] = 0;
          continue;
        }

        // 3) Ângulo / direção do ajuste.
        final angleWeight = _angleWeight(
          direction: direction,
          axisT: rdf.isEmpty ? 0.5 : rdf.axisT[idx],
          sideSign: rdf.isEmpty ? 0 : rdf.sideSign[idx],
          distancePx: rdf.isEmpty ? 0 : rdf.distancePx[idx],
          halfWidthHint: _halfWidthHint(rdf, imageSize),
        );

        // 4) Curvatura proxy via proximidade do contorno (SDF).
        final curvatureWeight = _curvatureWeight(protection, nx, ny);

        // 5) Densidade / peso da malha adaptativa.
        final meshWeight = meshDensity == null ? 1.0 : meshDensity[idx];

        final value = (protectionWeight *
                distanceWeight *
                angleWeight *
                curvatureWeight *
                meshWeight *
                influenceLimit *
                resolvedConfidence *
                confidenceGate)
            .clamp(0.0, 1.0);

        values[idx] = value;
        if (value > maxValue) {
          maxValue = value;
        }
      }
    }

    return InfluenceMap(
      values: values,
      width: width,
      height: height,
      imageSize: imageSize,
      regions: regions,
      confidence: resolvedConfidence,
      maxValue: maxValue,
    );
  }

  /// Atalho a partir de um [BodyAdjustment] completo.
  InfluenceMap buildForAdjustment({
    required Size imageSize,
    required BodyAdjustment adjustment,
    BodyFrameAssets? assets,
    AdaptiveBodyMesh? mesh,
    ProtectionMaps? protection,
    double confidence = 1,
    WarpQualityProfile qualityProfile = WarpQualityProfile.preview,
  }) {
    return build(
      imageSize: imageSize,
      regions: adjustment.regions,
      assets: assets,
      mesh: mesh,
      protection: protection,
      adjustment: adjustment,
      confidence: confidence,
      qualityProfile: qualityProfile,
    );
  }

  ({int width, int height}) _resolveMapSize({
    required Size imageSize,
    required WarpQualityProfile qualityProfile,
    required int? mapWidth,
    required int? mapHeight,
    required ProtectionMaps? protection,
  }) {
    if (mapWidth != null && mapHeight != null) {
      return (width: mapWidth, height: mapHeight);
    }
    if (protection != null && !protection.isEmpty) {
      final scale = qualityProfile.mapResolutionScale.clamp(0.35, 1.0);
      final w = math.max(8, (protection.width * scale).round());
      final h = math.max(8, (protection.height * scale).round());
      return (width: w, height: h);
    }

    final minDim = math.min(imageSize.width, imageSize.height);
    final base = switch (qualityProfile.quality) {
      WarpQuality.interactive => (minDim / 16).clamp(24, 48),
      WarpQuality.preview => (minDim / 12).clamp(32, 72),
      WarpQuality.export => (minDim / 8).clamp(48, 128),
    };
    final side = (base * qualityProfile.mapResolutionScale).round().clamp(16, 160);
    final aspect = imageSize.height / math.max(imageSize.width, 1);
    final width = side;
    final height = (side * aspect).round().clamp(16, 220);
    return (width: width, height: height);
  }

  double _halfWidthHint(RegionDistanceField rdf, Size imageSize) {
    if (rdf.segments.isEmpty) {
      return math.min(imageSize.width, imageSize.height) * 0.12;
    }
    var sum = 0.0;
    for (final segment in rdf.segments) {
      sum += segment.halfWidthPx;
    }
    return sum / rdf.segments.length;
  }

  double _angleWeight({
    required BodyAdjustmentDirection? direction,
    required double axisT,
    required double sideSign,
    required double distancePx,
    required double halfWidthHint,
  }) {
    if (direction == null) {
      return 1;
    }

    return switch (direction) {
      BodyAdjustmentDirection.inward ||
      BodyAdjustmentDirection.outward ||
      BodyAdjustmentDirection.horizontalExpand ||
      BodyAdjustmentDirection.horizontalContract =>
        () {
          // Prefer lateral distance from axis (não o miolo ósseo).
          final lateral = (distancePx / math.max(halfWidthHint, 1e-6))
              .clamp(0.0, 1.0);
          final lateralBell = math.sin(math.pi * lateral.clamp(0.05, 0.95));
          final along = 1.0 - ((axisT - 0.5).abs() * 0.35);
          return (0.35 + 0.65 * lateralBell) * along.clamp(0.4, 1.0);
        }(),
      BodyAdjustmentDirection.verticalStretch =>
        () {
          // Prefer pontos ao longo do eixo (não laterais extremos).
          final axial = 1.0 - (distancePx / math.max(halfWidthHint, 1e-6))
              .clamp(0.0, 1.0);
          return 0.4 + 0.6 * _smoothstep(axial);
        }(),
    };
  }

  double _curvatureWeight(ProtectionMaps? protection, double nx, double ny) {
    if (protection == null || protection.isEmpty) {
      return 1;
    }
    final sdf = protection.sdf.sampleNormalized(nx, ny);
    // Contorno (sdf≈0) recebe leve reforço; interior profundo permanece ~1.
    final nearEdge = math.exp(-(sdf.abs() / math.max(protection.transitionPx, 1)));
    return (0.85 + 0.15 * nearEdge).clamp(0.85, 1.0);
  }

  Float32List _buildMeshDensityGrid(
    AdaptiveBodyMesh mesh,
    int width,
    int height,
    Set<BodyRegion> regions,
  ) {
    final counts = List<int>.filled(width * height, 0);
    final invW = mesh.imageSize.width > 0 ? 1.0 / mesh.imageSize.width : 0.0;
    final invH = mesh.imageSize.height > 0 ? 1.0 / mesh.imageSize.height : 0.0;

    for (var i = 0; i < mesh.vertexCount; i++) {
      final region = mesh.regionAtVertex(i);
      if (!regions.contains(region) && !_softRegionMatch(regions, region)) {
        continue;
      }
      final nx = (mesh.vertices[i * 2] * invW).clamp(0.0, 1.0);
      final ny = (mesh.vertices[i * 2 + 1] * invH).clamp(0.0, 1.0);
      final gx = (nx * (width - 1)).round().clamp(0, width - 1);
      final gy = (ny * (height - 1)).round().clamp(0, height - 1);
      counts[gy * width + gx]++;
    }

    var maxCount = 1;
    for (final c in counts) {
      if (c > maxCount) maxCount = c;
    }

    final density = Float32List(width * height);
    for (var i = 0; i < density.length; i++) {
      final n = counts[i] / maxCount;
      // Densidade maior reforça levemente a influência (região já refinada).
      density[i] = 0.85 + 0.15 * n;
    }
    return density;
  }

  bool _softRegionMatch(Set<BodyRegion> targets, BodyRegion candidate) {
    for (final target in targets) {
      if (target == candidate) return true;
      if (target == BodyRegion.torso &&
          (candidate == BodyRegion.waist ||
              candidate == BodyRegion.chest ||
              candidate == BodyRegion.hip)) {
        return true;
      }
      if (target == BodyRegion.waist &&
          (candidate == BodyRegion.torso || candidate == BodyRegion.hip)) {
        return true;
      }
    }
    return false;
  }

  double _smoothstep(double t) {
    final x = t.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }
}
