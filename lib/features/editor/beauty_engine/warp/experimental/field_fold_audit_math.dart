import 'dart:math' as math;

import 'package:flutter/material.dart' show Offset;

import '../../mesh/tri_mesh_spatial_index.dart';
import '../../models/tri_mesh.dart';
import 'triangle_jacobian_math.dart';

/// Categorias de stencil FD (Fase 13 — diagnóstico only).
enum FieldFoldStencilCategory {
  sameTriangle,
  crossesTriangleBoundary,
  outsideMesh,
  other,
}

/// Resultado detalhado de um ponto FD.
class FieldFoldPointAudit {
  const FieldFoldPointAudit({
    required this.x,
    required this.y,
    required this.fdJ,
    required this.h,
    required this.triangleAtP,
    required this.triangleAtXm,
    required this.triangleAtXp,
    required this.triangleAtYm,
    required this.triangleAtYp,
    required this.category,
    required this.exactPlJ,
    required this.triangleJ,
    required this.centroidX,
    required this.centroidY,
    required this.minEdgeDistance,
    required this.sameTriangleFdJ,
  });

  final double x;
  final double y;
  final double fdJ;
  final double h;
  final int? triangleAtP;
  final int? triangleAtXm;
  final int? triangleAtXp;
  final int? triangleAtYm;
  final int? triangleAtYp;
  final FieldFoldStencilCategory category;
  final double? exactPlJ;
  final double? triangleJ;
  final double centroidX;
  final double centroidY;
  final double minEdgeDistance;
  final double? sameTriangleFdJ;
}

/// Matemática de auditoria FD vs PL (Fase 13, diagnóstico only).
abstract final class FieldFoldAuditMath {
  FieldFoldAuditMath._();

  static Offset? displacementAt({
    required TriMeshSpatialIndex sourceIndex,
    required List<Offset> deltas,
    required int vertexCount,
    required double x,
    required double y,
  }) {
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

  static FieldFoldStencilCategory classifyStencil({
    required int? triP,
    required int? triXm,
    required int? triXp,
    required int? triYm,
    required int? triYp,
  }) {
    if (triP == null) {
      return FieldFoldStencilCategory.outsideMesh;
    }
    if (triXm == null || triXp == null || triYm == null || triYp == null) {
      return FieldFoldStencilCategory.outsideMesh;
    }
    final xSame = triXm == triP && triXp == triP;
    final ySame = triYm == triP && triYp == triP;
    if (xSame && ySame) {
      return FieldFoldStencilCategory.sameTriangle;
    }
    if (!xSame || !ySame) {
      return FieldFoldStencilCategory.crossesTriangleBoundary;
    }
    return FieldFoldStencilCategory.other;
  }

  static double? finiteDiffJacobian({
    required TriMeshSpatialIndex sourceIndex,
    required List<Offset> deltas,
    required int vertexCount,
    required double px,
    required double py,
    required double h,
    required bool sameTriangleOnly,
  }) {
    final triP = sourceIndex.locateTriangleIndex(px, py);
    if (triP == null) {
      return null;
    }

    final triXm = sourceIndex.locateTriangleIndex(px - h, py);
    final triXp = sourceIndex.locateTriangleIndex(px + h, py);
    final triYm = sourceIndex.locateTriangleIndex(px, py - h);
    final triYp = sourceIndex.locateTriangleIndex(px, py + h);

    if (sameTriangleOnly) {
      if (triXm != triP ||
          triXp != triP ||
          triYm != triP ||
          triYp != triP) {
        return null;
      }
    }

    final c = displacementAt(
      sourceIndex: sourceIndex,
      deltas: deltas,
      vertexCount: vertexCount,
      x: px,
      y: py,
    );
    final xp = displacementAt(
      sourceIndex: sourceIndex,
      deltas: deltas,
      vertexCount: vertexCount,
      x: px + h,
      y: py,
    );
    final xm = displacementAt(
      sourceIndex: sourceIndex,
      deltas: deltas,
      vertexCount: vertexCount,
      x: px - h,
      y: py,
    );
    final yp = displacementAt(
      sourceIndex: sourceIndex,
      deltas: deltas,
      vertexCount: vertexCount,
      x: px,
      y: py + h,
    );
    final ym = displacementAt(
      sourceIndex: sourceIndex,
      deltas: deltas,
      vertexCount: vertexCount,
      x: px,
      y: py - h,
    );
    if (c == null || xp == null || xm == null || yp == null || ym == null) {
      return null;
    }

    final dudx = (xp.dx - xm.dx) / (2 * h);
    final dudy = (yp.dx - ym.dx) / (2 * h);
    final dvdx = (xp.dy - xm.dy) / (2 * h);
    final dvdy = (yp.dy - ym.dy) / (2 * h);
    return (1 + dudx) * (1 + dvdy) - dudy * dvdx;
  }

  static double minDistanceToTriangleEdges(
    TriMesh mesh,
    int tri,
    double px,
    double py,
  ) {
    final i0 = mesh.indices[tri * 3];
    final i1 = mesh.indices[tri * 3 + 1];
    final i2 = mesh.indices[tri * 3 + 2];
    final verts = [
      Offset(mesh.vertices[i0 * 2], mesh.vertices[i0 * 2 + 1]),
      Offset(mesh.vertices[i1 * 2], mesh.vertices[i1 * 2 + 1]),
      Offset(mesh.vertices[i2 * 2], mesh.vertices[i2 * 2 + 1]),
    ];
    var minDist = double.infinity;
    for (var e = 0; e < 3; e++) {
      final a = verts[e];
      final b = verts[(e + 1) % 3];
      minDist = math.min(minDist, _pointSegmentDistance(px, py, a.dx, a.dy, b.dx, b.dy));
    }
    return minDist;
  }

  static double _pointSegmentDistance(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    if (len2 < 1e-18) {
      return math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay));
    }
    var t = ((px - ax) * dx + (py - ay) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final cx = ax + t * dx;
    final cy = ay + t * dy;
    return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
  }

