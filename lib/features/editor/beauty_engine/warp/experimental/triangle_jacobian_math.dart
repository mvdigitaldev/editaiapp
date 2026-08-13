import 'dart:math' as math;

import 'package:flutter/material.dart' show Offset;

import '../../mesh/tri_mesh_spatial_index.dart';
import '../../models/tri_mesh.dart';

/// Definições compartilhadas de Jacobian — campo vs malha (Fase 9).
abstract final class TriangleJacobianMath {
  TriangleJacobianMath._();

  static const jacobianTolerance = 1e-4;

  /// Jacobian de malha: det(F) do mapa afim source→destination por triângulo.
  ///
  /// Para displacement PL por vértice, é constante dentro do triângulo.
  /// Com delta puramente horizontal (dy=0): det(F) = 1 + ∂u/∂x exatamente.
  static double meshTriangleJacobian(
    TriMesh mesh,
    List<Offset> deltas,
    int i0,
    int i1,
    int i2,
  ) {
    final p0 = Offset(mesh.vertices[i0 * 2], mesh.vertices[i0 * 2 + 1]);
    final p1 = Offset(mesh.vertices[i1 * 2], mesh.vertices[i1 * 2 + 1]);
    final p2 = Offset(mesh.vertices[i2 * 2], mesh.vertices[i2 * 2 + 1]);

    final d0 = deltas[i0];
    final d1 = deltas[i1];
    final d2 = deltas[i2];

    final q0 = p0 + d0;
    final q1 = p1 + d1;
    final q2 = p2 + d2;

    final t1x = p1.dx - p0.dx;
    final t1y = p1.dy - p0.dy;
    final t2x = p2.dx - p0.dx;
    final t2y = p2.dy - p0.dy;
    final detT = t1x * t2y - t1y * t2x;
    if (detT.abs() < 1e-12) {
      return 0.0;
    }

    final g1x = q1.dx - q0.dx;
    final g1y = q1.dy - q0.dy;
    final g2x = q2.dx - q0.dx;
    final g2y = q2.dy - q0.dy;

    final f00 = (g1x * t2y - g2x * t1y) / detT;
    final f01 = (g2x * t1x - g1x * t2x) / detT;
    final f10 = (g1y * t2y - g2y * t1y) / detT;
    final f11 = (g2y * t1x - g1y * t2x) / detT;

    return f00 * f11 - f01 * f10;
  }

  /// Jacobian exato do campo PL no centróide do triângulo (= mesh J).
  static double exactFieldJacobianAtCentroid(
    TriMesh mesh,
    List<Offset> deltas,
    int tri,
  ) {
    final i0 = mesh.indices[tri * 3];
    final i1 = mesh.indices[tri * 3 + 1];
    final i2 = mesh.indices[tri * 3 + 2];
    return meshTriangleJacobian(mesh, deltas, i0, i1, i2);
  }

  /// Jacobian de campo via diferenças finitas (como Fases 6–8).
  static double? finiteDiffFieldJacobian({
    required TriMeshSpatialIndex sourceIndex,
    required List<Offset> deltas,
    required int vertexCount,
    required double px,
    required double py,
    double h = 2.0,
  }) {
    Offset? disp(double x, double y) {
      final tri = sourceIndex.locateTriangleIndex(x, y);
      if (tri == null) {
        return null;
      }
      final hit = sourceIndex.barycentricInTriangle(tri, x, y);
      if (hit == null) {
        return null;
      }
      var dx = 0.0;
      var dy = 0.0;
      for (final (i, w) in [
        (hit.i0, hit.w0),
        (hit.i1, hit.w1),
        (hit.i2, hit.w2),
      ]) {
        if (i >= vertexCount) {
          return null;
        }
        dx += w * deltas[i].dx;
        dy += w * deltas[i].dy;
      }
      return Offset(dx, dy);
    }

    final c = disp(px, py);
    final xp = disp(px + h, py);
    final xm = disp(px - h, py);
    final yp = disp(px, py + h);
    final ym = disp(px, py - h);
    if (c == null || xp == null || xm == null || yp == null || ym == null) {
      return null;
    }

    final dudx = (xp.dx - xm.dx) / (2 * h);
    final dudy = (yp.dx - ym.dx) / (2 * h);
    final dvdx = (xp.dy - xm.dy) / (2 * h);
    final dvdy = (yp.dy - ym.dy) / (2 * h);
    return (1 + dudx) * (1 + dvdy) - dudy * dvdx;
  }

  /// Área assinada e razão dest/source.
  static double signedTriangleArea(
    TriMesh mesh,
    List<Offset> deltas,
    int tri, {
    bool destination = false,
  }) {
    final i0 = mesh.indices[tri * 3];
    final i1 = mesh.indices[tri * 3 + 1];
    final i2 = mesh.indices[tri * 3 + 2];

    double x(int i) =>
        mesh.vertices[i * 2] + (destination ? deltas[i].dx : 0);
    double y(int i) =>
        mesh.vertices[i * 2 + 1] + (destination ? deltas[i].dy : 0);

    final x0 = x(i0);
    final y0 = y(i0);
    final x1 = x(i1);
    final y1 = y(i1);
    final x2 = x(i2);
    final y2 = y(i2);

    return 0.5 * ((x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0));
  }

  static double areaRatio(TriMesh mesh, List<Offset> deltas, int tri) {
    final src = signedTriangleArea(mesh, deltas, tri).abs();
    if (src < 1e-12) {
      return 0.0;
    }
    final dst = signedTriangleArea(mesh, deltas, tri, destination: true).abs();
    return dst / src;
  }

