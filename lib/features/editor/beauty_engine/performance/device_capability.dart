import '../warp/warp_field_builder.dart';

/// Tier de hardware conforme `09-performance.md` (cap. 9).
enum DeviceTier {
  /// Flagship — p95 slider→frame ≤ 33 ms.
  a,

  /// Mid-range — p95 ≤ 66 ms.
  b,

  /// Entry / thermal — p95 ≤ 120 ms, degradação agressiva.
  c,
}

/// Perfil derivado do benchmark + tier persistido.
class DeviceCapabilityProfile {
  const DeviceCapabilityProfile({
    required this.tier,
    required this.previewMaxEdge,
    required this.useFloat16Intermediate,
    required this.guidedFilterPassScale,
    required this.exportTileSizePx,
    required this.faceWarpQualityInteractive,
    required this.sliderToFrameBudgetMs,
    required this.useFaceWarpIsolate,
    required this.preferFfiHotPath,
    required this.sliderDebounceMs,
    this.benchmarkMs,
  });

  final DeviceTier tier;
  final int previewMaxEdge;
  final bool useFloat16Intermediate;
  final double guidedFilterPassScale;
  final int exportTileSizePx;
  final WarpFieldQuality faceWarpQualityInteractive;
  final int sliderToFrameBudgetMs;
  final bool useFaceWarpIsolate;
  final bool preferFfiHotPath;
  final int sliderDebounceMs;
  final int? benchmarkMs;

  static DeviceCapabilityProfile forTier(
    DeviceTier tier, {
    int? benchmarkMs,
  }) {
    switch (tier) {
      case DeviceTier.a:
        return DeviceCapabilityProfile(
          tier: tier,
          previewMaxEdge: 1080,
          useFloat16Intermediate: true,
          guidedFilterPassScale: 1.0,
          exportTileSizePx: 2048,
          faceWarpQualityInteractive: WarpFieldQuality.interactive,
          sliderToFrameBudgetMs: 33,
          useFaceWarpIsolate: false,
          preferFfiHotPath: true,
          sliderDebounceMs: 80,
          benchmarkMs: benchmarkMs,
        );
      case DeviceTier.b:
        return DeviceCapabilityProfile(
          tier: tier,
          previewMaxEdge: 720,
          useFloat16Intermediate: true,
          guidedFilterPassScale: 0.85,
          exportTileSizePx: 1536,
          faceWarpQualityInteractive: WarpFieldQuality.interactive,
          sliderToFrameBudgetMs: 66,
          useFaceWarpIsolate: true,
          preferFfiHotPath: false,
          sliderDebounceMs: 100,
          benchmarkMs: benchmarkMs,
        );
      case DeviceTier.c:
        return DeviceCapabilityProfile(
          tier: tier,
          previewMaxEdge: 540,
          useFloat16Intermediate: false,
          guidedFilterPassScale: 0.7,
          exportTileSizePx: 1024,
          faceWarpQualityInteractive: WarpFieldQuality.interactive,
          sliderToFrameBudgetMs: 120,
          useFaceWarpIsolate: true,
          preferFfiHotPath: false,
          sliderDebounceMs: 120,
          benchmarkMs: benchmarkMs,
        );
    }
  }

  DeviceCapabilityProfile copyWith({
    DeviceTier? tier,
    int? previewMaxEdge,
    int? exportTileSizePx,
    int? sliderDebounceMs,
    int? benchmarkMs,
  }) {
    return DeviceCapabilityProfile(
      tier: tier ?? this.tier,
      previewMaxEdge: previewMaxEdge ?? this.previewMaxEdge,
      useFloat16Intermediate: useFloat16Intermediate,
      guidedFilterPassScale: guidedFilterPassScale,
      exportTileSizePx: exportTileSizePx ?? this.exportTileSizePx,
      faceWarpQualityInteractive: faceWarpQualityInteractive,
      sliderToFrameBudgetMs: sliderToFrameBudgetMs,
      useFaceWarpIsolate: useFaceWarpIsolate,
      preferFfiHotPath: preferFfiHotPath,
      sliderDebounceMs: sliderDebounceMs ?? this.sliderDebounceMs,
      benchmarkMs: benchmarkMs ?? this.benchmarkMs,
    );
  }
}
