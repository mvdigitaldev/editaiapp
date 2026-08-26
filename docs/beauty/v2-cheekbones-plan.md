# Plano — Cheekbones (Facial Warp V2)

**Estado:** plano A–E aprovado. Sprint A **encerrada**. Hipótese H em inspecção no editor (2026-08-26). Sem C.

Vigente: [`v2-cheekbones-h-report.md`](./v2-cheekbones-h-report.md).  
A geometria deste plano (123/411, hull malar, gônio a zero, `t ∈ [0,1]`) é **histórico da A**. Não descreve o Field no disco.

O preview já está na cadeia (`applyCheekbonesWarp`) para inspecção H. Isso **não** substitui a aprovação escrita da Sprint C nem promove D/E.

Contrato: [`FacialWarpV2-Development-Rules.md`](./FacialWarpV2-Development-Rules.md). Spec de região: [`v2-cheekbones-spec.md`](./v2-cheekbones-spec.md) (emendada por H).


Cheekbones é o próximo efeito de produto. Jaw e Chin estão encerrados. Reutiliza a pipeline já aprovada. Não modifica nenhuma parte validada da V2.

```
CheekbonesField.build(face:, imageSize:, t: cheekbone) → DisplacementField
BackwardBilinearWarp.apply(WarpRequest(...)) → WarpResult
```

`t = parameters['cheekbone']` em `[0, 1]`. Se `face == null` ou `cheekbone == 0`, identidade deste efeito.

---

## 0. Numeração das sprints

As regras obrigatórias (secção 4) são A → E e **proíbem saltar** a aprovação visual.

| Este plano | Regras V2 | Equivalente Chin |
|---|---|---|
| Sprint A | Field | `ChinField` |
| Sprint B | Lab offline `v2Raw` | lab Chin |
| Sprint C | Aprovação visual | sign-off humano do `v2Raw` (antes da promoção) |
| Sprint D | Preview | promoção — `applyChinWarp` no controller |
| Sprint E | Export | promoção — frame inteiro + tiles de body |

Não se fundem sprints. Não se escreve preview na B. Não se “já liga o slider” na C.

---

## 1. Objectivo

- Alterar **apenas** a geometria das maçãs (mid-face / eminência malar: Δx para a midline).
- Preservar a mandíbula já implementada (`JawField` intocado; gônios 58–288 sem deslocamento no Field do Cheekbones).
- Preservar o queixo já implementado (módulo `chin/` intocado; 152 e hull Chin sem deslocamento no Field do Cheekbones).
- Preservar olhos, nariz, boca e demais regiões protegidas (hard-zero no Field do Cheekbones).
- Gerar **apenas** um `DisplacementField` novo.
- Usar o mesmo `BackwardBilinearWarp`, os mesmos `WarpRequest` / `WarpResult` / `DisplacementField`.
- Sem ROI, Mesh ACE, MLS facial, fill, Telea, wrapper, adapter ou segunda pipeline.
- Sem spline mandibular. Sem slider composto.

**Contrato do módulo:** a região malar (maçãs). Landmarks 123/411, hull e amplitude da Sprint A são calibração, **não** contrato. Recalibrar handles/hull/amplitude sem mudar a arquitectura permanece permitido enquanto o efeito ficar nas maçãs.

### Geometria (espelho do Jaw, sítio diferente)

Jaw aprovado: só **Δx**, energia na silhueta mandibular, métrica 58–288.

Chin aprovado: só **Δy**, energia no mento, métrica 152.

Cheekbones proposto (Sprint A confirma ou pára):

