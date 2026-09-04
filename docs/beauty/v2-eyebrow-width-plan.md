# Plano — Eyebrow Width (Facial Warp V2)

**Estado:** Sprint D feita (2026-09-04). C assinada. Ícone Largura no editor. Sem E escrita.

Contrato: [`FacialWarpV2-Development-Rules.md`](./FacialWarpV2-Development-Rules.md). Spec: [`v2-eyebrow-width.md`](./v2-eyebrow-width.md). Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

```
EyebrowWidthField.build(face:, imageSize:, t:, tPhotoLeft:, tPhotoRight:)
  → DisplacementField
```

---

## 0. Numeração das sprints

| Sprint | Objectivo | Código de produto? |
|---|---|---|
| **A** | Field (`dx`/`dy`). Sem RGBA. Sem renderer. | Não |
| **B** | Lab offline: Field + `BackwardBilinearWarp` → `v2Raw` | Não |
| **C** | Aprovação visual humana das fotos lab | Não |
| **D** | Preview: ícone Largura na tab Sobrancelha, key `eyebrow_width` | Sim |
| **E** | Export = mesmo grafo do preview | Sim |

Não se fundem sprints. Sem C escrita, D não existe.

---

## 1. Objectivo (A)

- Só Δy. Esquerda afina; direita engrossa. Geral / L / R = lados da foto.
- Abrir a ilha a partir do eixo (não planalto da Altura). Olhos parados (`lidGate`). Amplitude leve (`0.008`).
- Preservar os Fields vivos, incluindo `eyebrow_height`. Sem importar nenhum.
- `w · s` independente de `t`. Runtime cacheia o unitário assinado.

### Gates A (p01 / p05 / p12)

- `t = 0` identidade
- `dx` nulo
- `t > 0` ⇒ arco `dy < 0`, base `dy > 0`
- `t < 0` ⇒ o contrário
- pico `< 0.012 × faceWidth`
- L isolado mexe 105/52; R isolado 334/282
- pálpebra ≤ 30% do pico; dobra externa ≤ 20%
- `minDetJ > 0`; vinco < 0,30; degrau < 0,25
- isolamento (não importa Altura nem outros Fields)

---

## 2. Arquivos

### Sprint A (feita 2026-09-04)

| Ficheiro | Função |
|---|---|
| `lib/.../warp/v2/eyebrow_width/eyebrow_width_field.dart` | `EyebrowWidthField.build` + `*Runtime` |
| `lib/.../warp/v2/eyebrow_width/eyebrow_width_masks.dart` | Ilha + `lidGate` (cópia da Altura, sem importar) |
| `lib/.../warp/v2/eyebrow_width/eyebrow_width_metrics.dart` | Métricas A |
| `test/.../facial_warp_v2_eyebrow_width_field_test.dart` | Gates A |
| `docs/beauty/v2-eyebrow-width.md` | Spec |
| `docs/beauty/v2-eyebrow-width-plan.md` | Este plano |

### Sprint B (feita 2026-09-04)

| Ficheiro | Função |
|---|---|
| `test/.../facial_warp_v2_eyebrow_width_lab_test.dart` | Matriz 21 `v2Raw` |
| `.cursor/facial-warp-v2/eyebrow_width/B/` | dumps + `summary.json` |
| `docs/beauty/v2-eyebrow-width-b-report.md` | Relatório B |

### Sprint C (feita 2026-09-04)

| Ficheiro | Função |
|---|---|
| `docs/beauty/v2-eyebrow-width-c-report.md` | Veredicto das 21 `v2Raw` |

### Sprint D (feita 2026-09-04)

| Ficheiro | Função |
|---|---|
| `docs/beauty/v2-eyebrow-width-d-report.md` | Relatório D |
| tab Sobrancelha + `applyEyebrowWidthWarp` + cadeia | Preview |

### Sprints seguintes (não nesta ronda)

E: o mesmo `applyFaceWarpChain` (já partilhado; sem relatório até o Leonardo pedir).

---

## 3. O que não entra nesta ronda

- Tab, ícone, slider, `faceWarpChainStages`
- Alterar qualquer Field vivo
- Length, End, Front, Angle, Shape
