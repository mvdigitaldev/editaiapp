import 'dart:ui';

import 'face_mesh_result.dart';

/// Utilitários para detecção e seleção de múltiplos rostos (Sprint 7).
abstract final class MultiFaceDetection {
  static const maxFaces = 5;

  /// Índice do rosto com maior área de bounding box (primário).
  static int indexOfLargest(List<FaceMeshResult> faces) {
    if (faces.isEmpty) {
      return 0;
    }
    var bestIndex = 0;
    var bestArea = 0.0;
    for (var i = 0; i < faces.length; i++) {
      final area = faces[i].boundingBox.width * faces[i].boundingBox.height;
      if (area > bestArea) {
        bestArea = area;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  static FaceMeshResult? primaryFace(List<FaceMeshResult> faces) {
    if (faces.isEmpty) {
      return null;
    }
    return faces[indexOfLargest(faces)];
  }

  /// Hit test em coordenadas normalizadas [0,1].
  static int? indexAtNormalized(
    List<FaceMeshResult> faces,
    Offset normalized,
  ) {
    for (var i = faces.length - 1; i >= 0; i--) {
      final expanded = faces[i].boundingBox.inflate(0.02);
      if (expanded.contains(normalized)) {
        return i;
      }
    }
    return null;
  }
}