- Só **Δx** (dy = 0 em todo o campo, se a A confirmar).
- Direcção: para a midline (`dx` esquerdo > 0, `dx` direito < 0; `src = dest − d`).
- Sem Δy de mento. Sem levar a silhueta mandibular.
- Handles primários (hipótese inicial, **não** congelados): **123** (esquerda) e **411** (direita). A Sprint A confirma ou troca por outro ID de `leftCheek` / `rightCheek`.
- Handles secundários (peso menor): resto do hull activo vigente, **sem** IDs Jaw/Chin. Ajustáveis na A.
- Hull activo (hipótese inicial): união `leftCheek` ∪ `rightCheek` — `{116, 123, 147, 187, 207, 206, 203, 142, 126, 217, 345, 352, 411, 425, 427, 436, 426, 423, 266, 371}` — **sem** IDs Jaw/Chin.
- A Sprint A **pode reduzir** o hull ao subconjunto malar `{116, 123, 147, 187, 345, 352, 411, 425}` se o hull cheio causar influência perceptível sobre a mandíbula ou o sulco nasolabial.
- Não usar como handles: `{58, 288, 132, 361, 172, 136, 365, 397}` (Jaw), `{152, 148, 176, 149, 377, 400, 378}` (Chin), `{323, 454}` (orelha), `{127, 234, 356, 93}` (têmpora).
- Amplitude: valor inicial apenas para o Lab (`t * 0.04 * faceWidth` como semente). **Não faz parte do contrato do efeito.** A Sprint A calibra a amplitude para atingir o sign-off visual mantendo a arquitectura. Se a amplitude “não chegar”, **não** se toca no renderer.
- Rampa de fronteira + kernel gaussiano nos handles (mesmo *tipo* de construção que Jaw/Chin; código **novo** no módulo Cheekbones, sem extrair helpers de `jaw_field.dart` nem de `chin_field.dart`). Sem spline mandibular.

### O que a Sprint A pode / não pode

Pode:

- validar ou trocar 123/411;
- reduzir o hull malar;

desde que continue restrita à região das maçãs.

Se durante a Sprint A ficar evidente que os landmarks 123/411 ou o hull inicial não representam corretamente a região malar nas três imagens oficiais, a Sprint A pode redefinir handles e hull sem necessidade de alterar a arquitectura nem abrir uma nova spec.

Não pode:

- mover Jaw;
- mover Chin;
- usar Face Slim;
- reutilizar spline mandibular;
- criar slider composto.

### Protecções hard-zero (Field do Cheekbones)

IDs **copiados no módulo** Cheekbones. Sem importar `jaw_field.dart` nem `chin_field.dart`.

| Região | Tratamento |
|---|---|
| Olhos, brows, nariz, boca, faceCenter, orelhas | hard-zero (como Jaw/Chin) |
| Domínio Jaw `{58, 288, 132, 361}` + `{172, 136, 365, 397}` | hard-zero — **preservar mandíbula** |
| Domínio Chin `{152, 148, 176, 149, 377, 400, 378}` | hard-zero — **preservar queixo** |
| Fora do hull das bochechas | zero (`outsideCheekZone`) |

Jaw e Chin **não se editam**. Não se “compensa” o Cheekbones mexendo gônios ou o mento.

### Métrica visual de produto (equivalente à largura Jaw / isolamento Chin)

- `malarWidth` entre os primários **vigentes após a A** (antes / depois).
- Gate: `cheekbonesNarrows` ⇒ `malarWidthAfter < malarWidthBefore`.
- `dx` no primário esquerdo > 0; `dx` no primário direito < 0.
- `|d|` nos primários na ordem de `influenceMax` (calibrar na A; Jaw usou > 40%).
- `|d|` em 58, 288 e 152 ≈ 0 (eps 0.5 px).
- Protecções Jaw/Chin/olhos/boca/nariz/orelhas: p95 ≤ 0.5.
- `outsideCheekZoneP95` ≤ 0.5.
- `minDetJ > 0`.

---

## 2. Arquivos

### 2.1 Novos (por sprint)

**Sprint A**

