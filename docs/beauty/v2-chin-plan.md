# Plano — Chin (Facial Warp V2)

**Estado:** só plano. Sem código até aprovação explícita deste documento e da Sprint A.

Contrato: [`FacialWarpV2-Development-Rules.md`](./FacialWarpV2-Development-Rules.md). Qualquer ponto deste plano que contradiga as regras é inválido.

Chin é o segundo efeito. Reutiliza a pipeline já aprovada. Não modifica nenhuma parte validada da V2.

```
ChinField.build(face:, imageSize:, t: chin) → DisplacementField
BackwardBilinearWarp.apply(WarpRequest(...)) → WarpResult
```

`t = parameters['chin']` em `[0, 1]`. Se `face == null` ou `chin == 0`, identidade deste efeito.

---

## 0. Numeração das sprints

O pedido verbal listou C = preview e D = export. As regras obrigatórias (secção 4) são A → E e **proíbem saltar** a aprovação visual.

| Este plano | Regras V2 | Equivalente Jaw |
|---|---|---|
| Sprint A | Field | V2.1 `JawField` |
| Sprint B | Lab offline `v2Raw` | V2.2 lab |
| Sprint C | Aprovação visual | sign-off humano do `v2Raw` (antes da promoção) |
| Sprint D | Preview | promoção — `applyJawWarp` no controller |
| Sprint E | Export | promoção — frame inteiro + tiles de body |

Não se fundem sprints. Não se escreve preview na B. Não se “já liga o slider” na C.

---

## 1. Objectivo

- Alterar **apenas** a geometria do queixo (encurtar: silhueta do mento sobe).
- Preservar a mandíbula já implementada (`JawField` intocado; gônios 58–288 sem deslocamento no Field do Chin).
- Preservar olhos, nariz, boca e demais regiões protegidas (hard-zero no Field do Chin).
- Gerar **apenas** um `DisplacementField` novo.
- Usar o mesmo `BackwardBilinearWarp`, os mesmos `WarpRequest` / `WarpResult` / `DisplacementField`.
- Sem ROI, Mesh ACE, MLS facial, fill, Telea, wrapper, adapter ou segunda pipeline.

### Geometria (espelho do Jaw, eixo diferente)

Jaw aprovado: só **Δx**, energia na silhueta mandibular, métrica 58–288.

Chin proposto (Sprint A confirma ou pára):

- Só **Δy** (dx = 0 em todo o campo).
- Direcção: queixo para cima no espaço imagem (`dy < 0` no tip; `src = dest − d`).
- Handle primário: landmark **152** (`V2RegionCatalog.chinTip`, já existente — não redefinir).
- Handles secundários (peso menor): cadeia do mento **sem gônios** — proposta `{148, 377, 176, 400}`.
- Hull activo: mento apertado `{152, 148, 176, 149, 377, 400, 378}` — **sem** `{58, 288, 132, 361, 172, 136, 365, 397}`.
- Amplitude lab inicial (igual espírito do Jaw, constante própria no módulo Chin): `t * 0.04 * faceWidth`. Calibração só no Field; se a amplitude “não chegar”, **não** se toca no renderer.
- Rampa de fronteira + kernel gaussiano nos handles (mesmo *tipo* de construção que Jaw; código **novo** no módulo Chin, sem extrair helpers de `jaw_field.dart`).

### Protecções hard-zero (Field do Chin)

| Região | Tratamento |
|---|---|
| Olhos, brows, nariz, boca, faceCenter, orelhas | hard-zero (como Jaw) |
| Gônios e silhueta mandibular `{58, 288, 132, 361}` (+ secundários jaw `{172, 136, 365, 397}`) | hard-zero — **preservar mandíbula** |
| Proxy “barba” do Jaw (faixa lábio→152) | **não** copiar como protecção — esse é o domínio do Chin |
| Fora do hull do mento | zero (`outsideChinZone`) |

Jaw continua a proteger a barba **no Field do Jaw**. Chin não edita isso.

### Métrica visual de produto (equivalente aos gônios)

- `chinY` no landmark 152 (antes / depois + `dy` amostrado no tip).
- Gate: `chinShortens` ⇒ `chinYAfter < chinYBefore`; `|dy@152|` na ordem de `influenceMax`.
- Gônios no Field Chin: `|d|` em 58 e 288 ≈ 0 (p95 / amostragem).
- Protecções faciais: p95 = 0.
- `minDetJ > 0`.

