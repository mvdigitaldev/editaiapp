# Facial Warp V2 — regras de desenvolvimento

**Estado:** aprovado. Referência obrigatória para qualquer efeito facial novo na V2.

Este documento não é um relatório de sprint. É o contrato permanente da arquitectura facial do produto. Qualquer implementação, revisão ou plano que contradiga estas regras está inválido.

Documentos históricos (`30-estado-atual-arquitetura.md`, `31-sistema-facial-atual.md`, `32-extended-roi.md`, relatórios ROI/Mesh/MLS) descrevem a pipeline abandonada. Não os usar como mapa do sistema actual.

Relatórios de sprint V2 já fechados (evidência, não substitutos destas regras):

- `v2.0-renderer-report.md`
- `v2.1-jaw-field-report.md`
- `v2.2-lab-report.md`
- `v2.3-device-lab-report.md`
- `v2-promotion-report.md`

---

## 1. Princípios arquitecturais

1. Existe **apenas uma pipeline facial**:

   ```
   EffectField.build(...) → DisplacementField
   BackwardBilinearWarp.apply(WarpRequest(...)) → WarpResult
   ```

2. Todo efeito gera **apenas um** `DisplacementField`. O efeito não pinta RGBA, não faz fill e não rasteriza.

3. O renderer (`BackwardBilinearWarp`) é **estável**. A convenção é `src = dest − displacement`. Origem fora de `[0, width−1] × [0, height−1]`: não amostrar; preservar o destino; `coverage = 0`; `invalidSource = 1`. Sem clamp à borda. Sem Telea. Sem hole-fill.

4. `WarpRequest`, `WarpResult` e `DisplacementField` são **infraestrutura compartilhada**. Não são o sítio de um efeito.

5. Nenhum efeito pode modificar outro efeito existente. Chin não edita Jaw. Nose não edita Chin. Um efeito novo não “ajusta” constantes, máscaras ou testes de um efeito já aprovado.

6. Não há segunda pipeline, selector, flag V1↔V2, facade, adapter, wrapper, LegacyWarp nem bridge “para depois”.

7. Body, pele e cor são sistemas à parte. MLS / `PassWarp` / `WarpField` do body não entram no grafo facial.

8. `FaceMeshDetector` / `FaceMeshResult` / landmarks existem para o Field ler geometria. Não reabrem Mesh ACE, tessellation de produto nem MLS facial.

---

## 2. Arquitectura

### 2.1 Camadas e responsabilidades

| Camada | Ficheiros | Pode | Não pode |
|---|---|---|---|
| Infraestrutura | `displacement_field.dart`, `backward_bilinear_warp.dart` (`WarpRequest`, `WarpResult`) | ser **lida** por qualquer efeito e pelo lab | ser alterada para caber um efeito novo |
| Catálogo compartilhado | `region_catalog.dart`, `region_masks.dart`, `field_metrics.dart` | ganhar **entradas novas** de um efeito, sem mudar as já usadas por efeitos aprovados | mudar landmarks, dilatação ou métricas de um efeito aprovado |
| Field do efeito | `warp/v2/<efeito>/` | construir `dx`/`dy`, máscaras e métricas daquele efeito | importar renderer, controller, UI, export, ROI, Mesh ACE, MLS facial |
| Lab offline | testes em `test/beauty_engine/warp/v2/` + dumps `v2Raw` | chamar Field + renderer e gravar métricas | ligar preview, export ou Device Lab como substituto do produto |
| Device Lab | `facial_warp_v2_device_lab.dart` | dump paralelo de laboratório | devolver RGBA ao preview; escolher pipeline |
| Produto | `BeautyEngineController`, export tiled, painel, registry | na Sprint D/E, chamar Field + renderer do efeito aprovado | conter matemática do campo; criar orquestrador extra |

### 2.2 Infraestrutura congelada

Os tipos seguintes são contrato. Alterá-los para um efeito novo é critério de parada (secção 7).

- `DisplacementField` — um par `(dx, dy)` por pixel; sem RGBA; sem interpolar o campo.
- `WarpRequest` — `sourceRgba`, `width`, `height`, `field`.
- `WarpResult` — `rgba` (`v2Raw`), `coverage`, `invalidSource`.
- `BackwardBilinearWarp.apply` — único raster facial.