| Ficheiro | Função |
|---|---|
| `lib/features/editor/beauty_engine/warp/v2/cheekbones/cheekbones_field.dart` | `CheekbonesField.build` → `DisplacementField` + máscaras + métricas. Sem RGBA, sem renderer, sem controller. |
| `lib/features/editor/beauty_engine/warp/v2/cheekbones/cheekbones_masks.dart` | Máscaras do Cheekbones (`cheek`, `cheekActive`, protecções). Reutiliza só `RegionMaskRaster` (read). **Não** altera a classe `RegionMasks`. |
| `lib/features/editor/beauty_engine/warp/v2/cheekbones/cheekbones_metrics.dart` | Métricas do Cheekbones. **Não** altera `FieldMetrics` (contrato Jaw). |
| `test/beauty_engine/warp/v2/facial_warp_v2_cheekbones_field_test.dart` | t=0 identidade; t=0.5 estreita maçãs; protecções; 58/288/152 imóveis; isolamento de imports. |
| `docs/beauty/v2-cheekbones-a-report.md` | Relatório A. |

**Sprint B** (só depois de A aprovada)

| Ficheiro | Função |
|---|---|
| `test/beauty_engine/warp/v2/facial_warp_v2_cheekbones_lab_test.dart` | Matriz p01/p05/p12 × cheekbone 0/25/50; `BackwardBilinearWarp.apply`; dumps `v2Raw`. Sem API nova em `lib/`. |
| `.cursor/facial-warp-v2/cheekbones/B/{p01,p05,p12}/{0,25,50}/` | `original.png`, `v2Raw.png`, coverage, invalidSource, displacement, influence, máscaras, `metrics.json`. |
| `docs/beauty/v2-cheekbones-b-report.md` | Relatório B. |

**Sprint C** (só depois de B aprovada)

| Ficheiro | Função |
|---|---|
| `docs/beauty/v2-cheekbones-c-report.md` | Veredicto visual **por foto × intensidade**. Sem código de produto. |

**Sprint D** (só depois de C aprovada)

Wiring no produto, **mesmo padrão** de `applyChinWarp` — chamada directa a `CheekbonesField` + renderer. Sem facade.

- `BeautyEngineController.applyCheekbonesWarp` (espelho de `applyChinWarp`, key `'cheekbone'`).
- `_renderTexture`: depois de Jaw e Chin (se activos), aplicar Cheekbones se `cheekbone > 0`. Cada Field é construído a partir da **face original** e do tamanho original. Sem somar `DisplacementField`.
- Painel / `BeautyToolRegistry` / `FaceFilterPipeline.faceWarpParameterKeys`: acrescentar `'cheekbone'`.
- `docs/beauty/v2-cheekbones-d-report.md`.

**Sprint E** (só depois de D aprovada)

- Export não-tiled: o mesmo `_renderTexture` (já inclui Cheekbones se D estiver certa).
- Export tiled: Cheekbones no **frame inteiro**, como Jaw e Chin; tiles só de body.
- `docs/beauty/v2-cheekbones-e-report.md`.

### 2.2 Podem receber só acrescento (append-only)

| Ficheiro | O que é permitido | O que é proibido |
|---|---|---|
| `warp/v2/region_catalog.dart` | Novos conjuntos `cheekLandmarks`, `cheekPrimary`, `cheekSecondary` | Alterar `chinTip`, gônios, `jawLandmarks`, silhueta jaw, conjuntos Chin, olhos/nariz/boca |

Handles / hull são constantes **do módulo** Cheekbones (como Chin A). Ajustá-los não muda a arquitectura. **123 / 411 e o hull da A são calibração, não contrato.** O contrato do módulo é a região malar; uma sprint posterior pode recalibrar landmarks sem nova spec.

Se o catálogo precisar de mudar um conjunto **já usado por Jaw ou Chin**, **PARADA**.

### 2.3 Não podem ser alterados

Infra, Jaw e Chin (qualquer sprint):

