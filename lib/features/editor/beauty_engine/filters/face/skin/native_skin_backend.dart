import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'skin_retouch_engine.dart';

/// Capacidades do backend nativo de pele (Metal / GLES / CPU nativo).
class NativeSkinCapabilities {
  const NativeSkinCapabilities({
    this.skinRetouch = false,
    this.skinGpu = false,
  });

  final bool skinRetouch;
  final bool skinGpu;

  static const unavailable = NativeSkinCapabilities();
}

/// Contrato do backend nativo de retoque de pele (Sprint 1).
abstract class NativeSkinBackend {
  Future<NativeSkinCapabilities> probe();

  /// Retorna RGBA processado, ou null se indisponível (caller usa CPU Dart).
  Future<Uint8List?> skinRetouch(SkinRetouchRequest request);

  void dispose();
}

/// MethodChannel → Metal (iOS) / GLES|CPU nativo (Android).
class MethodChannelNativeSkinBackend implements NativeSkinBackend {
  MethodChannelNativeSkinBackend({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.editaiapp/beauty_mediapipe';

  final MethodChannel _channel;
  NativeSkinCapabilities? _cached;

  @override
  Future<NativeSkinCapabilities> probe() async {
    if (_cached != null) return _cached!;
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'probeExportCapabilities',
      );
      if (raw == null) {
        _cached = NativeSkinCapabilities.unavailable;
        return _cached!;
      }
      _cached = NativeSkinCapabilities(
        skinRetouch: raw['skinRetouch'] == true,
        skinGpu: raw['skinGpu'] == true,
      );
    } catch (_) {
      _cached = NativeSkinCapabilities.unavailable;
    }
    return _cached!;
  }

  @override
  Future<Uint8List?> skinRetouch(SkinRetouchRequest request) async {
    final caps = await probe();
    if (!caps.skinRetouch || request.params.isNoop) {
      return null;
    }

    final underEye = request.underEyeWeights.length ==
            request.width * request.height
        ? request.underEyeWeights
        : Uint8List(request.width * request.height);

    try {
      final raw = await _channel.invokeMethod<dynamic>('skinRetouchExport', {
        'rgba': request.rgba,
        'width': request.width,
        'height': request.height,
        'skinWeights': request.skinWeights,
        'underEyeWeights': underEye,
        'smooth': request.params.smooth,
        'acne': request.params.acne,
        'wrinkles': request.params.wrinkles,
        'darkCircles': request.params.darkCircles,
        'shine': request.params.shine,
        'faceEdgePx': request.faceEdgePx,
      });
      return _asUint8List(raw);
    } catch (error, stack) {
      debugPrint('skinRetouchExport falhou, fallback CPU: $error\n$stack');
      return null;
    }
  }

  @override
  void dispose() {
    _cached = null;
  }

  static Uint8List? _asUint8List(Object? raw) {
    if (raw == null) return null;
    if (raw is Uint8List) return raw;
    if (raw is ByteData) {
      return raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
    }
    if (raw is List<int>) return Uint8List.fromList(raw);
    return null;
  }
}

/// Stub para testes.
class FakeNativeSkinBackend implements NativeSkinBackend {
  FakeNativeSkinBackend({
    this.capabilities = const NativeSkinCapabilities(
      skinRetouch: true,
      skinGpu: true,
    ),
    this.handler,
  });

  NativeSkinCapabilities capabilities;
  Future<Uint8List?> Function(SkinRetouchRequest request)? handler;
  int callCount = 0;

  @override
  Future<NativeSkinCapabilities> probe() async => capabilities;

  @override
  Future<Uint8List?> skinRetouch(SkinRetouchRequest request) async {
    callCount++;
    if (handler != null) return handler!(request);
    return Uint8List.fromList(request.rgba);
  }

  @override
  void dispose() {}
}