  static ({double cx, double cy}) triangleCentroid(TriMesh mesh, int tri) {
    final i0 = mesh.indices[tri * 3];
    final i1 = mesh.indices[tri * 3 + 1];
    final i2 = mesh.indices[tri * 3 + 2];
    return (
      cx: (mesh.vertices[i0 * 2] +
              mesh.vertices[i1 * 2] +
              mesh.vertices[i2 * 2]) /
          3,
      cy: (mesh.vertices[i0 * 2 + 1] +
              mesh.vertices[i1 * 2 + 1] +
              mesh.vertices[i2 * 2 + 1]) /
          3,
    );
  }

  /// Para delta horizontal puro: J = 1 + Σ(∂w_i/∂x · dx_i).
  static double horizontalFieldJacobianExact(
    TriMesh mesh,
    List<Offset> deltas,
    int tri,
  ) {
    final i0 = mesh.indices[tri * 3];
    final i1 = mesh.indices[tri * 3 + 1];
    final i2 = mesh.indices[tri * 3 + 2];

    final p0x = mesh.vertices[i0 * 2];
    final p0y = mesh.vertices[i0 * 2 + 1];
    final p1x = mesh.vertices[i1 * 2];
    final p1y = mesh.vertices[i1 * 2 + 1];
    final p2x = mesh.vertices[i2 * 2];
    final p2y = mesh.vertices[i2 * 2 + 1];

    final area2 = (p1x - p0x) * (p2y - p0y) - (p2x - p0x) * (p1y - p0y);
    if (area2.abs() < 1e-12) {
      return 0.0;
    }

    // ∂w0/∂x, ∂w1/∂x, ∂w2/∂x para coordenadas baricêntricas PL
    final dw0dx = (p1y - p2y) / area2;
    final dw1dx = (p2y - p0y) / area2;
    final dw2dx = (p0y - p1y) / area2;

    final dudx = dw0dx * deltas[i0].dx +
        dw1dx * deltas[i1].dx +
        dw2dx * deltas[i2].dx;
    return 1 + dudx;
  }

  static List<double> allMeshJacobians(TriMesh mesh, List<Offset> deltas) {
    final out = List<double>.filled(mesh.triangleCount, 1.0);
    for (var t = 0; t < mesh.triangleCount; t++) {
      final i0 = mesh.indices[t * 3];
      final i1 = mesh.indices[t * 3 + 1];
      final i2 = mesh.indices[t * 3 + 2];
      if (i0 >= deltas.length || i1 >= deltas.length || i2 >= deltas.length) {
        continue;
      }
      out[t] = meshTriangleJacobian(mesh, deltas, i0, i1, i2);
    }
    return out;
  }

  static double minJacobian(List<double> values) {
    if (values.isEmpty) {
      return 1.0;
    }
    return values.reduce(math.min);
  }

  static int countBelow(List<double> values, double threshold) {
    var n = 0;
    for (final v in values) {
      if (v < threshold) {
        n++;
      }
    }
    return n;
  }

  /// Fator uniforme s∈[0,1] para escalar os 3 deltas do triângulo até J≥epsilon.
  static double minUniformScaleForTriangle({
    required TriMesh mesh,
    required List<Offset> baseDeltas,
    required List<double> vertexScales,
    required int i0,
    required int i1,
    required int i2,
    required double epsilon,
  }) {
    var lo = 0.0;
    var hi = 1.0;

    final d0 = Offset(
      baseDeltas[i0].dx * vertexScales[i0],
      baseDeltas[i0].dy * vertexScales[i0],
    );
    final d1 = Offset(
      baseDeltas[i1].dx * vertexScales[i1],
      baseDeltas[i1].dy * vertexScales[i1],
    );
    final d2 = Offset(
      baseDeltas[i2].dx * vertexScales[i2],
      baseDeltas[i2].dy * vertexScales[i2],
    );

    final jAtHi = _meshJFromDeltas(mesh, d0, d1, d2, i0, i1, i2);
    if (jAtHi >= epsilon) {
      return 1.0;
    }

    for (var i = 0; i < 32; i++) {
      final mid = (lo + hi) / 2;
      final j = _meshJFromDeltas(
        mesh,
        Offset(d0.dx * mid, d0.dy * mid),
        Offset(d1.dx * mid, d1.dy * mid),
        Offset(d2.dx * mid, d2.dy * mid),
        i0,
        i1,
        i2,
      );
      if (j >= epsilon) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  static double _meshJFromDeltas(
    TriMesh mesh,
    Offset d0,
    Offset d1,
    Offset d2,
    int i0,
    int i1,
    int i2,
  ) {
    final p0 = Offset(mesh.vertices[i0 * 2], mesh.vertices[i0 * 2 + 1]);
    final p1 = Offset(mesh.vertices[i1 * 2], mesh.vertices[i1 * 2 + 1]);
    final p2 = Offset(mesh.vertices[i2 * 2], mesh.vertices[i2 * 2 + 1]);

    final q0 = p0 + d0;
    final q1 = p1 + d1;
    final q2 = p2 + d2;

    final t1x = p1.dx - p0.dx;
    final t1y = p1.dy - p0.dy;
    final t2x = p2.dx - p0.dx;
    final t2y = p2.dy - p0.dy;
    final detT = t1x * t2y - t1y * t2x;
    if (detT.abs() < 1e-12) {
      return 0.0;
    }

    final g1x = q1.dx - q0.dx;
    final g1y = q1.dy - q0.dy;
    final g2x = q2.dx - q0.dx;
    final g2y = q2.dy - q0.dy;

    final f00 = (g1x * t2y - g2x * t1y) / detT;
    final f01 = (g2x * t1x - g1x * t2x) / detT;
    final f10 = (g1y * t2y - g2y * t1y) / detT;
    final f11 = (g2y * t1x - g1y * t2x) / detT;

    return f00 * f11 - f01 * f10;
  }
}
