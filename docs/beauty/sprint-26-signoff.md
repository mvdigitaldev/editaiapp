# Sprint 26 — Sign-off

**Data:** 2026-07-21  
**Escopo:** QA cross-platform — regressão automatizada + acessibilidade sliders

## Entregas

- `BeautyAccessibleSlider` — rótulo, valor %, semântica TalkBack/VoiceOver, overlay 48dp
- Integração em `PresetCreatorPage` e `FaceFiltersDemoPage`
- Suite de regressão `test/beauty_engine/regression/beauty_engine_regression_test.dart`
- Testes widget de acessibilidade `test/beauty_engine/presentation/beauty_accessible_slider_test.dart`
- Matriz manual 22 dispositivos: [sprint-26-qa-matrix.md](./sprint-26-qa-matrix.md)

## Suite automatizada

| Área | Testes |
|------|--------|
| Face filters (todos os keys) | ✅ |
| Body filters (todos os keys) | ✅ |
| Skin filters | ✅ |
| Bundled presets (8) + JSON round-trip | ✅ |
| Preset sync LWW | ✅ |
| Performance policy (720p/1080p/tiled) | ✅ |
| Controller stub path | ✅ |
| Acessibilidade sliders | ✅ |

## Critérios de aceite

- [x] Regression suite automated
- [x] Accessibility sliders (Semantics + valor visível)
- [x] Matriz QA iOS + Android documentada (22 devices)
- [x] Zero P0 na suite automatizada
- [ ] ≤ 3 P1 bugs documentados — *pendente execução manual da matriz em devices físicos*

## Bugs conhecidos (P1)

| ID | Descrição | Plataforma | Workaround |
|----|-----------|------------|------------|
| — | Nenhum P1 identificado na suite automatizada | — | — |

> Preencher após rodar [sprint-26-qa-matrix.md](./sprint-26-qa-matrix.md) em dispositivos reais.

## Próximo

Sprint 27 — Release (`beauty_engine_enabled`, rollout gradual)
