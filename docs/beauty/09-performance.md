# Performance

## Metas

| Métrica | Preview | Export |
|---------|---------|--------|
| Selfie 720p | ≥ 24 FPS | N/A |
| Foto 4MP | ≥ 15 FPS | < 1.5s |
| Foto 12MP | ≥ 8 FPS ou tiled | < 3s |
| Memória pico | < 512 MB mid-range | < 768 MB export |

## Estratégias

### 1. Resolução adaptativa
- Preview: max 1080p long edge
- Export: resolução original, processamento tiled se > 8MP

### 2. Pipeline lazy
- Só executar passes com intensity > 0
- Skip body filters se pose confidence < threshold

### 3. Cache
- Mesh cache por landmark hash
- Shader program cache (compile once)
- LUT texture upload once per preset

### 4. Isolates / threads
- MediaPipe em thread nativa
- MLS field compute em isolate para export
- GPU work no render thread

### 5. Landmark throttling (video)
- Detect every N frames; interpolate between

## Profiling

| Ferramenta | Uso |
|------------|-----|
| Flutter DevTools Timeline | Frame budget |
| Android GPU Profiler | Shader cost |
| Instruments (iOS) | Metal timings |
| Custom `BeautyProfiler` | Per-pass ms logging |

## Sprint 25 — Performance

Consolidar todas otimizações; benchmarks em device matrix:
- Android mid (Snapdragon 6xx)
- Android high (Snapdragon 8xx)
- iPhone 12+
- iPhone SE 3

## Riscos

| Risco | Mitigação |
|-------|-----------|
| OOM 12MP | Tile export 2048px chunks |
| Thermal throttle | Reduzir preview FPS |
| Shader compile jank | Prewarm on editor open |
