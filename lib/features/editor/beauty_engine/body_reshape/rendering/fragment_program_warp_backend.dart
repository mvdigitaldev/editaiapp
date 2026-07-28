import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../models/warp_field.dart';
import '../../rendering/fragment_program_backend.dart';
import '../maps/influence_map.dart';
import '../protection/rigidity_map.dart';
import 'render_capabilities.dart';
import 'render_plan.dart';
import 'warp_texture.dart';

/// Backend de preview: remap via [ui.FragmentProgram] / Impeller.
///
/// Não faz loop por pixel em Dart. Empacota mapas em texturas, desenha um
/// retângulo com o shader e faz um único readback RGBA para o texture store.
///
/// Fallback: [isAvailable] false ou [apply] → null (PassWarp usa CPU).
class FragmentProgramWarpBackend implements FragmentProgramBackend {
  FragmentProgramWarpBackend({
    this.shaderAsset = BodyReshapeShaders.remap,
    bool forceCpuFallback = false,
  }) : _forceCpuFallback = forceCpuFallback;

  final String shaderAsset;
  bool _forceCpuFallback;
  ui.FragmentProgram? _program;
  bool _initAttempted = false;
  bool _available = false;
  String? _lastError;

  static FragmentProgramWarpBackend? _shared;
  static FragmentProgramWarpBackend get shared =>
      _shared ??= FragmentProgramWarpBackend();

  /// Reinicia o singleton (testes).
  static void resetShared() {
    _shared?.dispose();
    _shared = null;
  }

  @override
  bool get isAvailable => _available && !_forceCpuFallback;

  String? get lastError => _lastError;

  RenderCapabilities get capabilities => RenderCapabilities(
        fragmentProgramWarp: _available,
        forceCpuFallback: _forceCpuFallback,
        protectionMaps: true,
        influenceMaps: true,
      );

  void setForceCpuFallback(bool value) {
    _forceCpuFallback = value;
  }

  @override
  Future<void> initialize() async {
    if (_initAttempted) {
      return;
    }
    _initAttempted = true;

    if (_forceCpuFallback) {
      _available = false;
      return;
    }

    try {
      _program = await ui.FragmentProgram.fromAsset(shaderAsset);
      _available = true;
      _lastError = null;
    } catch (error) {
      _program = null;
      _available = false;
      _lastError = error.toString();
    }
  }

  /// Aplica remap GPU. Retorna null se indisponível ou em falha (fallback CPU).
  Future<Uint8List?> apply({
    required Uint8List rgba,
    required int width,
    required int height,
    required WarpField field,
    InfluenceMap? influenceMap,
    RigidityMap? protectionMap,
  }) async {
    final plan = RenderPlan.previewBodyReshape(
      field: field,
      influenceMap: influenceMap,
      protectionMap: protectionMap ?? field.rigidityMap,
      capabilities: capabilities,
    );
    return applyPlan(
      rgba: rgba,
      width: width,
      height: height,
      plan: plan,
    );
  }

  Future<Uint8List?> applyPlan({
    required Uint8List rgba,
    required int width,
    required int height,
    required RenderPlan plan,
  }) async {
    await initialize();
    if (!isAvailable || plan.isIdentity || _program == null) {
      return null;
    }

    final expected = width * height * 4;
    if (rgba.length != expected || width <= 0 || height <= 0) {
      return null;
    }

    ui.Image? sourceImage;
    ui.Image? displacementImage;
    ui.Image? maskImage;
    ui.Image? influenceImage;
    ui.Image? protectionImage;
    ui.Image? outputImage;

    try {
      final displacement = WarpTexture.fromDisplacement(plan.field);
      final mask = WarpTexture.fromMask(plan.field);
      final influence = plan.hasInfluence
          ? WarpTexture.fromInfluenceMap(plan.influenceMap!)
          : WarpTexture.constant(
              kind: WarpTextureKind.influence,
              imageSize: plan.imageSize,
              value: 1,
            );
      final protection = plan.hasProtection
          ? WarpTexture.fromRigidityMap(plan.protectionMap!)
          : WarpTexture.constant(
              kind: WarpTextureKind.protection,
              imageSize: plan.imageSize,
              value: 0,
            );

      sourceImage = await _imageFromRgba(rgba, width, height);
      displacementImage = await _imageFromRgba(
        displacement.rgba,
        displacement.width,
        displacement.height,
      );
      maskImage = await _imageFromRgba(mask.rgba, mask.width, mask.height);
      influenceImage = await _imageFromRgba(
        influence.rgba,
        influence.width,
        influence.height,
      );
      protectionImage = await _imageFromRgba(
        protection.rgba,
        protection.width,
        protection.height,
      );

      final shader = _program!.fragmentShader();
      shader.setFloat(0, width.toDouble());
      shader.setFloat(1, height.toDouble());
      shader.setImageSampler(0, sourceImage);
      shader.setImageSampler(1, displacementImage);
      shader.setImageSampler(2, maskImage);
      shader.setImageSampler(3, influenceImage);
      shader.setImageSampler(4, protectionImage);

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final paint = ui.Paint()..shader = shader;
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        paint,
      );
      final picture = recorder.endRecording();
      outputImage = await picture.toImage(width, height);
      picture.dispose();
      shader.dispose();

      final byteData =
          await outputImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        return null;
      }
      return byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
    } catch (error) {
      _lastError = error.toString();
      return null;
    } finally {
      sourceImage?.dispose();
      displacementImage?.dispose();
      maskImage?.dispose();
      influenceImage?.dispose();
      protectionImage?.dispose();
      outputImage?.dispose();
    }
  }

  void dispose() {
    _program = null;
    _available = false;
    _initAttempted = false;
  }

  static Future<ui.Image> _imageFromRgba(
    Uint8List rgba,
    int width,
    int height,
  ) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}
