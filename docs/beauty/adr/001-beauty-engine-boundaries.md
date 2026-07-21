# ADR 001 — Fronteiras Manual Editor ↔ Beauty Engine

**Status:** Aprovado  
**Sprint:** 01  
**Data:** 2026-07-20

## Contexto

O editaiapp é um app **nativo iOS + Android** com edição IA via Supabase. A **Fase 1** adiciona o **Manual Editor** (`manual_editor/`). A **Fase 2+** adiciona o **Beauty Engine** (`beauty_engine/`) — motor de warp facial/corporal open source.

Precisamos de fronteiras claras para evitar acoplamento, regressões na Fase 1 e scope creep.

## Decisão

### 1. Dois módulos irmãos sob `lib/features/editor/`

```
lib/features/editor/
├── manual_editor/     # Fase 1 — CONGELADO até release Fase 1
├── beauty_engine/     # Fase 2+ — Sprint 02 em diante
└── (existente)        # páginas IA, comparison, etc. — intocados
```

### 2. Regra de dependência (import)

| De | Pode importar |
|----|----------------|
| `manual_editor/` | `core/`, pacotes pub, **não** `beauty_engine/` |
| `beauty_engine/` | `core/`, pacotes pub, **não** `material.dart` em `mesh/`, `warp/`, `filters/`, `rendering/` |
| `beauty_engine/controllers/` | `flutter/foundation.dart` permitido; **não** `material.dart` |
| UI futura (`beauty_ui/` ou pages) | `beauty_engine/controllers/`, `material.dart` |

**Lint futuro (Sprint 02):** `analysis_options.yaml` — forbid import de `flutter/material.dart` em subpastas core do engine.

### 3. Fase 1 Manual Editor — escopo congelado

Inalterado até release Fase 1:

- `pro_image_editor` + `flutter_image_filters`
- LUTs, crop, rotação, tune
- Edge Function `salvar-edicao-manual`
- `operation_type = manual_edit`
- Fluxo: export → nuvem automática → `/comparison` → download

**Proibido na Fase 1:** importar `beauty_engine/`, MediaPipe, warp, face slim.

### 4. Persistência

| Fase | Operação | Backend |
|------|----------|---------|
| Fase 1 Manual | `manual_edit` | `edits` + `flux-imagens` (existente) |
| Fase 2+ Beauty (futuro) | `beauty_edit` ou composição sobre manual | Sprint 23+ |

Beauty Engine **não chama Supabase diretamente** — repositórios injetados na camada UI/data.

### 5. Plataformas

**Somente iOS + Android.** Sem código Web/Desktop/WASM.

### 6. Integração futura (pós Sprint 21)

Opções aprovadas (escolha na Sprint 21):

- **A)** `BeautyEditorPage` dedicada
- **B)** Manual Editor chama `BeautyEngineController` antes do export
- **C)** Pipeline unificado na mesma tela com abas Retoque / Filtros

## Consequências

### Positivas

- Fase 1 pode shipar independentemente
- Beauty Engine testável sem Widget
- Times/agentes podem trabalhar em paralelo após Fase 1

### Negativas

- Duplicação temporária de LUT path (Manual `ExportPipeline` vs Beauty `LutEngine` Sprint 09) — unificar no Sprint 09

## Critérios de aceite (Sprint 01)

- [x] Fronteiras documentadas
- [x] Fase 1 congelada explicitamente
- [x] Regras de import definidas
