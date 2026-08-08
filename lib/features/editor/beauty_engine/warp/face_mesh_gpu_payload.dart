import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../body_reshape/maps/influence_map.dart';
import '../models/tri_mesh.dart';
import 'anatomy/constrained_vertex_field.dart';
import 'face_mesh_cell_index.dart';

/// Texturas RGBA8 empacotadas para warp piecewise-affine na GPU (Sprint 37).
class FaceMeshGpuAtlas {
  const FaceMeshGpuAtlas({
    required this.vertexData,
    required this.vertexDataWidth,
    required this.vertexDataHeight,
    required this.triIndexData,
    required this.triIndexWidth,
    required this.triIndexHeight,
    required this.cellTriData,
    required this.cellTriWidth,
    required this.cellTriHeight,
    required this.imageSize,
    required this.cellSize,
    required this.vertexCount,
    required this.triangleCount,
    required this.displacementScalePx,
  });

  final Uint8List vertexData;
  final int vertexDataWidth;
  final int vertexDataHeight;

  final Uint8List triIndexData;
  final int triIndexWidth;
  final int triIndexHeight;

  final Uint8List cellTriData;
  final int cellTriWidth;
  final int cellTriHeight;

  final Size imageSize;
  final double cellSize;
  final int vertexCount;
  final int triangleCount;
  final Offset displacementScalePx;

  factory FaceMeshGpuAtlas.build({
    required TriMesh mesh,
    required ConstrainedVertexField vertexField,
    required Size imageSize,
    required FaceMeshCellIndex cellIndex,
  }) {
    final vCount = math.min(
      vertexField.landmarkCount,
      mesh.vertices.length ~/ 2,
    );

    final tCount = mesh.triangleCount;
    final dispScale = _displacementScale(vertexField, imageSize);

    final vertexData = _packVertexData(
      mesh: mesh,
      vertexField: vertexField,
      imageSize: imageSize,
      vertexCount: vCount,
      dispScale: dispScale,
    );

    final triIndexData = _packTriIndices(mesh: mesh, triangleCount: tCount);

    final cellTriData = _packCellTriMap(
      cellIndex: cellIndex,
      triangleCount: tCount,
    );

    return FaceMeshGpuAtlas(
      vertexData: vertexData.data,
      vertexDataWidth: vertexData.width,
      vertexDataHeight: vertexData.height,
      triIndexData: triIndexData.data,
      triIndexWidth: triIndexData.width,
      triIndexHeight: triIndexData.height,
      cellTriData: cellTriData.data,
      cellTriWidth: cellTriData.width,
      cellTriHeight: cellTriData.height,
      imageSize: imageSize,
      cellSize: cellIndex.cellSize,
      vertexCount: vCount,
      triangleCount: tCount,
      displacementScalePx: dispScale,
    );
  }

  static Offset _displacementScale(
    ConstrainedVertexField field,
    Size imageSize,
  ) {
    final maxDisp = math.max(field.maxDisplacementMagnitude(), 1.0);
    final cap = math.max(imageSize.width, imageSize.height) * 0.12;
    final scale = math.min(maxDisp * 1.15, cap);
    return Offset(scale, scale);
  }

  static ({Uint8List data, int width, int height}) _packVertexData({
    required TriMesh mesh,
    required ConstrainedVertexField vertexField,
    required Size imageSize,
    required int vertexCount,
    required Offset dispScale,
  }) {
    const width = 2;
    final safeCount = math.min(vertexCount, mesh.vertices.length ~/ 2);
    final rgba = Uint8List(width * safeCount * 4);
    final invW = imageSize.width > 0 ? 1.0 / imageSize.width : 0.0;
    final invH = imageSize.height > 0 ? 1.0 / imageSize.height : 0.0;

    for (var i = 0; i < safeCount; i++) {
      final vx = mesh.vertices[i * 2];
      final vy = mesh.vertices[i * 2 + 1];
      final d = vertexField.displacementAt(i);

      final posOffset = i * width * 4;
      _writeU16(rgba, posOffset, (vx * invW * 65535).round().clamp(0, 65535));
      _writeU16(
        rgba,
        posOffset + 2,
        (vy * invH * 65535).round().clamp(0, 65535),
      );

      final dispOffset = posOffset + 4;
      _writeSignedUnit(
        rgba,
        dispOffset,
        dispScale.dx > 0 ? d.dx / dispScale.dx : 0,
      );
      _writeSignedUnit(
        rgba,
        dispOffset + 1,
        dispScale.dy > 0 ? d.dy / dispScale.dy : 0,
      );
    }

    return (data: rgba, width: width, height: safeCount);
  }

