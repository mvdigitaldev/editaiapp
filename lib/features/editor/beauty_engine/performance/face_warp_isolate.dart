import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../filters/face/face_filter_pipeline.dart';
import '../mesh/mesh_engine_impl.dart';
import '../models/face_mesh_result.dart';
import '../models/warp_field.dart';
import '../warp/warp_field_builder.dart';

/// Payload serializável para [compute] — MLS facial fora da UI thread.
class FaceWarpIsolateInput {
  const FaceWarpIsolateInput({
    required this.faceJson,
    required this.imageWidth,
    required this.imageHeight,
    required this.parameters,
    required this.qualityIndex,
    required this.refineForPreview,
  });

  final Map<String, dynamic> faceJson;
  final double imageWidth;
  final double imageHeight;
  final Map<String, double> parameters;
  final int qualityIndex;
  final bool refineForPreview;

  factory FaceWarpIsolateInput.fromCompose({
    required FaceMeshResult face,
    required Size imageSize,
    required Map<String, double> parameters,
    required WarpFieldQuality quality,
    bool refineForPreview = false,
  }) {
    return FaceWarpIsolateInput(
      faceJson: face.toJson(),
      imageWidth: imageSize.width,
      imageHeight: imageSize.height,
      parameters: Map<String, double>.from(parameters),
      qualityIndex: quality.index,
      refineForPreview: refineForPreview,
    );
  }
}

/// Top-level para `compute`.
WarpField? composeFaceFieldIsolate(FaceWarpIsolateInput input) {
  final face = FaceMeshResult.fromJson(input.faceJson);
  final imageSize = Size(input.imageWidth, input.imageHeight);
  final quality = WarpFieldQuality.values[input.qualityIndex.clamp(
    0,
    WarpFieldQuality.values.length - 1,
  )];

  final exporting = quality == WarpFieldQuality.export;
  final pipeline = FaceFilterPipeline(
    fieldBuilder: WarpFieldBuilder.forFaceWarp(
      imageSize,
      exporting: exporting,
    ),
  );

  if (!pipeline.hasActiveWarp(input.parameters)) {
    return null;
  }

  final meshEngine = MeshEngineImpl();
  final mesh = meshEngine.buildFaceMesh(face, imageSize);
  var field = pipeline.compose(
    mesh: mesh,
    face: face,
    imageSize: imageSize,
    parameters: input.parameters,
    unified: false,
  );
  if (exporting) {
    field = field.refinedForRender(exportQuality: true).smoothDisplacement();
  }
  return field;
}

/// Executa MLS facial em isolate quando o perfil pede ou a imagem é grande.
abstract final class FaceWarpIsolateRunner {
  static const isolateMinEdgePx = 640;

  static bool shouldUseIsolate({
    required Size imageSize,
    required WarpFieldQuality quality,
    required bool profilePrefersIsolate,
  }) {
    if (quality == WarpFieldQuality.export) {
      return true;
    }
    if (profilePrefersIsolate) {
      return true;
    }
    final minEdge = imageSize.shortestSide;
    return minEdge >= isolateMinEdgePx;
  }

  static Future<WarpField?> run(FaceWarpIsolateInput input) {
    return compute(composeFaceFieldIsolate, input);
  }
}
