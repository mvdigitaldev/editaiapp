import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../body_reshape/rendering/native_export_backend.dart';
import 'face_mesh_export_warp.dart';
import 'face_mesh_native_export_backend.dart';
import 'native_face_mesh_payload.dart';

/// Export piecewise-affine facial via MethodChannel → Metal (iOS) / GLES (Android).
class MethodChannelNativeFaceMeshBackend implements FaceMeshNativeExportBackend {
  MethodChannelNativeFaceMeshBackend({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.editaiapp/beauty_mediapipe';

  final MethodChannel _channel;
  bool? _cachedAvailable;

  Future<bool> get isAvailable async {
    if (_cachedAvailable != null) {
      return _cachedAvailable!;
    }
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'probeExportCapabilities',
      );
      _cachedAvailable =
          raw?['faceMeshMetal'] == true || raw?['faceMeshGles'] == true;
    } catch (_) {
      _cachedAvailable = false;
    }
    return _cachedAvailable!;
  }

  Future<void> initialize() async {
    await isAvailable;
  }

  Future<Uint8List?> apply(FaceMeshExportRequest request) async {
    if (request.payload.isIdentity) {
      return Uint8List.fromList(request.rgba);
    }
    if (!await isAvailable) {
      return null;
    }

    final payload = NativeFaceMeshPayload.fromPayload(
      payload: request.payload,
      protectionMap: request.protectionMap,
    );

    try {
      final raw = await _channel.invokeMethod<dynamic>('faceMeshWarpExport', {
        'rgba': request.rgba,
        'width': request.width,
        'height': request.height,
        'fullWidth': request.resolvedFullWidth,
        'fullHeight': request.resolvedFullHeight,
        'tileOriginX': request.tileOriginX,
        'tileOriginY': request.tileOriginY,
        ...payload.toChannelArgs(),
      });
      return _asUint8List(raw);
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _cachedAvailable = null;
  }

  static Uint8List? _asUint8List(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is Uint8List) {
      return raw;
    }
    if (raw is ByteData) {
      return raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
    }
    if (raw is List<int>) {
      return Uint8List.fromList(raw);
    }
    return null;
  }
}

/// Stub para testes — simula export nativo sem MethodChannel.
class FakeNativeFaceMeshBackend implements FaceMeshNativeExportBackend {
  FakeNativeFaceMeshBackend({
    this.available = true,
    this.handler,
  });

  bool available;
  Future<Uint8List?> Function(FaceMeshExportRequest request)? handler;
  int callCount = 0;
  ExportWarpBackendKind lastBackend = ExportWarpBackendKind.metal;

  Future<bool> get isAvailable async => available;

  Future<void> initialize() async {}

  Future<Uint8List?> apply(FaceMeshExportRequest request) async {
    callCount++;
    if (handler != null) {
      return handler!(request);
    }
    return Uint8List.fromList(request.rgba);
  }

  void dispose() {}
}
