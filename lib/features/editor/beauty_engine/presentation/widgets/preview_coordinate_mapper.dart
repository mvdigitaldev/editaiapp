import 'dart:ui';

import 'package:flutter/rendering.dart';

/// Converte coordenadas do dedo no preview para UV normalizado [0,1] da imagem.
class PreviewCoordinateMapper {
  const PreviewCoordinateMapper();

  /// Tamanho da imagem ajustada com [BoxFit.contain] dentro de [viewportSize].
  Size fittedImageSize({
    required Size imageSize,
    required Size viewportSize,
  }) {
    if (imageSize.width <= 0 ||
        imageSize.height <= 0 ||
        viewportSize.width <= 0 ||
        viewportSize.height <= 0) {
      return viewportSize;
    }
    return applyBoxFit(BoxFit.contain, imageSize, viewportSize).destination;
  }

  /// [localPosition] no espaço de um widget que contém **exatamente** a imagem
  /// (mesma proporção, sem letterbox) — caso do preview envolvido por um
  /// SizedBox já ajustado.
  Offset? normalizedInImageBox({
    required Offset localPosition,
    required Size boxSize,
  }) {
    if (boxSize.width <= 0 || boxSize.height <= 0) {
      return null;
    }
    final bounds = Rect.fromLTWH(0, 0, boxSize.width, boxSize.height);
    if (!bounds.inflate(2.0).contains(localPosition)) {
      return null;
    }
    return Offset(
      (localPosition.dx / boxSize.width).clamp(0.0, 1.0),
      (localPosition.dy / boxSize.height).clamp(0.0, 1.0),
    );
  }

  /// Caso geral: widget maior que a imagem, que fica centralizada com
  /// [BoxFit.contain]. Retorna null se o ponto cai no letterbox.
  Offset? localToNormalized({
    required Offset localPosition,
    required Size viewportSize,
    required Size imageSize,
  }) {
    if (viewportSize.width <= 0 ||
        viewportSize.height <= 0 ||
        imageSize.width <= 0 ||
        imageSize.height <= 0) {
      return null;
    }

    final outputSize = fittedImageSize(
      imageSize: imageSize,
      viewportSize: viewportSize,
    );
    final dx = (viewportSize.width - outputSize.width) * 0.5;
    final dy = (viewportSize.height - outputSize.height) * 0.5;
    final imageRect = Rect.fromLTWH(dx, dy, outputSize.width, outputSize.height);

    if (!imageRect.inflate(1.0).contains(localPosition)) {
      return null;
    }

    return normalizedInImageBox(
      localPosition: localPosition - imageRect.topLeft,
      boxSize: imageRect.size,
    );
  }
}
