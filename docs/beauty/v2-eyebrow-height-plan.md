# Plano — Eyebrow Height (Facial Warp V2)

**Estado:** Sprint D no editor (2026-09-04). C assinada. Tab Sobrancelha. Sem E escrita. D [`v2-eyebrow-height-d-report.md`](./v2-eyebrow-height-d-report.md).

Contrato: [`FacialWarpV2-Development-Rules.md`](./FacialWarpV2-Development-Rules.md). Spec: [`v2-eyebrow-height.md`](./v2-eyebrow-height.md). Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

```
EyebrowHeightField.build(face:, imageSize:, t:, tPhotoLeft:, tPhotoRight:)
  → DisplacementField
```

`t ∈ [-1, 1]` por lado da foto. Se ambos ≈ 0, identidade deste efeito. Sem RGBA nesta sprint.

---

## 0. Numeração das sprints

| Sprint | Objectivo | Código de produto? |
|---|---|---|
| **A** | Field (`dx`/`dy`). Sem RGBA. Sem renderer. | Não |
| **B** | Lab offline: Field + `BackwardBilinearWarp` → `v2Raw` | Não |
| **C** | Aprovação visual humana das fotos lab | Não |
| **D** | Preview: tab Sobrancelha à direita de Rosto, key `eyebrow_height` | Sim |
| **E** | Export = mesmo grafo do preview | Sim |

Não se fundem sprints. Sem C escrita, D não existe.

---

## 1. Objectivo (A)

- Só Δy. Esquerda baixa; direita sobe. Geral / L / R = lados da foto.
- Planalto na ilha da sobrancelha. Olhos parados (`lidGate`). Linha L parada.
- Preservar os Fields vivos. Sem importar nenhum.
- Gerar **apenas** um `DisplacementField`.
- Infra: `BoundaryFeather`, `EuclideanDistanceTransform`, `DisplacementField`. Sem `RidgeWeight` (pesos a cair no arco seriam Shape).
- `w` independente de `t`. Runtime cacheia `unitWeight`.

### Gates A (p01 / p05 / p12)

- `t = 0` identidade
- `dx` nulo em todo o campo
- `t > 0` ⇒ `dy < 0` em 334/105 e em 282/52 (a ilha toda sobe)
- `t < 0` ⇒ `dy > 0` (baixa)
- L isolado mexe 105, não 334; R isolado o contrário
- olhos `p95 ≤ 0.5` px; pálpebra 159/386 `|D| ≤ 30%` do pico da brow; dobra externa (vão 70–33 / 300–263) `|D| ≤ 20%`
- 10 / boca / nariz ≈ 0; fora do hull ≈ 0
- `minDetJ > 0` em ±1; vinco no núcleo e degrau de entrada no tecto do Head (`0.30` / `0.25`)
- runtime: o mesmo `unit` em dois `t`
- isolamento (não importa outros Fields, nem `PersonMask`, nem RGBA)

---

## 2. Arquivos

### Sprint A (feita 2026-09-04)

| Ficheiro | Função |
|---|---|
| `lib/.../warp/v2/eyebrow_height/eyebrow_height_field.dart` | `EyebrowHeightField.build` + `*Runtime` |
| `lib/.../warp/v2/eyebrow_height/eyebrow_height_masks.dart` | Duas ilhas, olhos/L para métrica |
| `lib/.../warp/v2/eyebrow_height/eyebrow_height_metrics.dart` | Métricas A |
| `test/.../facial_warp_v2_eyebrow_height_field_test.dart` | Gates A |
| `docs/beauty/v2-eyebrow-height.md` | Spec |
| `docs/beauty/v2-eyebrow-height-plan.md` | Este plano |

### Sprint B (feita 2026-09-04)

Lab bipolar 3×7: `facial_warp_v2_eyebrow_height_lab_test.dart`. Dumps em `.cursor/facial-warp-v2/eyebrow_height/B/`. Relatório [`v2-eyebrow-height-b-report.md`](./v2-eyebrow-height-b-report.md). `invalidCount = 0`. Sem fill. Recalibrado 2026-09-04: `lidGate` cobre a dobra externa (prateleira + vão cauda→canto). Dumps refeitos.

### Sprint C (feita 2026-09-04)

Veredicto visual das 21 `v2Raw`. Relatório [`v2-eyebrow-height-c-report.md`](./v2-eyebrow-height-c-report.md). **Aprovado.** Sem `lib/`.

### Sprint D (feita 2026-09-04)

Tab Sobrancelha, key `eyebrow_height`, cadeia após `hairline`. Relatório [`v2-eyebrow-height-d-report.md`](./v2-eyebrow-height-d-report.md).

### Sprints seguintes (não nesta ronda)

E: o mesmo `applyFaceWarpChain` (já partilhado; sem relatório até pedido).

---

## 3. O que não entra nesta ronda

- Alterar qualquer Field vivo
- Os outros ícones do menu (Width, Length, End, Front, Angle, Shape)
- Relatório E