`DisplacementField.translation` é só teste sintético. Não faz parte de nenhum efeito de produto.

### 2.3 Pipeline única

Não existe compose facial, isolate facial, malha ACE, piecewise GPU facial, inpaint pós-warp facial, Extended ROI nem `FaceFilterPipeline.compose`.

O produto, quando um efeito está activo e há face:

1. Constrói o `DisplacementField` desse efeito.
2. Chama `BackwardBilinearWarp.apply`.
3. Segue para body / pele / cor, inalterados.

Se `face == null` ou a intensidade do efeito é 0, identidade facial (não chamar o renderer, ou campo zero — o efeito aprovado documenta qual dos dois).

### 2.4 Vários efeitos

Hoje o produto tem um efeito aprovado: **Jaw**.

Quando existir mais do que um efeito aprovado até Sprint C:

- cada um continua a gerar o seu próprio `DisplacementField`;
- nenhum escreve no Field do outro;
- a ordem de aplicação no preview/export é decisão explícita da Sprint D, documentada e aprovada;
- a composição **não** cria uma classe nova de orquestração (`WarpMixer`, `FacialWarpFacade`, `EffectSelector`);
- somar campos ou aplicar em sequência só entra se a Sprint D o declarar e os Fields aprovados permanecerem intocados.

Até essa aprovação, um efeito novo **não** se mistura com Jaw no preview.

### 2.5 Jaw já aprovado

Jaw é o efeito de referência. A matemática em `jaw_field.dart` está fechada.

- Amplitude lab: `t * 0.04 * faceWidth`.
- Só Δx. Protecções hard-zero. Métrica visual: gônios 58–288.
- Não mover, reescrever nem “organizar” Jaw como parte da sprint de outro efeito.

Jaw vive hoje em `warp/v2/jaw_field.dart` (raiz V2). Novos efeitos nascem em módulo próprio (`warp/v2/chin/`, …). Relocar Jaw não é pré-requisito de nenhum efeito novo.

---

## 3. Organização

Cada efeito tem o seu módulo. O módulo contém **apenas** o que esse efeito precisa.

```
lib/features/editor/beauty_engine/warp/v2/
    displacement_field.dart          # compartilhado — congelado
    backward_bilinear_warp.dart      # compartilhado — congelado
    region_catalog.dart              # compartilhado — só acrescentos
    region_masks.dart                # compartilhado — só acrescentos
    field_metrics.dart               # compartilhado — só acrescentos
    jaw_field.dart                   # Jaw aprovado — não alterar
    jaw/                             # opcional no futuro; não obrigar agora
    chin/
    face_slim/
    nose/
    eyes/
    mouth/
```

Testes do efeito:

```
test/beauty_engine/warp/v2/
    facial_warp_v2_displacement_field_test.dart   # contrato infra — não alterar
    facial_warp_v2_renderer_test.dart             # contrato renderer — não alterar
    facial_warp_v2_jaw_field_test.dart            # Jaw aprovado — não alterar
    facial_warp_v2_lab_test.dart                  # lab Jaw — não alterar o contrato
    <efeito>_field_test.dart
    <efeito>_lab_test.dart
```

Regras do módulo:

- Sem ficheiros “utils” partilhados entre efeitos “para reutilizar depois”.
- Sem copiar ROI, Telea, Mesh ACE ou MLS para dentro do módulo.
- Relatórios do efeito: `docs/beauty/v2-<efeito>-<sprint>.md` (A/B/C/D/E). Não editar este ficheiro de regras para registar um sprint.

Todo Field V2 deve ser autocontido.

Nenhum Field depende de outro Field V2. Cada Field é autocontido e constrói seu DisplacementField apenas a partir de FaceMeshResult, Size e seus próprios parâmetros.

É proibido importar outro Field V2.

Dependências permitidas:

- DisplacementField
- RegionMaskRaster
- MeshTopology
- RegionCatalog
- infraestrutura V2

Dependências proibidas:

- jaw_field.dart
- chin_field.dart
- face_slim_field.dart
- nose_field.dart
- eyes_field.dart
- mouth_field.dart

---

## 4. Fluxo obrigatório