---

## 2. Arquivos

### 2.1 Novos (por sprint)

**Sprint A**

| Ficheiro | Função |
|---|---|
| `lib/features/editor/beauty_engine/warp/v2/chin/chin_field.dart` | `ChinField.build` → `DisplacementField` + máscaras + métricas. Sem RGBA, sem renderer, sem controller. |
| `lib/features/editor/beauty_engine/warp/v2/chin/chin_masks.dart` | Máscaras do Chin (`chin`, `chinActive`, protecções). Reutiliza só `RegionMaskRaster` (read). **Não** altera a classe `RegionMasks`. |
| `lib/features/editor/beauty_engine/warp/v2/chin/chin_field_metrics.dart` | Métricas do Chin. **Não** altera `FieldMetrics` (contrato Jaw). |
| `test/beauty_engine/warp/v2/facial_warp_v2_chin_field_test.dart` | t=0 identidade; t=0.5 encurta 152; protecções; gônios imóveis; isolamento de imports. |
| `docs/beauty/v2-chin-a-report.md` | Relatório A. |

**Sprint B** (só depois de A aprovada)

| Ficheiro | Função |
|---|---|
| `test/beauty_engine/warp/v2/facial_warp_v2_chin_lab_test.dart` | Matriz p01/p05/p12 × chin 0/25/50; `BackwardBilinearWarp.apply`; dumps `v2Raw`. Sem API nova em `lib/`. |
| `.cursor/facial-warp-v2/chin/B/{p01,p05,p12}/{0,25,50}/` | `original.png`, `v2Raw.png`, coverage, invalidSource, displacement, influence, máscaras, `metrics.json`. |
| `docs/beauty/v2-chin-b-report.md` | Relatório B. |

**Sprint C** (só depois de B aprovada)

| Ficheiro | Função |
|---|---|
| `docs/beauty/v2-chin-c-report.md` | Veredicto visual **por foto × intensidade**. Sem código de produto. |

**Sprint D** (só depois de C aprovada)

Wiring no produto, **mesmo padrão** de `applyJawWarp` — chamada directa a `ChinField` + renderer. Sem facade.

- `BeautyEngineController.applyChinWarp` (espelho de `applyJawWarp`, key `'chin'`).
- `_renderTexture`: depois de Jaw (se activo), aplicar Chin se `chin > 0`. Cada Field é construído a partir da **face original** e do tamanho original. Sem somar `DisplacementField`. Sem classe mixer.
- Painel / `BeautyToolRegistry` / `FaceFilterPipeline.faceWarpParameterKeys`: acrescentar `'chin'`.
- `docs/beauty/v2-chin-d-report.md`.

**Sprint E** (só depois de D aprovada)

- Export não-tiled: o mesmo `_renderTexture` (já inclui Chin se D estiver certa).
- Export tiled: Chin no **frame inteiro**, como Jaw; tiles só de body.
- `docs/beauty/v2-chin-e-report.md`.

### 2.2 Podem receber só acrescento (append-only)

| Ficheiro | O que é permitido | O que é proibido |
|---|---|---|
| `warp/v2/region_catalog.dart` | Novos conjuntos `chinLandmarks`, `chinPrimary`, `chinSecondary` | Alterar `chinTip`, gônios, `jawLandmarks`, silhueta jaw, olhos/nariz/boca |

Se o catálogo precisar de mudar um conjunto **já usado por Jaw**, **PARADA**.

### 2.3 Não podem ser alterados

Infra e Jaw (qualquer sprint):

- `warp/v2/displacement_field.dart`
- `warp/v2/backward_bilinear_warp.dart`
- `warp/v2/jaw_field.dart`
- `warp/v2/field_metrics.dart` (Chin tem métricas próprias)
- `warp/v2/region_masks.dart` — classe `RegionMasks` e assinaturas existentes. Só **ler** `RegionMaskRaster`.
- `test/beauty_engine/warp/v2/facial_warp_v2_displacement_field_test.dart`
- `test/beauty_engine/warp/v2/facial_warp_v2_renderer_test.dart`
- `test/beauty_engine/warp/v2/facial_warp_v2_jaw_field_test.dart`
- `test/beauty_engine/warp/v2/facial_warp_v2_lab_test.dart` (contrato Jaw)
- `test/beauty_engine/warp/v2/facial_warp_v2_device_lab_test.dart`

