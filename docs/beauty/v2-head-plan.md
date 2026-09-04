# Plano — Head (Facial Warp V2)

**Estado:** D no editor (2026-09-04). Calibração asas laterais (`0.34 × faceWidth`) no hull e no `R₊`. Sem E escrita. Relatórios B/C/D.

Contrato: [`FacialWarpV2-Development-Rules.md`](./FacialWarpV2-Development-Rules.md). Spec: [`v2-head.md`](./v2-head.md). Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

```
HeadField.build(face:, imageSize:, t: head) → DisplacementField
```

`t ∈ [-1, 1]`. Se `|t| ≤ 1e-6`, identidade deste efeito. Sem RGBA nesta sprint.

---

## 0. Numeração das sprints

| Sprint | Objectivo | Código de produto? |
|---|---|---|
| **A** | Field (`dx`/`dy`). Sem RGBA. Sem renderer. | Não |
| **B** | Lab offline: Field + `BackwardBilinearWarp` → `v2Raw` | Não |
| **C** | Aprovação visual humana das fotos lab | Não |
| **D** | Preview no editor (tab Proporção, key `head`) | Sim |
| **E** | Export = mesmo grafo do preview | Sim |

Não se fundem sprints. Sem C escrita, D não existe.

---

## 1. Objectivo (A)

- Escala de semelhança da cabeça no sítio. Fundo longe parado.
- Preservar os sete Fields vivos. Sem importar nenhum.
- Olhos e boca **andam** com a cabeça (não são hard-zero).
- Gerar **apenas** um `DisplacementField`.
- Infra: `BoundaryFeather`, `EuclideanDistanceTransform`, `DisplacementField`. Sem `RidgeWeight`.
- `w` dilatado ao pior enlarge (`|t| = 1`) e **independente de t**.
- Composição Head → advecção → Chin / Hairline **já na A** (sem esperar pela D).

### Gates A (p01 / p05 / p12)

- `t = 0` identidade
- crescer: silhueta **sai** (píxel fora do oval original com `|D|` útil)
- encolher: anel entre cara nova e antiga **não** é identidade
- fundo longe ≈ 0
- `minDetJ > 0` em ±1; vinco no núcleo e degrau de entrada abaixo do tecto dos outros Fields
- simetria `|D|` em 58 / 288 (razão < 1,25)
- runtime: o mesmo `unit` em dois `t`; o campo só muda por `α(t)`
- Head → `LandmarkAdvection` → Chin / Hairline: 152 e 10 no sítio advectado (desvio < 1 px)
- isolamento (não importa outros Fields)

---

## 2. Arquivos

### Sprint A

| Ficheiro | Função |
|---|---|
| `lib/features/editor/beauty_engine/warp/v2/head/head_field.dart` | `HeadField.build` + `HeadFieldRuntime` |
| `lib/features/editor/beauty_engine/warp/v2/head/head_masks.dart` | Hull original ∪ enlarge extremo, `headActive` |
| `lib/features/editor/beauty_engine/warp/v2/head/head_metrics.dart` | Métricas A |
| `test/beauty_engine/warp/v2/facial_warp_v2_head_field_test.dart` | Gates A |
| `docs/beauty/v2-head.md` | Spec |
| `docs/beauty/v2-head-plan.md` | Este plano |

### Sprint B (feita 2026-09-04)

Lab bipolar 3×5: `facial_warp_v2_head_lab_test.dart`. Dumps em `.cursor/facial-warp-v2/head/B/`. Relatório [`v2-head-b-report.md`](./v2-head-b-report.md). `invalidSource` no cap ao encolher (p01/p05); sem fill.

### Sprint C (assinada 2026-09-04)

Veredicto visual. Relatório [`v2-head-c-report.md`](./v2-head-c-report.md). Sem código.

### Sprint D (feita 2026-09-04)

Tab Proporção, key `head`, `applyHeadWarp`, stage 0 na cadeia. Relatório [`v2-head-d-report.md`](./v2-head-d-report.md).

### Sprints seguintes (não nesta ronda)

E: o mesmo `applyFaceWarpChain` (já partilhado; sem relatório até pedido).

---

## 3. Fora desta A

- Menu Proporção / ícone / slider
- Ligar `applyFaceWarpChain`
- Alterar qualquer Field de Rosto
- Bloqueio de fundo, `head_size`, zoom da foto inteira

---

## 4. Equação vigente (A)

```
s = 1 − 0.12 · t
D = w · (q − c) · (1 − 1/s) · min(1, R₊ / |q − c|)
```

`k` 0,22 invertia (`minDetJ < 0`) porque `|∇w| · |q−c| · α` passava de 1 na rampa. Sem buraco em `c`: saltar `r² < 1` deixava um vizinho parado e o primeiro anel valia 0,26 px de degrau.