  static ({Uint8List data, int width, int height}) _packTriIndices({
    required TriMesh mesh,
    required int triangleCount,
  }) {
    const width = 1;
    final rgba = Uint8List(width * triangleCount * 4);
    final maxIdx = math.max(mesh.vertices.length ~/ 2, 1);

    for (var t = 0; t < triangleCount; t++) {
      final o = t * 4;
      rgba[o] = ((mesh.indices[t * 3] / maxIdx) * 255).round().clamp(0, 255);
      rgba[o + 1] =
          ((mesh.indices[t * 3 + 1] / maxIdx) * 255).round().clamp(0, 255);
      rgba[o + 2] =
          ((mesh.indices[t * 3 + 2] / maxIdx) * 255).round().clamp(0, 255);
      rgba[o + 3] = 255;
    }

    return (data: rgba, width: width, height: triangleCount);
  }

  static ({Uint8List data, int width, int height}) _packCellTriMap({
    required FaceMeshCellIndex cellIndex,
    required int triangleCount,
  }) {
    final w = cellIndex.gridWidth;
    final h = cellIndex.gridHeight;
    final rgba = Uint8List(w * h * 4);
    // Codifica tri+1 para que tri=0 não colida com célula vazia (alpha=0).
    final denom = math.max(triangleCount + 1, 2);

    for (var i = 0; i < cellIndex.triangleIndices.length; i++) {
      final tri = cellIndex.triangleIndices[i];
      final o = i * 4;
      if (tri < 0) {
        rgba[o + 3] = 0;
        continue;
      }
      final norm = ((tri + 1) / denom).clamp(0.0, 1.0);
      rgba[o] = (norm * 255).round();
      rgba[o + 3] = 255;
    }

    return (data: rgba, width: w, height: h);
  }

  static void _writeU16(Uint8List rgba, int offset, int value) {
    rgba[offset] = (value >> 8) & 0xFF;
    rgba[offset + 1] = value & 0xFF;
  }

  static void _writeSignedUnit(Uint8List rgba, int offset, double unit) {
    rgba[offset] = ((unit.clamp(-1.0, 1.0) * 0.5 + 0.5) * 255).round().clamp(
          0,
          255,
        );
  }
}

/// Payload GPU para warp facial piecewise-affine (sem grade intermediária).
class FaceMeshGpuPayload {
  const FaceMeshGpuPayload({
    required this.atlas,
    required this.intensity,
    this.influenceMap,
  });

  final FaceMeshGpuAtlas atlas;
  final double intensity;
  final InfluenceMap? influenceMap;

  bool get isIdentity => intensity <= 0;

  factory FaceMeshGpuPayload.build({
    required TriMesh mesh,
    required ConstrainedVertexField vertexField,
    required Size imageSize,
    InfluenceMap? influenceMap,
    required double intensity,
  }) {
    final cellIndex = FaceMeshCellIndex.build(
      mesh: mesh,
      imageSize: imageSize,
    );
    final atlas = FaceMeshGpuAtlas.build(
      mesh: mesh,
      vertexField: vertexField,
      imageSize: imageSize,
      cellIndex: cellIndex,
    );
    return FaceMeshGpuPayload(
      atlas: atlas,
      intensity: intensity,
      influenceMap: influenceMap,
    );
  }
}