- `warp/v2/displacement_field.dart`
- `warp/v2/backward_bilinear_warp.dart`
- `warp/v2/jaw_field.dart`
- `warp/v2/chin/` (módulo inteiro)
- `warp/v2/field_metrics.dart` (Cheekbones tem métricas próprias)
- `warp/v2/region_masks.dart` — classe `RegionMasks` e assinaturas existentes. Só **ler** `RegionMaskRaster`.
- `test/beauty_engine/warp/v2/facial_warp_v2_displacement_field_test.dart`
- `test/beauty_engine/warp/v2/facial_warp_v2_renderer_test.dart`
- `test/beauty_engine/warp/v2/facial_warp_v2_jaw_field_test.dart`
- `test/beauty_engine/warp/v2/facial_warp_v2_lab_test.dart` (contrato Jaw)
- `test/beauty_engine/warp/v2/facial_warp_v2_chin_field_test.dart`
- `test/beauty_engine/warp/v2/facial_warp_v2_chin_lab_test.dart`
- `test/beauty_engine/warp/v2/facial_warp_v2_device_lab_test.dart`

`face_slim/` permanece apenas como referência experimental.

Não reutilizar código do módulo durante a implementação do Cheekbones.

Até Sprint C inclusive, também **não** se altera:

- `beauty_engine_controller.dart`
- `tiled_export_engine.dart`
- painel, registry, `FaceFilterPipeline`
- `facial_warp_v2_device_lab.dart` (não é preview; continua jaw-only)
- `FacialWarpV2-Development-Rules.md`

Body, pele, cor, MLS, `PassWarp`: fora de escopo em todas as sprints.

---

## 3. Fluxo (igual ao Chin)

### Sprint A — CheekbonesField

**Faz**

- Módulo `warp/v2/cheekbones/` com Field, máscaras e métricas.
- Testes nas faces `real-p01` / `real-p05` / `real-p12` (os mesmos landmarks do Jaw/Chin).
- Isolamento: `cheekbones_field.dart` não importa renderer, controller, UI, `extended_roi`, anatomy, MLS, `jaw_field.dart`, `chin_field.dart` nem `face_slim_field.dart`. O mesmo vale para `cheekbones_masks.dart` e `cheekbones_metrics.dart`.

**Não faz**

- RGBA, preview, export, slider, Device Lab, `BackwardBilinearWarp`.

**Testes**

```
flutter test test/beauty_engine/warp/v2/
```

Jaw, Chin e renderer têm de passar **sem** mudança de expectativa. Acrescenta-se só `facial_warp_v2_cheekbones_field_test.dart`.

**Gates A**

| Gate | Critério |
|---|---|
| t=0 | campo zero; `influenceMax = 0` |
| t=0.5 | `cheekbonesNarrows`; `|d|` nos primários vigentes > 40% de `influenceMax` |
| dx | esquerdo > 0, direito < 0 (para a midline) |
| dy | campo só Δx (`dy` ≈ 0 no activo; exact 0 se o desenho A o fixar) |
| Mandíbula / queixo | `|d|` amostrado em 58, 288 e 152 ≈ 0 (eps 0.5 px) |
| Protecções | p95 olhos/brows/nariz/boca/orelhas/Jaw/Chin ≤ 0.5 |
| Fora do hull | `outsideCheekZoneP95` ≤ 0.5 |
| Fold | `minDetJ > 0` |
| Isolamento | sem import de renderer/produto/ROI/`jaw_field`/`chin_field`/`face_slim_field` |
| Regressão | testes Jaw/Chin/renderer/lab Jaw inalterados e verdes |
| Produto | o resultado deve ser percebido como redução das maçãs do rosto, **sem parecer Jaw e sem parecer Chin** |

**Aprovação A:** campo faz as maçãs; Jaw, Chin e renderer intactos.

### Sprint B — Lab offline

**Faz**

