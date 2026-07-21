# ADR 003 — Injeção de dependências (Riverpod)

**Status:** Aprovado  
**Sprint:** 01  
**Data:** 2026-07-20

## Contexto

O app usa **flutter_riverpod**. Beauty Engine deve ser testável e desacoplado da UI.

## Decisão

### Providers em `beauty_engine/di/beauty_engine_providers.dart`

```dart
// Exemplo — implementação Sprint 02
final faceMeshDetectorProvider = Provider<FaceMeshDetector>((ref) {
  return FaceMeshDetectorImpl(ref.watch(mediapipeBindingsProvider));
});

final beautyEngineControllerProvider = Provider<BeautyEngineController>((ref) {
  return BeautyEngineController(
    faceDetector: ref.watch(faceMeshDetectorProvider),
    poseDetector: ref.watch(poseDetectorProvider),
    meshEngine: ref.watch(meshEngineProvider),
    warpEngine: ref.watch(warpEngineProvider),
    gpuRenderer: ref.watch(gpuRendererProvider),
  );
});
```

### Regras

1. **UI** (`ConsumerWidget`) → só `ref.watch(beautyEngineControllerProvider)`
2. **Controllers** → recebem interfaces via construtor (sem `ref` interno)
3. **Testes** → `ProviderScope(overrides: [...])` com fakes
4. Manual Editor **não** registra providers beauty até integração Sprint 21

### Localização

`lib/features/editor/beauty_engine/di/` — criado no Sprint 02.

## Consequências

- Consistente com resto do app
- Mock fácil para unit tests do pipeline
