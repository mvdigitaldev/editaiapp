import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../segment/face_parts_segmentation.dart';
import '../../../segment/face_parsing_result.dart';
import '../mask_factory.dart';
import '../skin_mask_utils.dart';
import 'guided_filter.dart';

/// Mapeia pixels do buffer sendo processado para coordenadas normalizadas da
/// imagem COMPLETA.
///
/// No export por tiles o pass recebe apenas o recorte, mas as máscaras vêm
/// dos landmarks em coordenadas da imagem inteira; sem essa conversão o rosto
/// seria mapeado no 0..1 do tile e a pele cairia no lugar errado.
class SkinTileMapping {
  const SkinTileMapping({
    this.originX = 0,
    this.originY = 0,
    this.fullWidth,
    this.fullHeight,
  });

  final int originX;
  final int originY;
  final int? fullWidth;
  final int? fullHeight;

  ResolvedSkinTileMapping resolve(int width, int height) {
    return ResolvedSkinTileMapping(
      originX: originX,
      originY: originY,
      fullWidth: (fullWidth ?? width).toDouble(),
      fullHeight: (fullHeight ?? height).toDouble(),
    );
  }
}

class ResolvedSkinTileMapping {
  const ResolvedSkinTileMapping({
    required this.originX,
    required this.originY,
    required this.fullWidth,
    required this.fullHeight,
  });

  final int originX;
  final int originY;
  final double fullWidth;
  final double fullHeight;

  double normalizedX(int x) => (originX + x + 0.5) / fullWidth;

  double normalizedY(int y) => (originY + y + 0.5) / fullHeight;
}

/// Máscara de pele rasterizada (1 byte por pixel, 0–255) usada pelos passes
/// do Grupo A.
///
/// Substitui a amostragem paramétrica por retângulo/elipse do
/// [SkinProcessingMask] no caminho de suavização: com um mapa rasterizado o
/// feather é real (blur separável) e o mesmo buffer serve como textura R8 na
/// migração para GPU nativa.
///
/// Fonte da máscara, em ordem de preferência:
/// 1. [FacePartsSegmentation] (MediaPipe multiclass) — classe `faceSkin`;
/// 2. elipse do `faceBounds` dos landmarks (fallback quando a segmentação
///    não está disponível ou tem cobertura implausível).
///
/// Em ambos os casos as regiões protegidas dos landmarks (olhos, boca,
/// sobrancelhas) são subtraídas DEPOIS do feather: parsing de pele inclui a
/// pálpebra, e borrar cílio/sobrancelha é o defeito visual nº 1 de
/// suavizador de pele (invariante A1 do catálogo de Visual Quality Targets).
class SkinWeightMap {
  const SkinWeightMap({
    required this.weights,
    required this.width,
    required this.height,
    required this.fromSegmentation,
    required this.coverage,
    this.parsingSource,
  });

  final Uint8List weights;
  final int width;
  final int height;

  /// `true` quando a máscara veio da segmentação semântica.
  final bool fromSegmentation;

  /// Origem do face parsing quando [MaskFactory] foi usada (Sprint 4).
  final FaceParsingSource? parsingSource;

  /// Fração de pixels da imagem com peso > 0.
  final double coverage;

  bool get isEmpty => coverage <= 0;

  double weightAt(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return 0;
    return weights[y * width + x] / 255.0;
  }

  /// Cobertura mínima de pele facial na segmentação para confiar nela.
  /// Abaixo disso (rosto minúsculo, segmentação falhou, foto sem pessoa) o
  /// fallback geométrico é mais seguro.
  static const minSegmentationCoverage = 0.005;

  static final MaskFactory _defaultMaskFactory = MaskFactory();

