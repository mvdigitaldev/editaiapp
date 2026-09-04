# Plano — Hairline (Facial Warp V2)

**Estado:** A–E fechadas. C assinada 2026-09-03. Relatório [`v2-hairline-c-report.md`](./v2-hairline-c-report.md).

Contrato: [`FacialWarpV2-Development-Rules.md`](./FacialWarpV2-Development-Rules.md). Spec: [`v2-hairline.md`](./v2-hairline.md). Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

```
HairlineField.build(face:, imageSize:, t: hairline) → DisplacementField
```

`t ∈ [-1, 1]`. Se `face == null` ou `|t| ≤ 1e-6`, identidade deste efeito. Sem RGBA nesta sprint.

---

## 0. Numeração das sprints

| Sprint | Objectivo | Código de produto? |
|---|---|---|
| **A** | Field (`dx`/`dy`). Sem RGBA. Sem renderer. | Não |
| **B** | Lab offline: Field + `BackwardBilinearWarp` → `v2Raw` | Não |
| **C** | Aprovação visual humana das fotos lab | Não |
| **D** | Preview no editor (key `hairline`) | Sim |
| **E** | Export = mesmo grafo do preview | Sim |

Não se fundem sprints. Sem C escrita, D não existe.

---

## 1. Objectivo

- Alterar **apenas** o arco do topo (infla / desincha a coroa).
- Preservar os seis Fields vivos. Sem importar nenhum.
- Preservar olhos, brows, nariz, boca, orelhas, maçãs, mento (hard-zero).
- Têmporas **fora da crista** (Temple fica efeito futuro). Cauda, nunca disco.
- Gerar **apenas** um `DisplacementField` novo.
- Infra partilhada: `RidgeWeight`, `BoundaryFeather`, `EuclideanDistanceTransform`, `DisplacementField`.

### Geometria (A confirma ou pára)

- Escala radial a partir do 151 (fallback 9): `D ∝ w · (p − 151)`. Infla para fora, desincha para dentro. `dx ≠ 0` nos flancos.
- Handle primário: landmark **10** (midline; `dx ≈ 0`).
- Crista: `103 → 67 → 109 → 10` / `332 → 297 → 338 → 10`, pesos `0.22 → 0.55 → 0.85 → 1.00`.
- Hull: testa + pad `0.18 × faceWidth` acima do oval. Sem disco no 10.
- Factor de escala: `0.10`. Calibração só no Field.

### Protecções hard-zero

| Região | Tratamento |
|---|---|
| Olhos, brows, nariz, boca, orelhas | hard-zero |
| Maçãs 123 / 352 | hard-zero |
| Mento / mandíbula | hard-zero (fora do hull; disco de segurança no 152 e gônios se o pad chegar) |
| Têmporas 21 / 162 / 127 / 251 / 389 / 356 | **não** disco. Métrica: p95 ≪ pico do 10 |
| Fora do hull da testa | zero |

### Métrica de produto

- `hairlineY` no landmark 10.
- `t < 0` → infla: `dy@10 < 0`, `hairlineYAfter < hairlineYBefore`.
- `t > 0` → desincha: `dy@10 > 0`.
- Protecções p95 ≈ 0.
- `minDetJ > 0`.

---

## 2. Arquivos

### Sprint A

| Ficheiro | Função |
|---|---|
| `lib/features/editor/beauty_engine/warp/v2/hairline/hairline_field.dart` | `HairlineField.build` + `HairlineFieldRuntime` |
| `lib/features/editor/beauty_engine/warp/v2/hairline/hairline_masks.dart` | Hull testa, `hairlineActive`, protecções |
| `lib/features/editor/beauty_engine/warp/v2/hairline/hairline_metrics.dart` | Métricas A (não altera `FieldMetrics` do Jaw) |
| `test/beauty_engine/warp/v2/facial_warp_v2_hairline_field_test.dart` | Gates A em p01/p05/p12 |
| `docs/beauty/v2-hairline.md` | Spec |
| `docs/beauty/v2-hairline-plan.md` | Este plano |

### Sprint B (regenerada)

Lab bipolar 3×5: `facial_warp_v2_hairline_lab_test.dart`. Dumps em `.cursor/facial-warp-v2/hairline/B/`. Relatório [`v2-hairline-b-report.md`](./v2-hairline-b-report.md).

### Sprint D / E (fechadas)

Key `hairline` no painel, `applyHairlineWarp`, cadeia no início. E = o mesmo `applyFaceWarpChain`.

### Sprint C (assinada 2026-09-03)

Veredicto visual. Relatório [`v2-hairline-c-report.md`](./v2-hairline-c-report.md). Sem código.

### Não podem ser alterados

- Os seis Fields vivos e os seus testes de contrato
- `displacement_field.dart`, `backward_bilinear_warp.dart`, `WarpRequest` / `WarpResult`
- `beauty_engine_controller.dart`, painel, registry, `FaceFilterPipeline` (até D)
- `region_catalog.dart` conjuntos já usados por outros efeitos

---

## 3. Sprint A — HairlineField

**Faz**

- Módulo `warp/v2/hairline/` com Field, máscaras e métricas.
- Testes `real-p01` / `real-p05` / `real-p12`.
- Isolamento: sem renderer, controller, UI, RGBA, outro Field V2.

**Não faz**

- `BackwardBilinearWarp`, preview, export, slider, ícone, cadeia.

**Gates A**

| Gate | Critério |
|---|---|
| t=0 | campo zero; `influenceMax = 0`; `minDetJ = 1` |
| t=−0.5 | infla para fora: `dy@10 < 0`; `dx@109 < 0`; `dx@338 > 0`; energia no 10 > 40% do pico |
| t=+0.5 | desincha para dentro: `dy@10 > 0`; sinais dos flancos invertidos |
| dx | `dx@10 ≈ 0`; `dx` nos flancos ≠ 0 (não é Δy-only) |
| Protecções | p95 olhos/brows/nariz/boca/orelhas/maçãs ≤ 0.5 |
| Têmporas | abs amostrado ≪ pico do 10 (teto 35% do `|dy@10|`) |
| Fold | `minDetJ > 0` em t=±1 |
| Runtime | segundo `build` com o mesmo `face` reescala o mesmo peso |
| Isolamento | sem `sourceRgba`, `backward_bilinear_warp`, controller, `jaw_field` |

**Aprovação A:** o campo faz o topo; os seis efeitos intactos. Isto **não** é C.

---

## 4. Critérios de parada

```
PARADA — o efeito hairline exige alteração em <camada congelada>.
Motivo: <uma frase>.
Não foi implementado o atalho.
```

- Só “funciona” se as têmporas ou as maçãs se moverem no pico.
- Disco binário nas têmporas.
- `minDetJ ≤ 0` no extremo.
- Preview ou cadeia antes da C.
- Alterar outro Field para compensar.

---

## 5. Rollback

| Sprint | Rollback |
|---|---|
| A | Apagar `warp/v2/hairline/`, teste A, docs do efeito. Diff dos seis Fields = vazio. |
| B | Regenerar dumps; o Field A fica. |
| C | Sem código; só o relatório. |
| D / E | Remover a key do painel e a etapa da cadeia. Field A fica. |

---

## 6. Fora de escopo

- Temple, Width, Lift, `forehead` legado.
- Ligar o slider “para ver”.
- Face Rig, MLS, receitas.
