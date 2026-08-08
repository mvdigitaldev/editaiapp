import 'package:flutter/services.dart';

/// Estado térmico reportado pelo SO (Android PowerManager / iOS ProcessInfo).
enum ThermalState {
  nominal,
  fair,
  serious,
  critical,
}

/// Monitor de thermal throttling para degradação de export.
abstract class ThermalMonitor {
  Future<ThermalState> currentState();
}

/// Stub para testes e desktop.
class ThermalMonitorStub implements ThermalMonitor {
  ThermalMonitorStub({this.state = ThermalState.nominal});

  ThermalState state;

  @override
  Future<ThermalState> currentState() async => state;
}

/// Consulta `getThermalState` no plugin beauty_mediapipe.
class PlatformThermalMonitor implements ThermalMonitor {
  PlatformThermalMonitor({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.editaiapp/beauty_mediapipe';

  final MethodChannel _channel;

  @override
  Future<ThermalState> currentState() async {
    try {
      final raw = await _channel.invokeMethod<String>('getThermalState');
      return _parse(raw);
    } catch (_) {
      return ThermalState.nominal;
    }
  }

  static ThermalState _parse(String? raw) {
    switch (raw) {
      case 'fair':
        return ThermalState.fair;
      case 'serious':
        return ThermalState.serious;
      case 'critical':
        return ThermalState.critical;
      default:
        return ThermalState.nominal;
    }
  }
}