  /// Rasteriza o peso da região sob os olhos (olheiras) no mesmo grid da
  /// máscara de pele, para que o engine rode sobre buffers planos —
  /// requisito para executar em isolate.
  static Uint8List rasterizeUnderEye({
    required int width,
    required int height,
    required SkinProcessingMask geometric,
    SkinTileMapping mapping = const SkinTileMapping(),
  }) {
    final out = Uint8List(math.max(width * height, 0));
    if (out.isEmpty || geometric.isEmpty) return out;
    final resolved = mapping.resolve(width, height);
    for (var y = 0; y < height; y++) {
      final ny = resolved.normalizedY(y);
      for (var x = 0; x < width; x++) {
        final weight =
            SkinMaskUtils.underEyeWeight(resolved.normalizedX(x), ny, geometric);
        if (weight <= 0) continue;
        out[y * width + x] = (weight * 255).round().clamp(0, 255);
      }
    }
    return out;
  }

  static SkinWeightMap build({
    required int width,
    required int height,
    required SkinProcessingMask geometric,
    FacePartsSegmentation? segmentation,
    FaceParsingResult? parsing,
    SkinTileMapping mapping = const SkinTileMapping(),
    MaskFactory? maskFactory,
  }) {
    if (parsing != null && !parsing.isEmpty) {
      return (maskFactory ?? _defaultMaskFactory).buildSkin(
        parsing: parsing,
        geometric: geometric,
        width: width,
        height: height,
        mapping: mapping,
      );
    }

    final pixels = width * height;
    final resolved = mapping.resolve(width, height);
    final bounds = geometric.faceBounds;
    if (pixels <= 0 || bounds.isEmpty) {
      return SkinWeightMap(
        weights: Uint8List(math.max(pixels, 0)),
        width: width,
        height: height,
        fromSegmentation: false,
        coverage: 0,
      );
    }

    final useSegmentation = segmentation != null &&
        !segmentation.isEmpty &&
        segmentation.coverageOf(FacePartClass.faceSkin) >=
            minSegmentationCoverage;

    // Elipse inscrita no faceBounds: aproxima o oval do rosto melhor que o
    // retângulo, que pegaria fundo nos cantos.
    final ellipse = NormalizedEllipse(
      center: bounds.center,
      radiusX: bounds.width / 2,
      radiusY: bounds.height / 2,
    );
    // A segmentação já delimita a pele, mas limitamos ao entorno do rosto
    // para não tratar braço/colo (classe bodySkin vizinha, ou pele de outra
    // pessoa) como rosto do sujeito.
    final gate = bounds.inflate(math.max(bounds.width, bounds.height) * 0.12);

    final raw = Uint8List(pixels);
    for (var y = 0; y < height; y++) {
      final ny = resolved.normalizedY(y);
      for (var x = 0; x < width; x++) {
        final nx = resolved.normalizedX(x);
        if (!gate.contains(Offset(nx, ny))) {
          continue;
        }
        final base = useSegmentation
            ? (segmentation.isClassAt(nx, ny, FacePartClass.faceSkin) ? 1.0 : 0.0)
            : ellipse.weight(nx, ny, edgeFeather: 0.06);
        if (base <= 0) {
          continue;
        }
        raw[y * width + x] = (base * 255).round().clamp(0, 255);
      }
    }

    // Feather proporcional ao tamanho do rosto: a máscara de segmentação tem
    // borda dura (categoria por pixel) e produziria degrau visível.
    final faceEdgePx = math.max(
      bounds.width * resolved.fullWidth,
      bounds.height * resolved.fullHeight,
    );
    final featherRadius = (faceEdgePx * 0.012).round().clamp(1, 24);
    final feathered = GuidedFilter.boxMeanU8(
      raw,
      width: width,
      height: height,
      radius: featherRadius,
    );

    // Proteção aplicada por último: garante peso exatamente zero em olhos,
    // boca e sobrancelhas, inclusive contra o vazamento do feather.
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

        final byte = (value * (1 - protect) * 255).round().clamp(0, 255);
        if (byte <= 0) continue;
        weights[index] = byte;
        covered++;
      }
    }

    return SkinWeightMap(
      weights: weights,
      width: width,
      height: height,
      fromSegmentation: useSegmentation,
      coverage: covered / pixels,
    );
  }
}
