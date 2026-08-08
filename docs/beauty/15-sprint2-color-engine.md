# Sprint 2 — Color engine + memoização por estágio

Entrega da Fase 2 do SDK facial: motor de cor global no Beauty Engine,
memoização pós-warp/pós-pele para sliders de cor responsivos, UI de ajustes
e goldens do Grupo D.

## Escopo entregue

### Motor de cor (`ColorGradeEngine` + `PassColorGrade`)

- Grade Lightroom completa via paridade com `FilterGradeEngine` CPU
  (`filterTuneToColorMatrices` + `TuneParams` / 17 parâmetros).
- Vinheta radial parametrizada.
- Nitidez (unsharp em luminância linear) com **proteção de pele** via
  `SkinWeightMap` quando rosto detectado.
- LUT de preset continua em pass separado (`PassLut`) antes da grade.

Arquivos:

- `lib/features/editor/beauty_engine/filters/color/color_filter_pipeline.dart`
- `lib/features/editor/beauty_engine/filters/color/color_grade_engine.dart`
- `lib/features/editor/beauty_engine/rendering/pass_color_grade.dart`

### Memoização por estágio (`RenderStageCache`)

Quando só parâmetros do Grupo D mudam no preview interativo, o controller
reutiliza a textura pós-warp/pós-pele e executa apenas `color_grade`.

- Chave exclui keys de `ColorFilterPipeline.colorParameterKeys`.
- Preview usa `interactivePreview: true` para ativar o cache.
- `invalidateRenderStageCache()` ao trocar foto.

Arquivo: `lib/features/editor/beauty_engine/rendering/render_stage_cache.dart`

### UI

- Nova categoria **Cor** em `BeautyAdjustmentsPanel` (sliders −1…1,
  temperatura −0.5…0.5).
- Labels PT em `beauty_engine_labels.dart`.
- `BeautyPreset.toParameterMap()` expõe todos os campos de `TuneParams`.

### Testes

- `test/beauty_engine/filters/color/*`
- `test/beauty_engine/rendering/render_stage_cache_test.dart`
- `test/golden/color_group_d_golden_test.dart`

### Fichas Grupo D

Adicionadas em `docs/beauty/13-visual-quality-targets.md` (D1–D3).

## Fora deste sprint (backlog)

- **GPU nativo** dedicado (Metal/GLES) para color grade — CPU/RGBA por
  enquanto; preview já beneficia da memoização.
- **Curvas LUT 1D editáveis** e **HDR/CLAHE** completo — highlights/sombras
  cobertos via matrices; CLAHE entra quando houver toggle dedicado.
- **ICC embutido no export** — continua pendente (ver
  `docs/beauty/12-sprint0-auditoria-exif-icc.md`); encoder nativo no caminho
  de export quando disponível.

## Critério de saída

| Meta | Status |
|------|--------|
| Slider de cor não reexecuta warp/pele no preview | ✅ `RenderStageCache` |
| 17 parâmetros de cor no pipeline | ✅ |
| UI categoria Cor | ✅ |
| Goldens Grupo D | ✅ |
| LUT preset antes da grade | ✅ (ordem mantida) |

## Ordem pós-warp

1. LUT (preset)
2. eyeOverlay, cheekboneContour
3. skinEngine
4. **colorGrade** (novo)

Próximo: **Sprint 3** — Quality Score, presets adaptativos e gating.
