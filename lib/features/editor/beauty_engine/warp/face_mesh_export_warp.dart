import 'dart:typed_data';

import '../body_reshape/rendering/native_export_backend.dart';
import '../body_reshape/protection/rigidity_map.dart';
import '../config/face_warp_v3_config.dart';
import '../models/warp_field.dart';
import 'face_mesh_gpu_payload.dart';
import 'face_warp_ghost_mask.dart';
import 'face_warp_post_inpaint.dart';
import 'fragment_program_face_inpaint_backend.dart';
import 'fragment_program_face_mesh_backend.dart';
import 'face_mesh_native_export_backend.dart';
import 'method_channel_native_face_mesh_backend.dart';

/// Export / tiled remap facial piecewise-affine (Sprint 38–39).
class FaceMeshExportWarp {
  FaceMeshExportWarp({
    FragmentProgramFaceMeshBackend? meshBackend,
    FragmentProgramFaceInpaintBackend? inpaintBackend,
    FaceMeshNativeExportBackend? nativeBackend,
  })  : _meshBackend = meshBackend ?? FragmentProgramFaceMeshBackend.shared,
        _inpaintBackend = inpaintBackend ?? FragmentProgramFaceInpaintBackend.shared,
        _nativeBackend = nativeBackend ?? MethodChannelNativeFaceMeshBackend();

  final FragmentProgramFaceMeshBackend _meshBackend;
  final FragmentProgramFaceInpaintBackend _inpaintBackend;
  final FaceMeshNativeExportBackend _nativeBackend;

  ExportWarpBackendKind? lastBackend;
  bool lastUsedCpuFallback = false;

  Future<ExportWarpResult?> apply(FaceMeshExportRequest request) async {
    if (request.payload.isIdentity) {
      return ExportWarpResult(
        rgba: Uint8List.fromList(request.rgba),
        width: request.width,
        height: request.height,
        backend: ExportWarpBackendKind.fragmentProgram,
      );
    }

    Uint8List? rgba;
    ExportWarpBackendKind backend = ExportWarpBackendKind.fragmentProgram;

    if (FaceWarpV3Config.useNativePiecewiseExport) {
      await _nativeBackend.initialize();
      if (await _nativeBackend.isAvailable) {
        rgba = await _nativeBackend.apply(request);
        if (rgba != null && rgba.length == request.rgba.length) {
          backend = ExportWarpBackendKind.metal;
        } else {
          rgba = null;
        }
      }
    }

    if (rgba == null) {
      await _meshBackend.initialize();
      if (!_meshBackend.isAvailable) {
        return null;
      }

      rgba = await _meshBackend.apply(
        rgba: request.rgba,
        width: request.width,
        height: request.height,
        payload: request.payload,
        protectionMap: request.protectionMap,
        tileOriginX: request.tileOriginX,
        tileOriginY: request.tileOriginY,
        fullWidth: request.resolvedFullWidth,
        fullHeight: request.resolvedFullHeight,
      );
      backend = ExportWarpBackendKind.fragmentProgram;

      if (rgba == null || rgba.length != request.rgba.length) {
        return null;
      }
    }

    if (request.applyInpaint &&
        request.field != null &&
        !request.field!.isIdentity) {
      rgba = await _applyInpaint(request, rgba);
    }

    lastBackend = backend;
    lastUsedCpuFallback = false;
    return ExportWarpResult(
      rgba: rgba,
      width: request.width,
      height: request.height,
      backend: backend,
    );
  }

  Future<Uint8List> _applyInpaint(
    FaceMeshExportRequest request,
    Uint8List rgba,
  ) async {
    final field = request.field!;
    final useGpu = FaceWarpV3Config.useGpuInpaint && !request.forceCpuInpaint;

    if (useGpu) {
      await _inpaintBackend.initialize();
      if (_inpaintBackend.isAvailable) {
        final ghost = FaceWarpGhostMask.buildRgba(
          field: field,
          influenceMap: request.payload.influenceMap,
          parameters: request.parameters,
        );
        if (ghost != null) {
          final gpu = await _inpaintBackend.apply(
            rgba: rgba,
            ghostMask: ghost,
            width: request.width,
            height: request.height,
            tileOriginX: request.tileOriginX,
            tileOriginY: request.tileOriginY,
            fullWidth: request.resolvedFullWidth,
            fullHeight: request.resolvedFullHeight,
          );
          if (gpu != null) {
            return gpu;
          }
        }
      }
    }

    return FaceWarpPostInpaint.apply(
      rgba: rgba,
      width: request.width,
      height: request.height,
      field: field,
      influenceMap: request.payload.influenceMap,
      parameters: request.parameters,
    );
  }
}

class FaceMeshExportRequest {
  const FaceMeshExportRequest({
    required this.rgba,
    required this.width,
    required this.height,
    required this.payload,
    this.field,
    this.protectionMap,
    this.parameters = const {},
    this.tileOriginX = 0,
    this.tileOriginY = 0,
    this.fullWidth,
    this.fullHeight,
    this.applyInpaint = false,
    this.forceCpuInpaint = false,
  });

  final Uint8List rgba;
  final int width;
  final int height;
  final FaceMeshGpuPayload payload;
  final WarpField? field;
  final RigidityMap? protectionMap;
  final Map<String, double> parameters;
  final double tileOriginX;
  final double tileOriginY;
  final double? fullWidth;
  final double? fullHeight;
  final bool applyInpaint;
  final bool forceCpuInpaint;

  double get resolvedFullWidth => fullWidth ?? width.toDouble();
  double get resolvedFullHeight => fullHeight ?? height.toDouble();
}
