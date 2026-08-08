import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../body_reshape/protection/rigidity_map.dart';
import '../body_reshape/rendering/warp_texture.dart';
import '../rendering/fragment_program_backend.dart';
import 'face_mesh_gpu_payload.dart';

/// Backend GPU piecewise-affine na malha facial (Sprint 37).
class FragmentProgramFaceMeshBackend implements FragmentProgramBackend {
  FragmentProgramFaceMeshBackend({
    this.shaderAsset = FaceMeshShaders.piecewise,
    bool forceCpuFallback = false,
  }) : _forceCpuFallback = forceCpuFallback;

  final String shaderAsset;
  bool _forceCpuFallback;
  ui.FragmentProgram? _program;
  bool _initAttempted = false;
  bool _available = false;
  String? _lastError;

  static FragmentProgramFaceMeshBackend? _shared;
  static FragmentProgramFaceMeshBackend get shared =>
      _shared ??= FragmentProgramFaceMeshBackend();

  static void resetShared() {
    _shared?.dispose();
    _shared = null;
  }

  @override
  bool get isAvailable => _available && !_forceCpuFallback;

  String? get lastError => _lastError;

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

  Future<Uint8List?> apply({
    required Uint8List rgba,
    required int width,
    required int height,
    required FaceMeshGpuPayload payload,
    RigidityMap? protectionMap,
    double tileOriginX = 0,
    double tileOriginY = 0,
    double? fullWidth,
    double? fullHeight,
  }) async {
    await initialize();
    if (!isAvailable || payload.isIdentity || _program == null) {
      return null;
    }

    final expected = width * height * 4;
    if (rgba.length != expected || width <= 0 || height <= 0) {
      return null;
    }

    final atlas = payload.atlas;
    ui.Image? sourceImage;
    ui.Image? influenceImage;
    ui.Image? protectionImage;
    ui.Image? cellTriImage;
    ui.Image? vertexDataImage;
    ui.Image? triIndexImage;
    ui.Image? outputImage;

    try {
      final influence = payload.influenceMap != null &&
              !payload.influenceMap!.isEmpty
          ? WarpTexture.fromInfluenceMap(payload.influenceMap!)
          : WarpTexture.constant(
              kind: WarpTextureKind.influence,
              imageSize: atlas.imageSize,
              value: 1,
            );
      final protection = protectionMap != null && !protectionMap.isEmpty
          ? WarpTexture.fromRigidityMap(protectionMap)
          : WarpTexture.constant(
              kind: WarpTextureKind.protection,
              imageSize: atlas.imageSize,
              value: 0,
            );

      sourceImage = await _imageFromRgba(rgba, width, height);
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
      cellTriImage = await _imageFromRgba(
        atlas.cellTriData,
        atlas.cellTriWidth,
        atlas.cellTriHeight,
      );
      vertexDataImage = await _imageFromRgba(
        atlas.vertexData,
        atlas.vertexDataWidth,
        atlas.vertexDataHeight,
      );
      triIndexImage = await _imageFromRgba(
        atlas.triIndexData,
        atlas.triIndexWidth,
        atlas.triIndexHeight,
      );

      final shader = _program!.fragmentShader();
      final fw = fullWidth ?? width.toDouble();
      final fh = fullHeight ?? height.toDouble();

      shader.setFloat(0, fw);
      shader.setFloat(1, fh);
      shader.setFloat(2, tileOriginX);
      shader.setFloat(3, tileOriginY);
      shader.setFloat(4, width.toDouble());
      shader.setFloat(5, height.toDouble());
      shader.setFloat(6, atlas.cellTriWidth.toDouble());
      shader.setFloat(7, atlas.cellTriHeight.toDouble());
      shader.setFloat(8, atlas.cellSize);
      shader.setFloat(9, atlas.vertexCount.toDouble());
      shader.setFloat(10, atlas.triangleCount.toDouble());
      shader.setFloat(11, atlas.displacementScalePx.dx);
      shader.setFloat(12, atlas.displacementScalePx.dy);

      shader.setImageSampler(0, sourceImage);
      shader.setImageSampler(1, influenceImage);
      shader.setImageSampler(2, protectionImage);
      shader.setImageSampler(3, cellTriImage);
      shader.setImageSampler(4, vertexDataImage);
      shader.setImageSampler(5, triIndexImage);

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
      influenceImage?.dispose();
      protectionImage?.dispose();
      cellTriImage?.dispose();
      vertexDataImage?.dispose();
      triIndexImage?.dispose();
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

abstract final class FaceMeshShaders {
  static const piecewise =
      'lib/features/editor/beauty_engine/shaders/face_mesh_piecewise.frag';
  static const inpaint =
      'lib/features/editor/beauty_engine/shaders/face_warp_inpaint.frag';
}