Até Sprint C inclusive, também **não** se altera:

- `beauty_engine_controller.dart`
- `tiled_export_engine.dart`
- painel, registry, `FaceFilterPipeline`
- `facial_warp_v2_device_lab.dart` (não é preview; continua jaw-only)
- `FacialWarpV2-Development-Rules.md`

Body, pele, cor, MLS, `PassWarp`: fora de escopo em todas as sprints.

---

## 3. Fluxo (igual ao Jaw)

### Sprint A — ChinField

**Faz**

- Módulo `warp/v2/chin/` com Field, máscaras e métricas.
- Testes nas faces `real-p01` / `real-p05` / `real-p12` (os mesmos landmarks do Jaw).
- Isolamento: `chin_field.dart` não importa renderer, controller, UI, `extended_roi`, anatomy, MLS.

**Não faz**

- RGBA, preview, export, slider, Device Lab, `BackwardBilinearWarp`.

**Testes**

```
flutter test test/beauty_engine/warp/v2/
```

Jaw e renderer têm de passar **sem** mudança de expectativa. Acrescenta-se só `facial_warp_v2_chin_field_test.dart`.

**Gates A**

| Gate | Critério |
|---|---|
| t=0 | campo zero; `influenceMax = 0` |
| t=0.5 | `chinShortens`; `|dy@152|` > 40% de `influenceMax`; Δy do tip > limiar lab (calibrar no relatório; ordem de 1.5 px como o Jaw fez nos gônios) |
| dx | campo só Δy (`dx` ≈ 0 no activo; exact 0 se o desenho A o fixar) |
| Mandíbula | `|d|` amostrado em 58 e 288 ≈ 0 |
| Protecções | p95 olhos/brows/nariz/boca/orelhas = 0 |
| Fold | `minDetJ > 0` |
| Isolamento | sem import de renderer/produto/ROI |
| Regressão | testes Jaw/renderer/lab Jaw inalterados e verdes |

**Aprovação A:** campo faz o queixo; Jaw e renderer intactos.

### Sprint B — Lab offline

**Faz**

- `ChinField.build` + `BackwardBilinearWarp.apply` **só no teste**.
- Matriz **3 × 3**: p01 / p05 / p12 × `t = 0 / 0.25 / 0.50`.
- Fixtures: os mesmos PNG do Jaw (`test/beauty_engine/warp/fixtures/phase12/`).
- Dumps no disco + `summary.json`. Sem fill.

**Não faz**

- Controller, UI, export, Device Lab, alteração a `lib/` (como V2.2 do Jaw).

**Gates B**

| Gate | Critério |
|---|---|
| t=0 | `v2Raw` byte-igual à fonte; `invalidSource = 0` |
| t>0 | `changedPixelCount > 0` no domínio do mento |
| Geometria | `chinShortens`; protecções p95 = 0; gônios imóveis; `minDetJ > 0` |
| Fill | zero no grafo; `invalidSource` **não** é preenchido |
| Imports do lab | sem ROI/MLS/controller |

**Aprovação B:** métricas verdes + 9 dumps no disco. Isto **não** substitui a Sprint C.

### Sprint C — Aprovação visual

**Faz**

- Revisão humana dos 9 `v2Raw`.
- Relatório com passa/falha por célula.

**Não faz**

- Código. Se falhar: volta a A (Field) ou B (lab). **Nunca** “corrigir no renderer”.

**Gates C**

- Queixo sobe de forma legível em p01/p05/p12 a 25% e 50%.
- Mandíbula (gônios) não estreita.
- Olhos / nariz / boca estáveis.
- Ghost/smear sem fill é aceitável (mesmo critério Jaw V2.2). Leak que mexa maxilar ou boca = falha.

Sem C aprovada, D não existe.

### Sprint D — Preview

**Faz**

- `applyChinWarp` no controller (cópia estrutural de `applyJawWarp`, key `'chin'`).
- `_renderTexture`: `applyJawWarp` depois `applyChinWarp` sobre o RGBA resultante. Dois `apply` do **mesmo** renderer. Sem `WarpMixer`.
- UI: categoria Rosto ganha o slider `'chin'` (Jaw permanece).
- Registry e `FaceFilterPipeline`: keys `['jaw', 'chin']`. `hasActiveWarp` se jaw>0 **ou** chin>0.

