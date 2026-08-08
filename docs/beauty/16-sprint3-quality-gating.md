# Sprint 3 — Quality Score, gating e presets adaptativos

Entrega da Fase 3 do SDK facial: análise de qualidade da foto, caps
dinâmicos nos sliders, registry de ferramentas com predicados de gating
(cap. 19) e presets adaptativos offline.

## Escopo entregue

### Face Quality Assessment (cap. 7)

Métricas determinísticas 1× por foto no load:

- Tamanho do rosto (bbox em px)
- Blur (variância do Laplaciano)
- Ruído (high-pass em patch da bochecha)
- Exposição (% clip highlight/shadow)
- White balance (warmth em OKLab)
- Compressão JPEG (blockiness 8×8)
- Pose (yaw/pitch via landmarks)
- Oclusão (landmarks de baixa visibility)

Scores agregados 0..1: `sharpness`, `lighting`, `pose`, `integrity`, `overall`.

Arquivos:
- `lib/features/editor/beauty_engine/quality/face_quality_context.dart`
- `lib/features/editor/beauty_engine/quality/face_quality_assessment.dart`

### Tool Registry + Gating (cap. 12 / cap. 19)

- `ToolDescriptor` + `BeautyToolRegistry` — catálogo face/pele/cor
- `ToolGateEngine` — predicados das fichas A/D (blur, ruído, rosto pequeno,
  yaw, oclusão, compressão)
- `ToolGatePlan.applyToParameters()` — caps na curva do slider (usuário vê
  100%, efeito satura antes)

Arquivos:
- `lib/features/editor/beauty_engine/tools/*`

### Adaptive Presets (cap. 8)

- `AdaptivePresetEngine.modulate()` — base × Quality Score
- Presets: Natural, Estúdio, Suave, Beleza, **Glam** (novo JSON)
- Barra de presets no `/face-retouch-lab`

Arquivo: `lib/features/editor/beauty_engine/presets/adaptive_preset_engine.dart`

### Integração UI + controller

- `BeautyEngineController.assessImageQuality()` + `applyToolGating()`
- Preview/export usam parâmetros gated
- `BeautyAdjustmentsPanel`: esconde sliders desabilitados + hints PT
- Quality reavaliada após detecção de landmarks

## Testes

- `test/beauty_engine/quality/face_quality_assessment_test.dart`
- `test/beauty_engine/tools/tool_gate_engine_test.dart`
- `test/beauty_engine/presets/adaptive_preset_engine_test.dart`

## Critério de saída

| Meta | Status |
|------|--------|
| Quality Score 1× por foto | ✅ |
| Caps dinâmicos (skin_smooth em foto borrada) | ✅ |
| Sliders inviáveis somem com hint | ✅ |
| Presets adaptativos offline | ✅ |
| Registry central de keys | ✅ |

Próximo: **Sprint 5** — máscaras derivadas e Grupo C.