Todo efeito segue **exactamente** estas etapas. Nunca pular. Nunca fundir duas sprints no mesmo PR “porque é pequeno”.

### Sprint A — Field

**Objectivo:** o efeito existe só como geometria.

- Construir somente o Field (`dx`/`dy`).
- Máscaras e métricas do efeito, se necessárias para provar o campo.
- Sem RGBA.
- Sem preview.
- Sem controller.
- Sem export.
- Sem slider na UI.
- Sem chamar `BackwardBilinearWarp`.

**Entrega:** módulo `warp/v2/<efeito>/`, testes de campo, relatório A.

**Aprovação:** o campo faz o que o efeito promete (direcção, domínio, protecções). Renderer e Jaw intactos.

### Sprint B — Laboratório offline

**Objectivo:** ver `v2Raw` sem produto.

- Compõe o Field da Sprint A com `BackwardBilinearWarp.apply`.
- Matriz mínima: fotos lab p01 / p05 / p12 × intensidades acordadas (padrão Jaw: 0 / 25 / 50).
- Métricas e dumps (`v2Raw`, coverage / `invalidSource` se relevantes).
- Sem controller, sem UI, sem export, sem Device Lab como caminho de produto.

**Entrega:** teste de lab, dumps, relatório B.

**Aprovação:** t=0 identidade; t>0 pixels mudam no domínio do efeito; protecções a zero; sem fill.

### Sprint C — Aprovação visual

**Objectivo:** um humano aceita o `v2Raw` das fotos lab.

- Sem código novo de produto.
- Sem “já ir ligando o slider”.
- Se a imagem for rejeitada, volta-se à Sprint A (Field) ou B (lab). Não se “corrige no renderer”.

**Entrega:** relatório C com veredicto explícito por foto/intensidade.

**Aprovação:** explícita. Sem ela, Sprint D não existe.

### Sprint D — Preview

**Objectivo:** o editor mostra o efeito já aprovado.

- Ligar o Field + renderer no `BeautyEngineController` (mesmo padrão de `applyJawWarp`).
- Slider / registry / `FaceFilterPipeline` só para a key desse efeito.
- Device Lab **não** é o preview. O produto chama o Field e o renderer **directamente**.
- Não alterar Jaw, renderer, `DisplacementField`, `WarpRequest`, `WarpResult`.

**Entrega:** wiring de preview, relatório D.

### Sprint E — Export

**Objectivo:** JPEG/export usa o mesmo Field + renderer do preview.

- Export não-tiled e tiled: o efeito corre no frame; tiles de body permanecem body.
- Sem raster facial paralelo, sem inpaint facial, sem caminho nativo extra.

**Entrega:** wiring de export, relatório E.

---

## 5. Aprovação

Nenhum efeito avança de sprint sem **aprovação explícita** do Leonardo (ou do sign-off escrito no relatório da sprint).

- “Os testes passaram” não é aprovação visual (Sprint C).
- “Já está no preview” não autoriza a Sprint E se a D não foi aprovada.
- Um efeito rejeitado na C não entra no controller “desligado por flag”.
- Relatório da sprint: o que mudou, o que **não** mudou (renderer, Jaw, infra), comando de teste, veredicto.

---

## 6. Critérios de aprovação por sprint

| Sprint | Passa se | Falha se |
|---|---|---|
| A | Field isolado; testes de domínio/protecção; zero RGBA; Jaw e renderer intocados | Matemática no controller; import do renderer; edição de Jaw |
| B | `v2Raw` lab nas fotos aprovadas; métricas; t=0 identidade; sem fill | Preview; Device Lab a substituir o lab offline; Telea |
| C | Aprovação visual escrita por foto | Seguir para D com “parece ok” verbal e sem relatório |
| D | Preview = Field aprovado + renderer; UI só da key nova | Wrapper, flag de pipeline, alteração de Jaw/renderer |
| E | Export = mesmo grafo do preview | Raster/export facial à parte; inpaint; GPU facial nova |

Testes de contrato que **não** se alteram para caber o efeito:

- `facial_warp_v2_displacement_field_test.dart`
- `facial_warp_v2_renderer_test.dart`
- `facial_warp_v2_jaw_field_test.dart`
- contratos de lab Jaw já aprovados

