import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Capacidades do hot path nativo (FFI + memória compartilhada).
class HotPathCapabilities {
  const HotPathCapabilities({
    required this.ffiAvailable,
    required this.sharedMemorySupported,
  });

  final bool ffiAvailable;
  final bool sharedMemorySupported;

  bool get isReady => ffiAvailable && sharedMemorySupported;

  factory HotPathCapabilities.fromMap(Map<dynamic, dynamic> raw) {
    return HotPathCapabilities(
      ffiAvailable: raw['ffiAvailable'] == true,
      sharedMemorySupported: raw['sharedMemorySupported'] == true,
    );
  }

  static const unavailable = HotPathCapabilities(
    ffiAvailable: false,
    sharedMemorySupported: false,
  );
}

/// Abstração do caminho slider→frame sem MethodChannel no hot path (Sprint 6).
///
/// Implementação atual delega ao pipeline GPU existente; FFI entra quando
/// [HotPathCapabilities.isReady] for true no nativo.
abstract class HotPathRenderer {
  Future<HotPathCapabilities> probeCapabilities();

  /// Prepara buffer RGBA para upload nativo/GPU — evita cópias extras quando
  /// FFI estiver ativo.
  Future<Uint8List> preparePreviewBuffer(Uint8List rgba);
}

/// Fallback MethodChannel — preparação zero-copy best-effort (view do buffer).
class MethodChannelHotPathRenderer implements HotPathRenderer {
  MethodChannelHotPathRenderer({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.editaiapp/beauty_mediapipe';

  final MethodChannel _channel;
  HotPathCapabilities _caps = HotPathCapabilities.unavailable;
  bool _probed = false;

  @override
  Future<HotPathCapabilities> probeCapabilities() async {
    if (_probed) {
      return _caps;
    }
    try {
      final raw = await _channel.invokeMethod<dynamic>('probeHotPathCapabilities');
      if (raw is Map) {
        _caps = HotPathCapabilities.fromMap(raw);
      }
    } catch (_) {
      _caps = HotPathCapabilities.unavailable;
    }
    _probed = true;
    return _caps;
  }

  @override
  Future<Uint8List> preparePreviewBuffer(Uint8List rgba) async {
    await probeCapabilities();
    // FFI futuro: registrar buffer externo e retornar handle.
    // Hoje: view direta — sem cópia defensiva no caminho quente.
    return rgba;
  }
}
