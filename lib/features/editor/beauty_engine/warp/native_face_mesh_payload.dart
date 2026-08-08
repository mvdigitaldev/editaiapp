import 'dart:ui';

import '../body_reshape/protection/rigidity_map.dart';
import '../body_reshape/rendering/warp_texture.dart';
import 'face_mesh_gpu_payload.dart';

/// Empacota [FaceMeshGpuPayload] para export nativo (Metal / GLES).
class NativeFaceMeshPayload {
  const NativeFaceMeshPayload({
    required this.vertexData,
    required this.vertexDataWidth,
    required this.vertexDataHeight,
    required this.triIndexData,
    required this.triIndexWidth,
    required this.triIndexHeight,
    required this.cellTriData,
    required this.cellTriWidth,
    required this.cellTriHeight,
    required this.imageWidth,
    required this.imageHeight,
    required this.cellSize,
    required this.vertexCount,
    required this.triangleCount,
    required this.displacementScaleX,
    required this.displacementScaleY,
    required this.influenceRgba,
    required this.influenceWidth,
    required this.influenceHeight,
    required this.protectionRgba,
    required this.protectionWidth,
    required this.protectionHeight,
  });

  final List<int> vertexData;
  final int vertexDataWidth;
  final int vertexDataHeight;

  final List<int> triIndexData;
  final int triIndexWidth;
  final int triIndexHeight;

  final List<int> cellTriData;
  final int cellTriWidth;
  final int cellTriHeight;

  final double imageWidth;
  final double imageHeight;
  final double cellSize;
  final int vertexCount;
  final int triangleCount;
  final double displacementScaleX;
  final double displacementScaleY;

  final List<int> influenceRgba;
  final int influenceWidth;
  final int influenceHeight;

  final List<int> protectionRgba;
  final int protectionWidth;
  final int protectionHeight;

  factory NativeFaceMeshPayload.fromPayload({
    required FaceMeshGpuPayload payload,
    RigidityMap? protectionMap,
  }) {
    final atlas = payload.atlas;
    final imageSize = atlas.imageSize;

    final influence = payload.influenceMap != null &&
            !payload.influenceMap!.isEmpty
        ? WarpTexture.fromInfluenceMap(payload.influenceMap!)
        : WarpTexture.constant(
            kind: WarpTextureKind.influence,
            imageSize: imageSize,
            value: 1,
          );
    final protection = protectionMap != null && !protectionMap.isEmpty
        ? WarpTexture.fromRigidityMap(protectionMap)
        : WarpTexture.constant(
            kind: WarpTextureKind.protection,
            imageSize: imageSize,
            value: 0,
          );

    return NativeFaceMeshPayload(
      vertexData: atlas.vertexData,
      vertexDataWidth: atlas.vertexDataWidth,
      vertexDataHeight: atlas.vertexDataHeight,
      triIndexData: atlas.triIndexData,
      triIndexWidth: atlas.triIndexWidth,
      triIndexHeight: atlas.triIndexHeight,
      cellTriData: atlas.cellTriData,
      cellTriWidth: atlas.cellTriWidth,
      cellTriHeight: atlas.cellTriHeight,
      imageWidth: imageSize.width,
      imageHeight: imageSize.height,
      cellSize: atlas.cellSize,
      vertexCount: atlas.vertexCount,
      triangleCount: atlas.triangleCount,
      displacementScaleX: atlas.displacementScalePx.dx,
      displacementScaleY: atlas.displacementScalePx.dy,
      influenceRgba: influence.rgba,
      influenceWidth: influence.width,
      influenceHeight: influence.height,
      protectionRgba: protection.rgba,
      protectionWidth: protection.width,
      protectionHeight: protection.height,
    );
  }

  Map<String, Object> toChannelArgs() => {
        'vertexData': vertexData,
        'vertexDataWidth': vertexDataWidth,
        'vertexDataHeight': vertexDataHeight,
        'triIndexData': triIndexData,
        'triIndexWidth': triIndexWidth,
        'triIndexHeight': triIndexHeight,
        'cellTriData': cellTriData,
        'cellTriWidth': cellTriWidth,
        'cellTriHeight': cellTriHeight,
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
        'cellSize': cellSize,
        'vertexCount': vertexCount,
        'triangleCount': triangleCount,
        'displacementScaleX': displacementScaleX,
        'displacementScaleY': displacementScaleY,
        'influence': influenceRgba,
        'influenceWidth': influenceWidth,
        'influenceHeight': influenceHeight,
        'protection': protectionRgba,
        'protectionWidth': protectionWidth,
        'protectionHeight': protectionHeight,
      };
}
