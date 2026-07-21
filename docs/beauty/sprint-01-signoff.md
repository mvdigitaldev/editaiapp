# Sprint 01 — Sign-off

**Sprint:** 01 — Revisão da arquitetura  
**Status:** ✅ Concluída  
**Data:** 2026-07-20

## Objetivo

Validar arquitetura Beauty Engine vs Manual Editor; aprovar estrutura de pastas, contratos e estratégia FFI.

## Entregáveis

| Item | Arquivo | Status |
|------|---------|--------|
| ADR fronteiras Manual ↔ Beauty | [adr/001-beauty-engine-boundaries.md](./adr/001-beauty-engine-boundaries.md) | ✅ |
| ADR FFI MediaPipe | [adr/002-mediapipe-ffi-strategy.md](./adr/002-mediapipe-ffi-strategy.md) | ✅ |
| ADR Riverpod DI | [adr/003-dependency-injection.md](./adr/003-dependency-injection.md) | ✅ |
| Índice ADRs | [adr/README.md](./adr/README.md) | ✅ |
| Sign-off | este documento | ✅ |

## Critérios de aceite

- [x] Documentação `docs/beauty/00–10` revisada
- [x] Desacoplamento UI/engine validado ([001](./adr/001-beauty-engine-boundaries.md))
- [x] FFI path definido Face + Pose ([002](./adr/002-mediapipe-ffi-strategy.md))
- [x] Fase 1 Manual Editor congelada — zero breaking changes
- [x] Plataformas: iOS + Android only (confirmado)

## Revisão docs (00–10)

| Doc | Revisado | Notas |
|-----|----------|-------|
| 00-visao-geral | ✅ | Plataformas nativas OK |
| 01-arquitetura | ✅ | Diagramas aprovados; link ADRs adicionado |
| 02-mediapipe | ✅ | Alinhado ADR 002 |
| 03-mesh | ✅ | Sem alteração |
| 04-warp | ✅ | MLS default OK |
| 05-render | ✅ | Metal + OpenGL ES OK |
| 06-presets | ✅ | Supabase presets Sprint 23 |
| 07-face-filters | ✅ | Mapeamento sprint OK |
| 08-body-filters | ✅ | Mapeamento sprint OK |
| 09-performance | ✅ | Metas mobile OK |
| 10-roadmap | ✅ | Fases OK |

## Ambiente (registro)

| Ferramenta | Versão atual | Nota Fase 1 |
|------------|--------------|-------------|
| Flutter | 3.38.9 | `pro_image_editor` pode exigir ≥3.41 — validar no Sprint Fase 1 / deps |
| Dart | 3.10.8 | Idem — possível bump antes Manual Editor |

## Decisões-chave Sprint 01

1. **`packages/beauty_mediapipe/`** — plugin FFI local para MediaPipe
2. **Ordem implementação:** Android Face → iOS Face → Pose (ambas plataformas)
3. **`manual_editor/` não importa `beauty_engine/`** até integração Sprint 21+
4. **GPU:** Impeller + Metal (iOS) + OpenGL ES (Android)

## Riscos abertos (para sprints seguintes)

| Risco | Owner sprint |
|-------|--------------|
| FFI build MediaPipe | Sprint 03 |
| Flutter/Dart version vs pro_image_editor | Fase 1 Manual Editor |
| APK size (modelos .task) | Sprint 03 |

## Próximo passo

**Sprint 02 — Beauty Engine scaffold**

- Criar `lib/features/editor/beauty_engine/` tree
- Interfaces vazias + `BeautyEngineController` stub
- Skeleton `packages/beauty_mediapipe/`
- Riverpod providers stub em `di/`
