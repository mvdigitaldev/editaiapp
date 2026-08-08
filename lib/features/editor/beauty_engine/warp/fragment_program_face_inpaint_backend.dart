import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../rendering/fragment_program_backend.dart';
import 'face_warp_ghost_mask.dart';
import 'fragment_program_face_mesh_backend.dart';

/// Inpaint pós-warp na GPU (Sprint 38).
class FragmentProgramFaceInpaintBackend implements FragmentProgramBackend {
  FragmentProgramFaceInpaintBackend({
    this.shaderAsset = FaceMeshShaders.inpaint,
    bool forceCpuFallback = false,
  }) : _forceCpuFallback = forceCpuFallback;

  final String shaderAsset;
  bool _forceCpuFallback;
  ui.FragmentProgram? _program;
  bool _initAttempted = false;
  bool _available = false;
  String? _lastError;

  static FragmentProgramFaceInpaintBackend? _shared;
  static FragmentProgramFaceInpaintBackend get shared =>
      _shared ??= FragmentProgramFaceInpaintBackend();

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
    required FaceWarpGhostMask ghostMask,
    required int width,
    required int height,
    double tileOriginX = 0,
    double tileOriginY = 0,
    double? fullWidth,
    double? fullHeight,
  }) async {
    await initialize();
    if (!isAvailable || _program == null) {
      return null;
    }

    final expected = width * height * 4;
    if (rgba.length != expected || width <= 0 || height <= 0) {
      return null;
    }

    ui.Image? sourceImage;
    ui.Image? ghostImage;
    ui.Image? outputImage;

    try {
      sourceImage = await _imageFromRgba(rgba, width, height);
      ghostImage = await _imageFromRgba(
        ghostMask.rgba,
        ghostMask.width,
        ghostMask.height,
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

      shader.setImageSampler(0, sourceImage);
      shader.setImageSampler(1, ghostImage);

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
      ghostImage?.dispose();
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
