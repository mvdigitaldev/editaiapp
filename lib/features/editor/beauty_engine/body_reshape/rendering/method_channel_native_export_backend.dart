import 'package:flutter/services.dart';

import 'native_export_backend.dart';
import 'render_plan.dart';

/// Backend de export via MethodChannel → Metal (iOS) / Vulkan|GLES (Android).
class MethodChannelNativeExportBackend implements NativeExportBackend {
  MethodChannelNativeExportBackend({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.editaiapp/beauty_mediapipe';

  final MethodChannel _channel;
  ExportWarpCapabilities? _cachedCaps;
  final Set<String> _opaqueIds = {};

  @override
  Future<ExportWarpCapabilities> probe() async {
    if (_cachedCaps != null) {
      return _cachedCaps!;
    }
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'probeExportCapabilities',
      );
      if (raw == null) {
        _cachedCaps = ExportWarpCapabilities.unavailable;
        return _cachedCaps!;
      }
      _cachedCaps = ExportWarpCapabilities(
        metal: raw['metal'] == true,
        vulkan: raw['vulkan'] == true,
        openGlEs: raw['openGlEs'] == true,
        nativeJpegEncode: raw['nativeJpegEncode'] == true,
      );
    } catch (_) {
      // MissingPlugin / binding não inicializado / plataforma sem canal.
      _cachedCaps = ExportWarpCapabilities.unavailable;
    }
    return _cachedCaps!;
  }

  @override
  Future<Uint8List?> warpExport(ExportWarpRequest request) async {
    final caps = await probe();
    if (!caps.hasNativeGpu || request.field.isIdentity) {
      return null;
    }

    final plan = request.plan ??
        RenderPlan.exportBodyReshape(
          field: request.field,
          influenceMap: request.influenceMap,
          protectionMap: request.protectionMap,
          tileOriginX: request.tileOriginX,
          tileOriginY: request.tileOriginY,
          fullWidth: request.resolvedFullWidth,
          fullHeight: request.resolvedFullHeight,
        );
    final payload = NativeWarpPayload.fromPlan(plan);

    try {
      final raw = await _channel.invokeMethod<dynamic>('warpExport', {
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

  @override
  Future<Uint8List?> encodeJpeg({
    required Uint8List rgba,
    required int width,
    required int height,
    int quality = 90,
  }) async {
    final caps = await probe();
    if (!caps.nativeJpegEncode) {
      return null;
    }
    try {
      final raw = await _channel.invokeMethod<dynamic>('encodeJpeg', {
        'rgba': rgba,
        'width': width,
        'height': height,
        'quality': quality,
      });
      return _asUint8List(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> release(OpaqueExportResource resource) async {
    if (!_opaqueIds.remove(resource.id)) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('releaseExportResource', {
        'id': resource.id,
      });
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    }
  }

  @override
  void dispose() {
    _cachedCaps = null;
    _opaqueIds.clear();
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

/// Stub para testes — simula GPU nativa sem MethodChannel.
class FakeNativeExportBackend implements NativeExportBackend {
  FakeNativeExportBackend({
    this.capabilities = const ExportWarpCapabilities(
      metal: true,
      nativeJpegEncode: true,
    ),
    this.warpHandler,
  });

  ExportWarpCapabilities capabilities;
  Future<Uint8List?> Function(ExportWarpRequest request)? warpHandler;
  int warpCallCount = 0;

  @override
  Future<ExportWarpCapabilities> probe() async => capabilities;

  @override
  Future<Uint8List?> warpExport(ExportWarpRequest request) async {
    warpCallCount++;
    if (warpHandler != null) {
      return warpHandler!(request);
    }
    // Ecoa input — valida plumbing sem deformar.
    return Uint8List.fromList(request.rgba);
  }

  @override
  Future<Uint8List?> encodeJpeg({
    required Uint8List rgba,
    required int width,
    required int height,
    int quality = 90,
  }) async {
    if (!capabilities.nativeJpegEncode) {
      return null;
    }
    return Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);
  }

  @override
  Future<void> release(OpaqueExportResource resource) async {}

  @override
  void dispose() {}
}
