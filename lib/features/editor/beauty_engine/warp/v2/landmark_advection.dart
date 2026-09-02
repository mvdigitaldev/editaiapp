import 'dart:ui';

import '../../models/face_landmark.dart';
import '../../models/face_mesh_result.dart';
import 'displacement_field.dart';

/// Leva os landmarks para a geometria já deformada por um campo.
///
/// A cadeia facial aplica um efeito sobre o RGBA que o anterior devolveu. Sem
/// advecção, o efeito a jusante constrói crista e domínio sobre landmarks que
/// já não coincidem com a silhueta da imagem que recebe: com o Jaw a 100% a
/// silhueta desloca-se 6–10 px sob as âncoras 132/58/172/136, e o peso passa a
/// cair em fundo e cabelo em vez do bordo — daí as pontas quando se somam
/// efeitos.
///
/// O renderer é backward (`src = dest − D(dest)`), logo o ponto material que
/// estava em `p` aparece em `q` com `q − D(q) = p`. Resolve-se por ponto fixo
/// `q ← p + D(q)`, que converge porque o campo não dobra (`detJ > 0`).
///
/// Só os landmarks avançam. `boundingBox` e `confidence` seguem intactos: nenhum
/// Field os lê, e a convenção de unidades do rect não é a do campo.
abstract final class LandmarkAdvection {
  LandmarkAdvection._();

  /// Iterações do ponto fixo. Uma já corrige a maior parte; três põem o resíduo
  /// abaixo do sub-pixel para os deslocamentos desta pipeline.
  static const iterations = 3;

  /// Chamar só para efeitos activos: não testa se o campo é nulo, porque
  /// `isZero` varre a imagem inteira. Quem encadeia salta a etapa inactiva e
  /// assim mantém o mesmo objecto `face`, o que importa porque os Fields a
  /// jusante cacheiam o peso unitário por `identical(face, ...)`.
  static FaceMeshResult advance({
    required FaceMeshResult face,
    required DisplacementField field,
    required Size imageSize,
  }) {
    if (imageSize.width <= 0 || imageSize.height <= 0) {
      return face;
    }
    if (field.width != imageSize.width.round() ||
        field.height != imageSize.height.round()) {
      throw StateError(
        'advection_size_mismatch: field ${field.width}x${field.height} '
        'image ${imageSize.width.round()}x${imageSize.height.round()}',
      );
    }

    final w = imageSize.width;
    final h = imageSize.height;
    final moved = List<FaceLandmark>.generate(
      face.landmarks.length,
      (i) {
        final lm = face.landmarks[i];
        final q = advancePoint(
          field,
          Offset(lm.normalized.dx * w, lm.normalized.dy * h),
        );
        return FaceLandmark(
          index: lm.index,
          normalized: Offset(q.dx / w, q.dy / h),
          z: lm.z,
          visibility: lm.visibility,
        );
      },
      growable: false,
    );

    return FaceMeshResult(
      landmarks: moved,
      boundingBox: face.boundingBox,
      confidence: face.confidence,
    );
  }

  static Offset advancePoint(DisplacementField field, Offset p) {
    var q = p;
    for (var k = 0; k < iterations; k++) {
      final d = _sample(field, q.dx, q.dy);
      q = Offset(p.dx + d.dx, p.dy + d.dy);
    }
    return q;
  }

  static Offset _sample(DisplacementField field, double x, double y) {
    final maxX = field.width - 1;
    final maxY = field.height - 1;
    final cx = x.clamp(0.0, maxX.toDouble());
    final cy = y.clamp(0.0, maxY.toDouble());
    final x0 = cx.floor();
    final y0 = cy.floor();
    final x1 = x0 + 1 <= maxX ? x0 + 1 : x0;
    final y1 = y0 + 1 <= maxY ? y0 + 1 : y0;
    final tx = cx - x0;
    final ty = cy - y0;
    final i00 = y0 * field.width + x0;
    final i10 = y0 * field.width + x1;
    final i01 = y1 * field.width + x0;
    final i11 = y1 * field.width + x1;
    return Offset(
      _blend(field.dx[i00], field.dx[i10], field.dx[i01], field.dx[i11], tx, ty),
      _blend(field.dy[i00], field.dy[i10], field.dy[i01], field.dy[i11], tx, ty),
    );
  }

  static double _blend(
    double v00,
    double v10,
    double v01,
    double v11,
    double tx,
    double ty,
  ) {
    final top = v00 + (v10 - v00) * tx;
    final bottom = v01 + (v11 - v01) * tx;
    return top + (bottom - top) * ty;
  }
}