- `CheekbonesField.build` + `BackwardBilinearWarp.apply` **só no teste**.
- Matriz **3 × 3**: p01 / p05 / p12 × `t = 0 / 0.25 / 0.50`.
- Fixtures: os mesmos PNG do Jaw (`test/beauty_engine/warp/fixtures/phase12/`).
- Dumps no disco + `summary.json`. Sem fill.

**Não faz**

- Controller, UI, export, Device Lab, alteração a `lib/` (como V2.2 do Jaw).

**Gates B**

| Gate | Critério |
|---|---|
| t=0 | `v2Raw` byte-igual à fonte; `invalidSource = 0` |
| t>0 | `changedPixelCount > 0` no domínio das maçãs |
| Geometria | `cheekbonesNarrows`; protecções p95 ≤ 0.5; 58/288/152 imóveis; `minDetJ > 0` |
| Fill | zero no grafo; `invalidSource` **não** é preenchido |
| Imports do lab | sem ROI/MLS/controller |

**Aprovação B:** métricas verdes + 9 dumps no disco. Isto **não** substitui a Sprint C.

### Sprint C — Aprovação visual

**Faz**

- Revisão humana dos 9 `v2Raw`.
- Relatório com passa/falha por célula.
- Primeira foto de sign-off: **p05**. Depois p12. p01 serve para não vazar para o maxilar.

**Não faz**

- Código. Se falhar: volta a A (Field) ou B (lab). **Nunca** “corrigir no renderer”.

**Gates C**

- Maçãs entram de forma legível em p01/p05/p12 a 25% e 50%.
- O resultado deve ser percebido como redução das maçãs do rosto, **sem parecer Jaw e sem parecer Chin**.
- Linha 58–288 não se mexer. Mento (152) não subir.
- Olhos / nariz / boca estáveis.
- Ghost/smear sem fill é aceitável (mesmo critério Jaw V2.2). Leak que mexa maxilar, mento ou boca = falha.

Sem C aprovada, D não existe.

### Sprint D — Preview

**Faz**

- `applyCheekbonesWarp` no controller (cópia estrutural de `applyChinWarp`, key `'cheekbone'`).
- `_renderTexture`: `applyJawWarp` depois `applyChinWarp` depois `applyCheekbonesWarp` sobre o RGBA resultante. Cada `apply` do **mesmo** renderer.
- UI: categoria Rosto ganha o slider `'cheekbone'` (Jaw e Chin permanecem).
- Registry e `FaceFilterPipeline`: keys `['jaw', 'chin', 'cheekbone']`. `hasActiveWarp` se jaw>0 **ou** chin>0 **ou** cheekbone>0.

**Composição (decisão a aprovar na D, não antes)**

- Cada efeito gera o seu Field a partir da face e do tamanho **originais**.
- Não se somam `dx`/`dy` num campo partilhado.
- Ordem: Jaw → Chin → Cheekbones.

```
Se a composição introduzir regressão visual em Jaw ou Chin
nos testes oficiais (p01, p05, p12),
a Sprint D entra em PARADA e volta para a Sprint A do
Cheekbones.

JawField e ChinField não podem ser alterados para acomodar
Cheekbones.

Regressão visual significa:
- alteração perceptível da geometria produzida por Jaw isolado;
- alteração perceptível da geometria produzida por Chin isolado;
- perda dos gates aprovados das Sprints C de Jaw ou Chin.
```

Device Lab **não** entra no preview. Não se altera `facial_warp_v2_device_lab.dart` nesta sprint (continua dump jaw-only).

**Gates D**

- Preview com só cheekbone = Field aprovado + renderer.
- Preview com só jaw = **idêntico** ao actual (regressão).
- Preview com só chin = **idêntico** ao actual (regressão).
- Sem wrapper, sem flag de pipeline, sem ROI.

### Sprint E — Export

**Faz**

- Não-tiled: herda D.
- Tiled: aplicar Cheekbones no frame inteiro a seguir ao Chin; tiles só body.

**Gates E**