**Composição (decisão a aprovar na D, não antes)**

- Cada efeito gera o seu Field a partir da face e do tamanho **originais**.
- Não se somam `dx`/`dy` num campo partilhado.
- Ordem: Jaw → Chin (Jaw já é o primeiro passo facial).
- Se a composição visual destruir Jaw ou Chin, **PARADA** — não se altera `JawField` nem o renderer para “compensar”.

Device Lab **não** entra no preview. Não se altera `facial_warp_v2_device_lab.dart` nesta sprint (continua dump jaw-only).

**Gates D**

- Preview com só chin = Field aprovado + renderer.
- Preview com só jaw = **idêntico** ao actual (regressão).
- Sem wrapper, sem flag de pipeline, sem ROI.

### Sprint E — Export

**Faz**

- Não-tiled: herda D.
- Tiled: aplicar Chin no frame inteiro a seguir ao Jaw; tiles só body.

**Gates E**

- Export = mesmo grafo do preview.
- Sem raster facial paralelo, sem inpaint, sem GPU facial nova.

---

## 4. Testes (resumo)

| Quando | Comando | O que prova |
|---|---|---|
| Toda sprint | `flutter test test/beauty_engine/warp/v2/` | Contratos V2 + testes novos do Chin |
| A | + `facial_warp_v2_chin_field_test.dart` | Field / máscaras / métricas |
| B | + `facial_warp_v2_chin_lab_test.dart` | `v2Raw` 3×3, isolamento |
| D/E | testes de painel/registry/controller que já existem, **actualizados só para aceitar a key `chin`** — sem reescrever goldens Jaw | Wiring |

Não se editam os quatro ficheiros de contrato listados em 2.3 para o Chin passar.

---

## 5. Critérios de parada

Parar de imediato e escrever no relatório da sprint:

```
PARADA — o efeito chin exige alteração em <camada congelada>.
Motivo: <uma frase>.
Não foi implementado o atalho.
```

Além da lista das regras (renderer, `DisplacementField`, `WarpRequest`, `WarpResult`, `JawField`, fill/Telea, segunda pipeline, ROI/Mesh/MLS, GPU facial, flag V1↔V2, body/pele/cor):

- O queixo só “funciona” se os gônios 58–288 se moverem.
- O queixo só “funciona” se se alterar a protecção/barba **dentro** de `jaw_field.dart`.
- É preciso somar campos no `DisplacementField` ou mudar `RegionMasks` / `FieldMetrics` de forma que quebre o construtor Jaw.
- É preciso fill porque o mento abre buraco no pescoço.
- Preview ou export começam antes da Sprint C aprovada.

---

## 6. Rollback

Cada sprint é revertível à parte (não se mistura com Jaw).

| Sprint | Rollback |
|---|---|
| A | Apagar `warp/v2/chin/`, teste A, acrescentos do catálogo. Diff de infra/Jaw = vazio. |
| B | Apagar teste B e `.cursor/facial-warp-v2/chin/B/`. `lib/` igual ao fim de A. |
| C | Só relatório; nada a reverter no código. |
| D | Remover `applyChinWarp` e a key `'chin'` de painel/registry/pipeline. `applyJawWarp` permanece. |
| E | Reverter só o tiled export; preview D pode ficar se E falhar sozinha. |

Não há flag de emergência que reabra ROI/Mesh/MLS.

---

## 7. Fora de escopo

- Relocar `jaw_field.dart` para `warp/v2/jaw/`.
- Alterar Device Lab / `facialWarpCoreV2Lab`.
- Limpar `FaceWarpV3Config` ou `FaceParams` mortos.
- Face slim, nariz, olhos, boca.
- Paridade comercial / Meitu.
- Qualquer implementação neste momento.

---

## 8. Checklist antes da Sprint A

- [x] Plano escrito (este documento).
- [ ] Plano aprovado por escrito.
- [ ] Sprint A cabe nas regras (só Field; sem RGBA/preview/controller).
- [ ] Não é necessário tocar em renderer, `DisplacementField`, `WarpRequest`, `WarpResult` ou Jaw.
- [ ] Módulo Chin não importa produto nem pipeline abandonada.
- [ ] Testes de contrato V2 existentes não serão editados.
- [ ] Sem wrapper, adapter, flag de pipeline, utilitário “para depois”.

A Sprint A **não começa** sem o visto neste plano.
