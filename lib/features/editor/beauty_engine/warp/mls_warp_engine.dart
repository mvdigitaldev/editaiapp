import 'dart:ui';

import '../models/mesh_region.dart';
import '../models/warp_algorithm.dart';
import '../rendering/gpu_renderer.dart';
import 'control_point_builder.dart';
import 'warp_field_builder.dart';
import 'warp_engine.dart';

/// Implementacao MLS (Moving Least Squares) — algoritmo default.
class MlsWarpEngine implements WarpEngine {
  MlsWarpEngine({
    ControlPointBuilder? controlPointBuilder,
    WarpFieldBuilder? fieldBuilder,
    BodyMultiPassPipeline? multiPassPipeline,
  })  : _controlPointBuilder =
            controlPointBuilder ?? const ControlPointBuilder(),
        _fieldBuilder = fieldBuilder ?? const WarpFieldBuilder(),
        _multiPassPipeline = multiPassPipeline ?? BodyMultiPassPipeline();

  final ControlPointBuilder _controlPointBuilder;
  final WarpFieldBuilder _fieldBuilder;
  final BodyMultiPassPipeline _multiPassPipeline;

  WarpField? _activeField;

  @override
  WarpAlgorithm get algorithm => WarpAlgorithm.mls;

  @override
  WarpField compute(WarpRequest request) {
    final intensity = _resolveIntensity(request);
    if (intensity <= 0) {
      _activeField = WarpField.identity(
        imageSize: request.imageSize,
        region: request.region,
      );
      return _activeField!;
    }

    final controlPoints = _controlPointBuilder.buildForRegion(
      mesh: request.mesh,
      region: request.region,
      intensity: intensity,
      imageSize: request.imageSize,
    );

    _activeField = _fieldBuilder.build(
      controlPoints: controlPoints,
      imageSize: request.imageSize,
      region: request.region,
      intensity: intensity,
    );
    return _activeField!;
  }

  @override
  BodyMultiPassResult? composeBodyMultiPass(BodyMultiPassInput input) {
    if (!input.config.isV2Enabled) {
      return null;
    }
    final result = _multiPassPipeline.run(input);
    _activeField = result.field;
    return result;
  }

  @override
  Future<TextureHandle> applyGPU({
    required TextureHandle input,
    required WarpField field,
    required GPURenderer renderer,
  }) async {
    if (field.isIdentity) {
      return input;
    }

    return renderer.applyPass(
      input: input,
      shaderName: WarpEngine.warpRemapShader,
      uniforms: {'warpField': field},
    );
  }

  /// Reset/undo — retorna campo identidade.
  WarpField reset() {
    final current = _activeField;
    _activeField = WarpField.identity(
      imageSize: current?.imageSize ?? Size.zero,
      region: current?.region ?? MeshRegion.jawLeft,
    );
    return _activeField!;
  }

  WarpField? get activeField => _activeField;

  double _resolveIntensity(WarpRequest request) {
    return request.parameter(
      'face_slim',
      camelCase: 'faceSlim',
      defaultValue: request.parameter('jaw', defaultValue: 0),
    );
  }
}
