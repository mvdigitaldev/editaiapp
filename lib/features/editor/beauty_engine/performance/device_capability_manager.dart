import 'package:shared_preferences/shared_preferences.dart';

import 'device_capability.dart';
import 'device_capability_benchmark.dart';

/// Resolve tier A/B/C na 1ª abertura do editor e persiste o resultado.
class DeviceCapabilityManager {
  DeviceCapabilityManager({SharedPreferences? preferences})
      : _preferences = preferences;

  static const _prefsTierKey = 'beauty_device_tier_v1';
  static const _prefsBenchmarkMsKey = 'beauty_device_benchmark_ms_v1';

  SharedPreferences? _preferences;
  DeviceCapabilityProfile? _cached;

  DeviceCapabilityProfile? get cachedProfile => _cached;

  Future<DeviceCapabilityProfile> resolve({bool forceBenchmark = false}) async {
    if (_cached != null && !forceBenchmark) {
      return _cached!;
    }

    _preferences ??= await SharedPreferences.getInstance();
    final prefs = _preferences!;

    if (!forceBenchmark) {
      final tierIndex = prefs.getInt(_prefsTierKey);
      final benchmarkMs = prefs.getInt(_prefsBenchmarkMsKey);
      if (tierIndex != null &&
          tierIndex >= 0 &&
          tierIndex < DeviceTier.values.length) {
        _cached = DeviceCapabilityProfile.forTier(
          DeviceTier.values[tierIndex],
          benchmarkMs: benchmarkMs,
        );
        return _cached!;
      }
    }

    final ms = DeviceCapabilityBenchmark.runGuidedFilterMicrobench();
    final profile = DeviceCapabilityBenchmark.profileFromBenchmarkMs(ms);
    await prefs.setInt(_prefsTierKey, profile.tier.index);
    await prefs.setInt(_prefsBenchmarkMsKey, ms);
    _cached = profile;
    return profile;
  }

  /// Para testes — injeta perfil sem persistir.
  void overrideForTests(DeviceCapabilityProfile profile) {
    _cached = profile;
  }

  void clearCache() {
    _cached = null;
  }
}
