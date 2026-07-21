# Sprint 25 — Sign-off

**Data:** 2026-07-20  
**Escopo:** Performance hardening conforme `09-performance.md`

## Entregas

- `AdaptivePreviewPolicy` — preview 720p (selfie) / 1080p (foto)
- `TiledExportEngine` — export tiled 2048px para imagens > 8MP
- `ShaderPrewarmService` — prewarm de passes no open do Beauty Editor
- `LandmarkThrottle` — detecção a cada N frames (base para vídeo)
- `BeautyProfiler` — timings por passo
- `WarpCpuRemap.applyGlobal` — warp por tile na exportação
- Integração no `BeautyEngineController` e `BeautyEditorPage`

## Critérios de aceite

- [x] Preview adaptativo por megapixel
- [x] Export tiled > 8MP
- [x] Shader prewarm no editor
- [x] Landmark throttle implementado
- [x] Profiler por passo

## Próximo

Sprint 26 — QA cross-platform