- Export = mesmo grafo do preview.
- Sem raster facial paralelo, sem inpaint, sem GPU facial nova.

---

## 4. Testes (resumo)

| Quando | Comando | O que prova |
|---|---|---|
| Toda sprint | `flutter test test/beauty_engine/warp/v2/` | Contratos V2 + testes novos do Cheekbones |
| A | + `facial_warp_v2_cheekbones_field_test.dart` | Field / máscaras / métricas |
| B | + `facial_warp_v2_cheekbones_lab_test.dart` | `v2Raw` 3×3, isolamento |
| D/E | testes de painel/registry/controller que já existem, **actualizados só para aceitar a key `cheekbone`** — sem reescrever goldens Jaw/Chin | Wiring |

Não se editam os ficheiros de contrato listados em 2.3 para o Cheekbones passar.

---

## 5. Critérios de parada

Parar de imediato e escrever no relatório da sprint:

```
PARADA — o efeito cheekbones exige alteração em <camada congelada>.
Motivo: <uma frase>.
Não foi implementado o atalho.
```

Além da lista das regras (renderer, `DisplacementField`, `WarpRequest`, `WarpResult`, `JawField`, módulo Chin, fill/Telea, segunda pipeline, ROI/Mesh/MLS, GPU facial, flag V1↔V2, body/pele/cor):

- As maçãs só “funcionam” se os gônios 58–288 ou o 152 se moverem.
- É preciso usar Face Slim ou reutilizar código de `face_slim/`.
- É preciso reutilizar spline mandibular.
- É preciso criar slider composto.
- É preciso somar campos no `DisplacementField` ou mudar `RegionMasks` / `FieldMetrics` de forma que quebre o construtor Jaw ou Chin.
- É preciso fill porque o mid-face abre buraco.
- Preview ou export começam antes da Sprint C aprovada.
- A composição na D introduz regressão visual em Jaw ou Chin nos testes oficiais (p01, p05, p12), no sentido da secção 3.

---

## 6. Rollback

Cada sprint é revertível à parte (não se mistura com Jaw nem Chin).

| Sprint | Rollback |
|---|---|
| A | Apagar `warp/v2/cheekbones/`, teste A, acrescentos do catálogo. Diff de infra/Jaw/Chin = vazio. |
| B | Apagar teste B e `.cursor/facial-warp-v2/cheekbones/B/`. `lib/` igual ao fim de A. |
| C | Só relatório; nada a reverter no código. |
| D | Remover `applyCheekbonesWarp` e a key `'cheekbone'` de painel/registry/pipeline. `applyJawWarp` e `applyChinWarp` permanecem. |
| E | Reverter só o tiled export; preview D pode ficar se E falhar sozinha. |

Não há flag de emergência que reabra ROI/Mesh/MLS.

---

## 7. Fora de escopo

- Relocar `jaw_field.dart` para `warp/v2/jaw/`.
- Relocar o módulo `chin/`.
- Alterar Device Lab / `facialWarpCoreV2Lab`.
- Limpar `FaceWarpV3Config` ou `FaceParams` mortos.
- Face Slim, V Face, Narrow Face, Temple, Hairline, nariz, olhos, boca.
- Slider composto.
- Paridade comercial / Meitu.
- Qualquer implementação neste momento.

---

## 8. Checklist antes da Sprint A

- [x] Plano escrito (este documento).
- [x] Plano aprovado por escrito.
- [ ] Sprint A cabe nas regras (só Field; sem RGBA/preview/controller).
- [ ] Não é necessário tocar em renderer, `DisplacementField`, `WarpRequest`, `WarpResult`, Jaw ou Chin.
- [ ] Módulo Cheekbones não importa produto nem pipeline abandonada.
- [ ] Testes de contrato V2 existentes não serão editados.
- [ ] Sem wrapper, adapter, flag de pipeline, utilitário “para depois”.

A Sprint A **não começa** sem o visto explícito para a Sprint A.
