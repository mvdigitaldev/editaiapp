import 'device_capability.dart';
import 'thermal_monitor.dart';

/// Parâmetros de export ajustados por thermal + tier.
class ExportDegradationPlan {
  const ExportDegradationPlan({
    required this.tileSizePx,
    required this.jpegQualityReduction,
    required this.skipParallelTiles,
    required this.thermalState,
  });

  final int tileSizePx;
  final int jpegQualityReduction;
  final bool skipParallelTiles;
  final ThermalState thermalState;
}

/// Degrada export quando o dispositivo está quente (cap. 9).
abstract final class ThermalDegradationPolicy {
  static ExportDegradationPlan plan({
    required DeviceCapabilityProfile profile,
    required ThermalState thermal,
  }) {
    var tileSize = profile.exportTileSizePx;
    var qualityReduction = 0;
    var skipParallel = false;

    switch (thermal) {
      case ThermalState.nominal:
        break;
      case ThermalState.fair:
        tileSize = (tileSize * 0.75).round().clamp(512, profile.exportTileSizePx);
        qualityReduction = 2;
        skipParallel = true;
      case ThermalState.serious:
        tileSize = (tileSize * 0.5).round().clamp(512, profile.exportTileSizePx);
        qualityReduction = 5;
        skipParallel = true;
      case ThermalState.critical:
        tileSize = 512;
        qualityReduction = 8;
        skipParallel = true;
    }

    return ExportDegradationPlan(
      tileSizePx: tileSize,
      jpegQualityReduction: qualityReduction,
      skipParallelTiles: skipParallel,
      thermalState: thermal,
    );
  }
}
