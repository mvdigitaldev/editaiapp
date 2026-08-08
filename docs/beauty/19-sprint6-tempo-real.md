# Sprint 6 — Tempo real, FFI e performance

## Objetivo

Fechar o loop **slider → frame** com latência previsível por tier de hardware,
MLS facial fora da UI thread, degradação térmica no export e base de medição
para comparar com Banuba (cap. 18–19 do plano SDK facial).

## Entregas

### Device Capability Manager

- **`DeviceTier`** A / B / C com perfis em `device_capability.dart`
- **`DeviceCapabilityBenchmark`** — guided filter 512×512 na 1ª abertura do editor
- **`DeviceCapabilityManager`** — persiste tier em `SharedPreferences`
- Integração na **`BeautyEditorPage`**: preview max edge e debounce por tier

| Tier | p95 budget | Preview max edge | Export tiles | MLS isolate |
|------|------------|------------------|--------------|-------------|
| A    | 33 ms      | 1080             | 2048         | opcional    |
| B    | 66 ms      | 720              | 1536         | sim         |
| C    | 120 ms     | 540              | 1024         | sim         |

### MLS em isolate

- **`FaceWarpIsolateRunner`** — `compute()` para `WarpFieldBuilder.build()`
- **`BeautyEngineController.composeFaceFieldAsync`** — usado em preview e export tiled
- Profiler stage: `face_warp_isolate`

### Thermal degradation (export)

- **`ThermalMonitor`** + `getThermalState` nativo (Android PowerManager / iOS ProcessInfo)
- **`ThermalDegradationPolicy`** — reduz tile size e qualidade JPEG quando quente
- **`TiledExportEngine`** consulta thermal antes do loop de tiles

### Hot path FFI (preparação)

- **`HotPathRenderer`** — interface FFI-ready
- **`MethodChannelHotPathRenderer`** — fallback atual
- **`probeHotPathCapabilities`** nativo — retorna `ffiAvailable: false` até migração

### Performance budgets

- **`PerformanceBudgetPolicy`** — limites p95 por tier
- Badge de ms no editor usa `sliderToFrameBudgetMs` do perfil (33/66/120)
- **`BeautyBenchmarkAggregator`** continua agregando por estágio (log a cada 20 frames)

## Providers (Riverpod)

- `deviceCapabilityManagerProvider`
- `deviceCapabilityProfileProvider`
- `thermalMonitorProvider`
- `hotPathRendererProvider`

## Testes

```bash
flutter test test/beauty_engine/performance/
```

- `device_capability_test.dart` — tiers, thermal, budgets
- `face_warp_isolate_test.dart` — paridade sync vs isolate

## Critério de saída

- [ ] p95 slider→frame dentro do budget do tier em device matrix
- [ ] Sessão longa (100 sliders + 10 exports) sem crescimento de RSS
- [ ] Export tiled respeita degradação térmica
- [ ] FFI hot path habilitável sem refactor da UI (stub → implementação nativa)

## Próximo

**Sprint 7** — multi-rosto, swap Banuba via feature flag, telemetria de rollout.
Ver `docs/beauty/20-sprint7-swap-banuba.md`.
