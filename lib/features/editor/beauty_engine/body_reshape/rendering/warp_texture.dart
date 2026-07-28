import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../models/warp_field.dart';
import '../maps/influence_map.dart';
import '../protection/rigidity_map.dart';

/// Tipo semântico de textura enviada ao backend de preview.
enum WarpTextureKind {
  source,
  displacement,
  mask,
  influence,
  protection,
}

/// Textura RGBA8888 empacotada a partir de mapas de warp (grade ou full-res).
///
/// Deslocamento assinado é codificado em RG: `channel = clamp(v * 0.5 + 0.5)`.
/// O shader decodifica com `rg * 2 - 1` (fração da largura/altura da imagem).
class WarpTexture {
  final WarpTextureKind kind;
  final int width;
  final int height;
  final Uint8List rgba;
  final Size imageSize;

  const WarpTexture({
    required this.kind,
    required this.width,
    required this.height,
    required this.rgba,
    required this.imageSize,
  }) : assert(width > 0 && height > 0);

  int get byteLength => rgba.length;

  /// Deslocamento do [WarpField] na resolução da grade (bilinear no GPU).
  factory WarpTexture.fromDisplacement(WarpField field) {
    final w = field.gridWidth;
    final h = field.gridHeight;
    final imgW = math.max(field.imageSize.width, 1.0);
    final imgH = math.max(field.imageSize.height, 1.0);
    final rgba = Uint8List(w * h * 4);

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final idx = y * w + x;
        final dx = field.displacement[idx * 2] / imgW;
        final dy = field.displacement[idx * 2 + 1] / imgH;
        final o = idx * 4;
        rgba[o] = _encodeSignedUnit(dx);
        rgba[o + 1] = _encodeSignedUnit(dy);
        rgba[o + 2] = 0;
        rgba[o + 3] = 255;
      }
    }

    return WarpTexture(
      kind: WarpTextureKind.displacement,
      width: w,
      height: h,
      rgba: rgba,
      imageSize: field.imageSize,
    );
  }

  /// Máscara do [WarpField] na resolução da grade.
  factory WarpTexture.fromMask(WarpField field) {
    final w = field.gridWidth;
    final h = field.gridHeight;
    final rgba = Uint8List(w * h * 4);

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final idx = y * w + x;
        final m = (field.mask[idx].clamp(0.0, 1.0) * 255).round();
        final o = idx * 4;
        rgba[o] = m;
        rgba[o + 1] = m;
        rgba[o + 2] = m;
        rgba[o + 3] = 255;
      }
    }

    return WarpTexture(
      kind: WarpTextureKind.mask,
      width: w,
      height: h,
      rgba: rgba,
      imageSize: field.imageSize,
    );
  }

  factory WarpTexture.fromInfluenceMap(InfluenceMap map) {
    return _fromScalarField(
      kind: WarpTextureKind.influence,
      values: map.values,
      width: map.width,
      height: map.height,
      imageSize: map.imageSize,
    );
  }

  factory WarpTexture.fromRigidityMap(RigidityMap map) {
    return _fromScalarField(
      kind: WarpTextureKind.protection,
      values: map.values,
      width: map.width,
      height: map.height,
      imageSize: map.imageSize,
    );
  }

  /// Textura 1×1 constante (útil como sampler “neutro”).
  factory WarpTexture.constant({
    required WarpTextureKind kind,
    required Size imageSize,
    double value = 0,
  }) {
    final v = (value.clamp(0.0, 1.0) * 255).round();
    return WarpTexture(
      kind: kind,
      width: 1,
      height: 1,
      rgba: Uint8List.fromList([v, v, v, 255]),
      imageSize: imageSize,
    );
  }

  factory WarpTexture.fromSourceRgba({
    required Uint8List rgba,
    required int width,
    required int height,
    required Size imageSize,
  }) {
    return WarpTexture(
      kind: WarpTextureKind.source,
      width: width,
      height: height,
      rgba: rgba,
      imageSize: imageSize,
    );
  }

  static WarpTexture _fromScalarField({
    required WarpTextureKind kind,
    required Float32List values,
    required int width,
    required int height,
    required Size imageSize,
  }) {
    if (width <= 0 || height <= 0 || values.isEmpty) {
      return WarpTexture.constant(kind: kind, imageSize: imageSize, value: 0);
    }

    final rgba = Uint8List(width * height * 4);
    final count = math.min(values.length, width * height);
    for (var i = 0; i < count; i++) {
      final v = (values[i].clamp(0.0, 1.0) * 255).round();
      final o = i * 4;
      rgba[o] = v;
      rgba[o + 1] = v;
      rgba[o + 2] = v;
      rgba[o + 3] = 255;
    }

    return WarpTexture(
      kind: kind,
      width: width,
      height: height,
      rgba: rgba,
      imageSize: imageSize,
    );
  }

  /// Decodifica canal RG de deslocamento (testes / referência).
  static Offset decodeDisplacement(int r, int g, Size imageSize) {
    final nx = (r / 255.0) * 2.0 - 1.0;
    final ny = (g / 255.0) * 2.0 - 1.0;
    return Offset(nx * imageSize.width, ny * imageSize.height);
  }

  static int _encodeSignedUnit(double v) {
    return ((v * 0.5 + 0.5).clamp(0.0, 1.0) * 255.0).round();
  }
}
