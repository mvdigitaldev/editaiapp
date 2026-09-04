# Plano — Eyebrow End (Facial Warp V2)

**Estado:** Sprint D feita (2026-09-04). C assinada. Ícone Ponta no editor. Sem E escrita.

Contrato: [`FacialWarpV2-Development-Rules.md`](./FacialWarpV2-Development-Rules.md). Spec: [`v2-eyebrow-end.md`](./v2-eyebrow-end.md). Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

```
EyebrowEndField.build(face:, imageSize:, t:, tPhotoLeft:, tPhotoRight:)
  → DisplacementField
```

---

## 0. Numeração das sprints

| Sprint | Objectivo | Código de produto? |
|---|---|---|
| **A** | Field (`dx`/`dy`). Sem RGBA. Sem renderer. | Não |
| **B** | Lab offline: Field + `BackwardBilinearWarp` → `v2Raw` | Não |
| **C** | Aprovação visual humana das fotos lab | Não |
| **D** | Preview: ícone Ponta na tab Sobrancelha, key `eyebrow_end` | Sim |
| **E** | Export = mesmo grafo do preview | Sim |

Não se fundem sprints. Sem C escrita, D não existe.

---

## 1. Objectivo (A)

- Só Δx. Esquerda junta; direita separa. Geral / L / R = lados da foto.
- Só o terço interno (glabela). Cauda e arco quase parados. Olhos parados (`lidGate`). Amplitude `0.030`.
- Preservar os Fields vivos, incluindo `eyebrow_height` e `eyebrow_width`. Sem importar nenhum.
- `w · band · s_inner · away` independente de `t`. Runtime cacheia o unitário.

### Gates A (p01 / p05 / p12)

- `t = 0` identidade
- `dy` nulo em todo o campo
- `t > 0` ⇒ `browsSeparate`: dx 336 > 0, dx 107 < 0
- `t < 0` ⇒ `browsJoin`: o contrário
- |dx| em 336/107 visível (`> 0.0015 × faceWidth` a t=0,5)
- |dx| em caudas 300/70 ≤ 25% do pico interno; arco 334/105 ≤ 45%
- pico `< 0.040 × faceWidth`
- L isolado mexe 107; R isolado 336
- pálpebra ≤ 30% do pico; dobra ≤ 20%; landmark 10 ≈ 0
- `minDetJ > 0`; vinco < 0,30; degrau < 0,25
- isolamento (não importa Altura/Largura nem outros Fields)

---

## 2. Arquivos

### Sprint A (feita 2026-09-04)

| Ficheiro | Função |
|---|---|
| `lib/.../warp/v2/eyebrow_end/eyebrow_end_field.dart` | `EyebrowEndField.build` + `*Runtime` |
| `lib/.../warp/v2/eyebrow_end/eyebrow_end_masks.dart` | Ilha + `lidGate` (cópia da Largura, sem importar) |
| `lib/.../warp/v2/eyebrow_end/eyebrow_end_metrics.dart` | Métricas A |
| `test/.../facial_warp_v2_eyebrow_end_field_test.dart` | Gates A |
| `docs/beauty/v2-eyebrow-end.md` | Spec |
| `docs/beauty/v2-eyebrow-end-plan.md` | Este plano |

### Sprint B (feita 2026-09-04)

| Ficheiro | Função |
|---|---|
| `test/.../facial_warp_v2_eyebrow_end_lab_test.dart` | Matriz 21 `v2Raw` |
| `.cursor/facial-warp-v2/eyebrow_end/B/` | dumps + `summary.json` |
| `docs/beauty/v2-eyebrow-end-b-report.md` | Relatório B |

### Sprint C (feita 2026-09-04)

| Ficheiro | Função |
|---|---|
| `docs/beauty/v2-eyebrow-end-c-report.md` | Veredicto das 21 `v2Raw` |

### Sprint D (feita 2026-09-04)

| Ficheiro | Função |
|---|---|
| `docs/beauty/v2-eyebrow-end-d-report.md` | Relatório D |
| tab Sobrancelha + `applyEyebrowEndWarp` + cadeia | Preview |

### Sprints seguintes (não nesta ronda)

E: o mesmo `applyFaceWarpChain` (já partilhado; sem relatório até o Leonardo pedir).

---

## 3. O que não entra nesta ronda

- Alterar qualquer Field vivo
- Length, Front, Angle, Shape
- Fundir D+E