Pode-se **acrescentar** testes do efeito novo. Não se reescreve o contrato antigo.

---

## 7. Critérios de parada

Parar **imediatamente** e documentar o motivo (relatório da sprint, sem “resolver em silêncio”) se o efeito novo exigir:

1. Alterar `BackwardBilinearWarp` / a convenção `src = dest − displacement`.
2. Alterar `DisplacementField`, `WarpRequest` ou `WarpResult`.
3. Alterar `JawField` ou os testes de contrato Jaw.
4. Fill, Telea, clamp OOB, hole-fill ou inpaint para “fechar o buraco”.
5. Uma segunda pipeline, selector, adapter, wrapper ou facade.
6. Reintroduzir ROI, Mesh ACE, MLS facial, isolate facial ou `composeFaceField`.
7. GPU facial, piecewise-affine ou export nativo “só para este efeito”.
8. Flag que escolha entre V1 e V2, ou entre dois renderers faciais.
9. Mudar body / pele / cor para o efeito facial funcionar.

A frase de parada no relatório:

```
PARADA — o efeito <nome> exige alteração em <camada congelada>.
Motivo: <uma frase>.
Não foi implementado o atalho.
```

Depois da parada: não se “estica” a infra. Ou o efeito cabe no Field + renderer existentes, ou o efeito não entra.

---

## 8. Proibições

É proibido:

- alterar JawField já aprovado;
- alterar o renderer;
- alterar `DisplacementField`;
- alterar `WarpRequest`;
- alterar `WarpResult`;
- criar wrappers;
- criar adapters;
- criar nova pipeline;
- reintroduzir ROI / Mesh / MLS facial;
- copiar Telea, `ExtendedRoiPipeline`, ACE, isolate ou filtros MLS faciais para `warp/v2/`;
- usar o Device Lab como preview;
- ligar preview ou export antes da Sprint C aprovada;
- deixar código morto “para o próximo efeito”;
- criar `LegacyWarp`, `WarpSelector`, `FacialWarpV2Facade` ou bridges;
- alterar testes de contrato V2 já aprovados para o efeito novo passar.

---

## 9. Estabilidade do sistema

1. **Um efeito, um Field.** Se o Field não chega, o renderer não se “ajuda”.
2. **O renderer não conhece o efeito.** Sem landmarks, sem máscaras, sem nome de tool dentro de `BackwardBilinearWarp`.
3. **O Field não conhece o produto.** Sem `BeautyEngineController`, sem UI, sem export.
4. **Jaw é regressão permanente.** Qualquer sprint de outro efeito corre `flutter test test/beauty_engine/warp/v2/` e os testes Jaw têm de continuar a passar sem alteração de expectativa.
5. **Catálogo compartilhado é append-only** relativamente a efeitos aprovados. Acrescentar `chinHandles` é permitido. Mudar o conjunto dos gônios 58–288 não é.
6. **Identidade em t=0** é lei: `v2Raw` byte-igual à fonte nas fotos lab.
7. **Protecções hard-zero** de um efeito aprovado não podem passar a receber deslocamento por causa de outro efeito (na Sprint A/B/C do novo; na D, a composição aprovada tem de preservar este facto ou parar).
8. **Sem feature flag de emergência** que reabra a pipeline antiga.
9. **Sem paridade comercial como desculpa** para fill, GPU ou segunda malha. A V2 não promete Meitu. Promete um Field + um remap bilinear.
10. Resíduos da pipeline antiga (`FaceWarpV3Config`, rollout, `FaceParams` mortos) **não** se usam e **não** se reactivam. Limpeza desses resíduos é tarefa à parte, nunca acoplada à sprint de um efeito.

---

## 10. Checklist antes de escrever código

- [ ] A sprint anterior deste efeito foi aprovada por escrito.
- [ ] O trabalho desta sprint cabe na tabela da secção 4.
- [ ] Não é necessário tocar em renderer, `DisplacementField`, `WarpRequest`, `WarpResult` ou Jaw.
- [ ] O módulo do efeito não importa produto nem pipeline abandonada.
- [ ] Os testes de contrato V2 existentes não serão editados.
- [ ] Não há wrapper, adapter, flag de pipeline nem “utilitário partilhado para depois”.

Se algum item falhar, não começar a sprint.