  static FieldFoldPointAudit? auditPoint({
    required TriMesh mesh,
    required TriMeshSpatialIndex sourceIndex,
    required List<Offset> deltas,
    required int vertexCount,
    required double px,
    required double py,
    required double h,
  }) {
    final triP = sourceIndex.locateTriangleIndex(px, py);
    final triXm = sourceIndex.locateTriangleIndex(px - h, py);
    final triXp = sourceIndex.locateTriangleIndex(px + h, py);
    final triYm = sourceIndex.locateTriangleIndex(px, py - h);
    final triYp = sourceIndex.locateTriangleIndex(px, py + h);

    final fdJ = finiteDiffJacobian(
      sourceIndex: sourceIndex,
      deltas: deltas,
      vertexCount: vertexCount,
      px: px,
      py: py,
      h: h,
      sameTriangleOnly: false,
    );
    if (fdJ == null) {
      return null;
    }

    final category = classifyStencil(
      triP: triP,
      triXm: triXm,
      triXp: triXp,
      triYm: triYm,
      triYp: triYp,
    );

    double? exactPlJ;
    double? triangleJ;
    double cx = px;
    double cy = py;
    var minEdge = double.infinity;

    if (triP != null) {
      final i0 = mesh.indices[triP * 3];
      final i1 = mesh.indices[triP * 3 + 1];
      final i2 = mesh.indices[triP * 3 + 2];
      if (i0 < vertexCount && i1 < vertexCount && i2 < vertexCount) {
        triangleJ = TriangleJacobianMath.meshTriangleJacobian(
          mesh,
          deltas,
          i0,
          i1,
          i2,
        );
        exactPlJ = triangleJ;
        final cent = TriangleJacobianMath.triangleCentroid(mesh, triP);
        cx = cent.cx;
        cy = cent.cy;
        minEdge = minDistanceToTriangleEdges(mesh, triP, px, py);
      }
    }

    final sameTriJ = finiteDiffJacobian(
      sourceIndex: sourceIndex,
      deltas: deltas,
      vertexCount: vertexCount,
      px: px,
      py: py,
      h: h,
      sameTriangleOnly: true,
    );

    return FieldFoldPointAudit(
      x: px,
      y: py,
      fdJ: fdJ,
      h: h,
      triangleAtP: triP,
      triangleAtXm: triXm,
      triangleAtXp: triXp,
      triangleAtYm: triYm,
      triangleAtYp: triYp,
      category: category,
      exactPlJ: exactPlJ,
      triangleJ: triangleJ,
      centroidX: cx,
      centroidY: cy,
      minEdgeDistance: minEdge,
      sameTriangleFdJ: sameTriJ,
    );
  }

  static String categoryLabel(FieldFoldStencilCategory c) {
    switch (c) {
      case FieldFoldStencilCategory.sameTriangle:
        return 'SAME_TRIANGLE';
      case FieldFoldStencilCategory.crossesTriangleBoundary:
        return 'CROSSES_TRIANGLE_BOUNDARY';
      case FieldFoldStencilCategory.outsideMesh:
        return 'OUTSIDE_MESH';
      case FieldFoldStencilCategory.other:
        return 'OTHER';
    }
  }

  static Map<String, dynamic> pointToJson(FieldFoldPointAudit p) {
    return {
      'x': p.x,
      'y': p.y,
      'fdJ': p.fdJ,
      'h': p.h,
      'triangleAtP': p.triangleAtP,
      'triangleAtXm': p.triangleAtXm,
      'triangleAtXp': p.triangleAtXp,
      'triangleAtYm': p.triangleAtYm,
      'triangleAtYp': p.triangleAtYp,
      'category': categoryLabel(p.category),
      'exactPlJ': p.exactPlJ,
      'triangleJ': p.triangleJ,
      'centroidX': p.centroidX,
      'centroidY': p.centroidY,
      'minEdgeDistance': p.minEdgeDistance,
      'sameTriangleFdJ': p.sameTriangleFdJ,
    };
  }
}
