import 'dart:math' as math;
import 'dart:typed_data';

import '../../segment/face_parsing_class.dart';
import '../../segment/face_parsing_result.dart';
import '../../segment/parsing_mask_cache.dart';
import 'skin/guided_filter.dart';
import 'skin/skin_weight_map.dart';
import 'skin_mask_utils.dart';

/// Fábrica de máscaras derivadas do face parsing (Sprint 4).
class MaskFactory {
  MaskFactory({ParsingMaskCache? cache}) : _cache = cache ?? ParsingMaskCache();

  final ParsingMaskCache _cache;

  static const skinInclude = {
    FaceParsingClass.skin,
    FaceParsingClass.nose,
    FaceParsingClass.neck,
    FaceParsingClass.neckL,
  };

  static const hairInclude = {FaceParsingClass.hair, FaceParsingClass.hat};

  static const protectExclude = {
    FaceParsingClass.eyeG,
    FaceParsingClass.eyeL,
    FaceParsingClass.browG,
    FaceParsingClass.browL,
    FaceParsingClass.mouth,
    FaceParsingClass.lipUpper,
    FaceParsingClass.lipLower,
  };

  /// Intersection over Union entre duas máscaras binárias (0/255).
  static double iou(Uint8List a, Uint8List b, {int threshold = 128}) {
    if (a.length != b.length || a.isEmpty) return 0;
    var intersection = 0;
    var union = 0;
    for (var i = 0; i < a.length; i++) {
      final inA = a[i] >= threshold;
      final inB = b[i] >= threshold;
      if (inA && inB) intersection++;
      if (inA || inB) union++;
    }
    if (union == 0) return 1;
    return intersection / union;
  }

  Uint8List buildRegionMask({
    required FaceParsingResult parsing,
    required Set<FaceParsingClass> include,
    required int width,
    required int height,
    SkinTileMapping mapping = const SkinTileMapping(),
    int featherRadius = 0,
    bool useCache = true,
    FaceParsingClass cacheRegion = FaceParsingClass.skin,
  }) {
    final pixels = width * height;
    if (pixels <= 0 || parsing.isEmpty) {
      return Uint8List(math.max(pixels, 0));
    }

    final parsingHash = ParsingMaskCache.hashParsingBuffer(parsing.classes);
    final key = ParsingMaskCache.cacheKey(
      width: width,
      height: height,
      region: cacheRegion,
      parsingHash: parsingHash,
      tileOriginX: mapping.originX,
      tileOriginY: mapping.originY,
    );
    if (useCache) {
      final cached = _cache.get(key);
      if (cached != null && cached.length == pixels) {
        return cached;
      }
    }

    final resolved = mapping.resolve(width, height);
    final includeIndices = include.map((c) => c.index).toSet();
    final raw = Uint8List(pixels);

    for (var y = 0; y < height; y++) {
      final ny = resolved.normalizedY(y);
      for (var x = 0; x < width; x++) {
        final nx = resolved.normalizedX(x);
        if (includeIndices.contains(
          parsing.classAtNormalized(nx, ny).index,
        )) {
          raw[y * width + x] = 255;
        }
      }
    }

    Uint8List output;
    if (featherRadius > 0) {
      final feathered = GuidedFilter.boxMeanU8(
        raw,
        width: width,
        height: height,
        radius: featherRadius,
      );
      output = Uint8List(pixels);
      for (var i = 0; i < pixels; i++) {
        output[i] = (feathered[i] * 255).round().clamp(0, 255);
      }
    } else {
      output = raw;
    }

    if (useCache) {
      _cache.put(key, output);
    }
    return output;
  }

  SkinWeightMap buildSkin({
    required FaceParsingResult parsing,
    required SkinProcessingMask geometric,
    required int width,
    required int height,
    SkinTileMapping mapping = const SkinTileMapping(),
  }) {
    final pixels = width * height;
    final bounds = geometric.faceBounds;
    if (pixels <= 0 || bounds.isEmpty || parsing.isEmpty) {
      return SkinWeightMap(
        weights: Uint8List(math.max(pixels, 0)),
        width: width,
        height: height,
        fromSegmentation: parsing.source != FaceParsingSource.geometric,
        coverage: 0,
        parsingSource: parsing.source,
      );
    }

    final resolved = mapping.resolve(width, height);
    final faceEdgePx = math.max(
      bounds.width * resolved.fullWidth,
      bounds.height * resolved.fullHeight,
    );
    final featherRadius = (faceEdgePx * 0.012).round().clamp(1, 24);

    final raw = buildRegionMask(
      parsing: parsing,
      include: skinInclude,
      width: width,
      height: height,
      mapping: mapping,
      featherRadius: featherRadius,
      cacheRegion: FaceParsingClass.skin,
    );

    final excludeIndices = protectExclude.map((c) => c.index).toSet();
    final feathered = Uint8List.fromList(raw);
    for (var y = 0; y < height; y++) {
      final ny = resolved.normalizedY(y);
      for (var x = 0; x < width; x++) {
        final index = y * width + x;
        if (feathered[index] <= 0) continue;
        if (excludeIndices.contains(
          parsing.classAtNormalized(resolved.normalizedX(x), ny).index,
        )) {
          feathered[index] = 0;
        }
      }
    }

    final protectedRegions = geometric.protectedRegions
        .map((region) => region.inflate(0.008))
        .toList(growable: false);

    final weights = Uint8List(pixels);
    var covered = 0;
    for (var y = 0; y < height; y++) {
      final ny = resolved.normalizedY(y);
      for (var x = 0; x < width; x++) {
        final index = y * width + x;
        final value = feathered[index];
        if (value <= 0) continue;
        final nx = resolved.normalizedX(x);

        final protect = math.max(
          SkinMaskUtils.softRegionsWeight(
            nx,
            ny,
            protectedRegions,
            edgeFeather: 0.02,
          ),
          SkinMaskUtils.softRegionsWeight(
            nx,
            ny,
            geometric.eyebrowRegions,
            edgeFeather: 0.02,
          ),
        );
        if (protect >= 1) continue;

        final byte = (value * (1 - protect)).round().clamp(0, 255);
        if (byte <= 0) continue;
        weights[index] = byte;
        covered++;
      }
    }

    return SkinWeightMap(
      weights: weights,
      width: width,
      height: height,
      fromSegmentation: parsing.source != FaceParsingSource.geometric,
      coverage: covered / pixels,
      parsingSource: parsing.source,
    );
  }

  void clearCache() => _cache.clear();
}
