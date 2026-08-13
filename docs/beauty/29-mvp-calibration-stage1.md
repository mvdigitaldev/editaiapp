# Etapa 1 — Diagnóstico MVP (somente leitura)

Harness e diagnóstico **sem alteração de produção**.

## Executar

```bash
flutter test test/beauty_engine/warp/mvp_calibration_stage1_test.dart
```

## Artefatos gerados

Diretório: `.cursor/mvp-calibration-stage1/`

| Arquivo | Conteúdo |
|---------|----------|
| `mvp-calibration-stage1-summary.json` | Métricas completas por ferramenta/intensidade |
| `mvp-calibration-stage1-report.md` | Relatório tabular |
| `heatmap-{tool}-i1.0.png` | Heatmap de displacement (Phase 9 @1.0) |

## Estágios medidos

1. **Generator** — pilot deltas + semiRigid, sem clamp/anti-fold
2. **ACE** — `composeVertexField(applyStructuralPipeline: false)`
3. **Phase9** — `FaceWarpStructuralPipeline`
4. **Effective** — Phase9 × GeometricSupport weights

## Referência

Face Slim `effective ROI max @1.0` define baseline perceptual.
