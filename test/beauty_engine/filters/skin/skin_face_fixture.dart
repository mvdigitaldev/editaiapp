import 'dart:math' as math;
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/face_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';

/// Índices que `SkinMaskUtils` usa — precisam cair em posições
/// anatomicamente plausíveis para os testes de máscara fazerem sentido.
const faceOvalIndices = {
  10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365,
  379, 378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93,
  234, 127, 162, 21, 54, 103, 67, 109,
};
const leftEyeIndices = {
  263, 249, 390, 373, 374, 380, 381, 382, 362, 466, 388, 387, 386, 385, 384, 398,
};
const rightEyeIndices = {
  33, 7, 163, 144, 145, 153, 154, 155, 133, 246, 161, 160, 159, 158, 157, 173,
};
const leftBrowIndices = {276, 283, 282, 295, 285, 336, 296, 334, 293, 300};
const rightBrowIndices = {46, 53, 52, 65, 55, 107, 66, 105, 63, 70};
const innerMouthIndices = {
  13, 14, 87, 178, 88, 317, 402, 318, 324, 415, 310, 311, 312, 80, 81, 82, 191,
};

/// Centros de referência do rosto sintético (coordenadas normalizadas).
const faceCenter = Offset(0.5, 0.42);
const faceRadiusX = 0.20;
const faceRadiusY = 0.24;
const leftEyeCenter = Offset(0.585, 0.34);
const rightEyeCenter = Offset(0.415, 0.34);
const mouthCenter = Offset(0.5, 0.55);
const cheekSample = Offset(0.60, 0.46);

/// Rosto sintético com olhos, sobrancelhas e boca em posições realistas.
FaceMeshResult syntheticFace() {
  final points = <int, Offset>{};

  void placeOnEllipse(Set<int> indices, Offset center, double rx, double ry) {
    final sorted = indices.toList()..sort();
    for (var i = 0; i < sorted.length; i++) {
      final angle = (i / sorted.length) * 2 * math.pi;
      points[sorted[i]] = Offset(
        center.dx + math.cos(angle) * rx,
        center.dy + math.sin(angle) * ry,
      );
    }
  }

  placeOnEllipse(faceOvalIndices, faceCenter, faceRadiusX, faceRadiusY);
  placeOnEllipse(leftEyeIndices, leftEyeCenter, 0.045, 0.022);
  placeOnEllipse(rightEyeIndices, rightEyeCenter, 0.045, 0.022);
  placeOnEllipse(leftBrowIndices, const Offset(0.585, 0.295), 0.05, 0.008);
  placeOnEllipse(rightBrowIndices, const Offset(0.415, 0.295), 0.05, 0.008);
  placeOnEllipse(innerMouthIndices, mouthCenter, 0.055, 0.018);

  final landmarks = List.generate(
    FaceMeshResult.expectedLandmarkCount,
    (index) {
      final placed = points[index];
      if (placed != null) {
        return FaceLandmark(index: index, normalized: placed);
      }
      // Restante distribuído dentro do oval, sem afetar as regiões testadas.
      final angle = index * 0.618 * 2 * math.pi;
      final radius = 0.35 + (index % 7) * 0.04;
      return FaceLandmark(
        index: index,
        normalized: Offset(
          (faceCenter.dx + math.cos(angle) * faceRadiusX * radius)
              .clamp(0.0, 1.0),
          (faceCenter.dy + math.sin(angle) * faceRadiusY * radius)
              .clamp(0.0, 1.0),
        ),
      );
    },
  );

  return FaceMeshResult(
    landmarks: landmarks,
    confidence: 0.95,
    boundingBox: Rect.fromCenter(
      center: faceCenter,
      width: faceRadiusX * 2,
      height: faceRadiusY * 2,
    ),
  );
}
