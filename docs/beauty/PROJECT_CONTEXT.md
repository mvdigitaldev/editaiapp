# PROJECT_CONTEXT — Facial Warp V2

**Fonte oficial do estado do projeto.**  
Última actualização: 2026-08-26 (V Shape: corte seco na curva; V Chin, Jaw e Cheekbones H intactos)

Todo chat novo começa aqui. Segue **somente** o estado deste ficheiro.  
Hipóteses antigas que não estejam neste documento **não existem**.

Contrato permanente (não substitui este ficheiro): [`FacialWarpV2-Development-Rules.md`](./FacialWarpV2-Development-Rules.md).

---

## Como usar

1. Ler este ficheiro primeiro.
2. Tratar o conteúdo como a memória canónica: decisões, estado, proibições, sprint actual.
3. Ignorar relatórios históricos, planos congelados e conversas anteriores quando contradisserem este documento.
4. Qualquer decisão nova, mudança de sprint, aprovação ou arquivo **actualiza este ficheiro no mesmo turno**. Sem memória só no chat.

---

## Papel da IA

A IA actua como **arquitecto** do Facial Warp V2.

- Sempre **criticar antes de implementar**.
- Sempre **propor documentação antes de código**.
- Sempre **entregar prompts em Markdown** para o Leonardo encaminhar ao Cursor (implementação noutro chat, se necessário).
- Não avançar sprint sem aprovação explícita escrita.
- Não “resolver em silêncio” uma contradição com este documento ou com as regras V2.

---

## Estado actual

| Peça | Estado |
|---|---|
| **Jaw** | Aprovado. Vivo no produto (`jaw`). Encerrado. Não alterar. |
| **Chin** | Reaberto **só** para calibração bipolar Chin Length. Vivo (`chin`, «Tamanho do queixo»). Não assinado no editor. Relatório [`v2-chin-length-bipolar.md`](./v2-chin-length-bipolar.md). **Intacto** no V Chin. |
| **V Chin** | Aprovado. Vivo no produto (`v_chin`, «V do queixo»). Encerrado. Não alterar. Relatório [`v2-v-chin.md`](./v2-v-chin.md). **Intacto** no V Shape. |
| **V Shape** | Em inspecção. Key `v_shape` («Formato V»). Sem C. Relatório [`v2-v-shape.md`](./v2-v-shape.md). |
| **Face Slim** | Arquivado. Lab A/B no disco. Sem C/D/E. Sem slider. Não promover. Não renomear para Cheekbones. |
| **Roadmap de produto** | Aprovado. Adenda: V Shape em inspecção. Face Rig congelado. |
| **Cheekbones** | Em desenvolvimento. Hipótese H vigente (crista oval). Inspecção no editor. Sem C. Relatório [`v2-cheekbones-h-report.md`](./v2-cheekbones-h-report.md). **Intacto** no V Shape. |

Pipeline viva no produto:

```
RGBA → applyJawWarp → applyChinWarp → applyVChinWarp → applyVShapeWarp → applyCheekbonesWarp → Body → Skin → Color
```

Cheekbones está na cadeia de preview/export como inspecção da hipótese H. **Não** é Sprint C/D aprovada. V Chin está na mesma cadeia, **aprovado**. V Shape está na cadeia como inspecção.

---

## Arquitectura

Única pipeline facial:

```
Field
  ↓
DisplacementField
  ↓
BackwardBilinearWarp
```

- Cada efeito gera **apenas um** `DisplacementField`.
- O renderer é estável: `src = dest − displacement`.
- Sem clamp à borda. Sem Telea. Sem hole-fill.
- Nenhum Field importa outro Field V2.
- Infra congelada: `DisplacementField`, `WarpRequest`, `WarpResult`, `BackwardBilinearWarp`.
- Catálogo compartilhado é **append-only** relativamente a efeitos aprovados.

---

## Nunca

É proibido:

- MLS no renderer
- Face Rig (plano congelado; inválido como implementação)
- Receitas (blend ponderado de regiões / sliders compostos)
- Slider composto
- Alterar Jaw
- Alterar V Chin
- Alterar Chin **fora** da calibração bipolar de Chin Length
- Alterar Cheekbones H
- Alterar o renderer / `DisplacementField` / `WarpRequest` / `WarpResult`
- Segunda pipeline, wrapper, adapter, facade, flag V1↔V2
- Promover Face Slim
- Ligar preview/export antes da Sprint C aprovada
- Corrigir um efeito “ajustando” outro

---

## Fluxo obrigatório (todo efeito)

Nunca saltar. Nunca fundir sprints no mesmo PR.

| Sprint | Objectivo | Código de produto? |
|---|---|---|
| **A** | Field (`dx`/`dy`). Sem RGBA. Sem renderer. | Não |
| **B** | Lab offline: Field + `BackwardBilinearWarp` → `v2Raw` | Não |
| **C** | Aprovação visual humana das fotos lab | Não |
| **D** | Preview no editor (controller / slider da key) | Sim |
| **E** | Export = mesmo grafo do preview | Sim |

Aprovação de C é escrita. Sem ela, D não existe.

---

## Efeitos

### Jaw — encerrado

- Key: `jaw` (Mandíbula).
- Só Δx, para a midline. Energia nos gônios 58–288.
- Amplitude: `t * 0.04 * faceWidth`.
- Módulo: `warp/v2/jaw_field.dart`.
- Papel de produto: estreitar mandíbula nos gônios. Não é o Jawline completo do Meitu (falta pescoço). Suficiente. Não reabrir.

### Chin — reaberto (Chin Length bipolar)

- Key: `chin` («Tamanho do queixo»). Não é V Chin nem Double Chin.
- Só Δy. `dx = 0`. Crista no oval mento→172/397 (peso a descer até 0.08). Gônios **fora** da crista. 132/361 hard-zero. Hull/crista vigentes em [`v2-chin-length-bipolar.md`](./v2-chin-length-bipolar.md).
- `t ∈ [-1, 1]`. Centro = identidade. Esquerda alonga (`dy > 0` no 152); direita encurta (`dy < 0`).
- Amplitude: `0.07 × faceWidth`. σ⊥ `0.08 × faceWidth`.
- Preview: slider não bloqueia; o peso unitário da crista cacheia-se (t só escala `dy`). Métricas de lab não correm no preview.
- Módulo: `warp/v2/chin/`.
- Não é Sprint A–E nova. Pendente assinatura visual no editor.
- Fora deste passo: Double Chin, pescoço, Δx no gônio, alterar Jaw, Cheekbones, V Chin (encerrado).

### V Chin — encerrado

- Key: `v_chin` («V do queixo»). **Não** é `v_face`. Não é Chin Length nem V shape.
- Aprovado no editor (2026-08-26). Vivo em preview/export. Não reabrir.
- Só Δx para a midline. `dy = 0`. 152 ≈ 0 por simetria (função ímpar), sem ilha/entalhe. Gônios e 132/361 hard-zero.
- Crista: **148 → 176 → 149 → 150 → 136** / **377 → 400 → 378 → 379 → 365**. Pesos 1.00 → 0.14. Para antes de 172/58.
- Slider bipolar; Geral / Esquerda / Direita = lados da **foto**. `tPhotoLeft` / `tPhotoRight`.
- Amplitude: `0.080 × faceWidth`. σ⊥ `0.11 × faceWidth`. Rampa midline `0.11 × faceWidth` (fixa).
- **Esquerda = V** (Meitu, para a midline); direita = quadrado. `t < 0` puxa para dentro.
- Preview: cache do peso; métricas de lab fora do preview.
- Documento: [`v2-v-chin.md`](./v2-v-chin.md).
- Módulo: `warp/v2/v_chin/`. Não importa Chin/Jaw/Cheekbones.

### V Shape — em inspecção

- Key: `v_shape` («Formato V»). **Não** é `v_face`. Não é V Chin nem Jaw.
- Só Δx. `dy = 0`. Interior 148/176/149 hard-zero. 152 hard-zero. 132/361 hard-zero.
- Crista no oval: **58 → 172 → 136** / **288 → 397 → 365** (sopro→pico→mento). Pesos 0.20 → 1.00 → 0.62. **Não** 172→136→58 (volta atrás e corta a silhueta).
- Slider bipolar; Geral / Esquerda / Direita = lados da **foto**. `tPhotoLeft` / `tPhotoRight`.
- Amplitude: `0.055 × faceWidth`. σ⊥ `0.13 × faceWidth`. Hull pad `0.09`. Rampa de bordo `0.16 × faceWidth`. Rampa midline `0.10 × faceWidth` (fixa).
- **Direita = V** (Meitu, bordo para a midline); esquerda = quadrado. `t > 0` puxa para dentro.
- Preview: cache do peso; métricas de lab fora do preview.
- Documento: [`v2-v-shape.md`](./v2-v-shape.md). Sem C.
- Módulo: `warp/v2/v_shape/`. Não importa V Chin/Chin/Jaw/Cheekbones.

### Face Slim — arquivo

- Módulo `warp/v2/face_slim/` + testes A/B podem ficar no disco.
- Não é slider Meitu. Misturava mid-face + silhueta sem gônio.
- Sem Sprint C/D/E. Sem `applyFaceSlimWarp`. Sem key no painel.
- Código **não** se reutiliza como base do Cheekbones.

### Cheekbones — em desenvolvimento

- Key: `cheekbone` (“Maçãs do rosto”). Viva no painel como inspecção H. **Não** é C/D/E aprovada.
- Relatório vigente: [`v2-cheekbones-h-report.md`](./v2-cheekbones-h-report.md).
- Contrato: **Δx** para a midline. `dy = 0`. Mento hard-zero. Gônio **não** é hard-zero (cauda na crista, peso 0.22). Não substitui Jaw.
- Slider bipolar Meitu: centro = 0, sem %. Flag Geral / Esquerda / Direita = lados da **foto**. `tPhotoLeft` / `tPhotoRight` no mesmo Field (não é receita).
- Crista: polilinha oval **234→93→132→58** / **454→323→361→288**. `weight` = distância à crista, não `max(gaussianas)`.
- 323 e 454 estão no oval: a pina da orelha trava **fora** da silhueta. Disco centrado nesses IDs fazia o “S” (tragus parado).
- Primário de métrica direito: **352** (espelho de 123). **Não** 411 (espelho de 187).
- Calibração: t ∈ [-1, 1] por lado; amplitude `0.022 × faceWidth`; σ⊥ `0.09 × faceWidth`; rampa `0.12 × faceWidth`; rampa orelha `0.035 × faceWidth` na pina. Pesos da crista 0.80→0.22.
- Preview: mesmo padrão do Chin — slider não bloqueia; peso unitário cacheado (t / L / R só escala `dx`). Métricas de lab não correm no preview. Geometria H intacta.
- Sprint A encerrada (A1 carimbo; A2 arco interrompido). Hull/losango e dumps B antigos **não** são o Field no disco.
- **Próximo passo (Cheekbones):** Sprint C quando Leonardo assinar as fotos lab. H **não** se altera. V Chin encerrado. V Shape não pisa H.
- Chin Length e V Chin são sliders distintos. Não “ajustar” um para compensar o outro.

---

## Roadmap de produto (aprovado)

**Adenda 2026-08-26 (V Shape).** Leonardo abriu o Formato V (`v_shape`): silhueta externa do queixo, sopro na curva da mandíbula, L/R da foto. Inspecção. Documento [`v2-v-shape.md`](./v2-v-shape.md). V Chin, Jaw e Cheekbones H intactos. Não é o arco maçã→mandíbula. C não assinada.

**Adenda 2026-08-26 (V Chin encerrado).** Leonardo fechou o V Chin no editor. Aprovado. Vivo (`v_chin`). Não alterar. Documento [`v2-v-chin.md`](./v2-v-chin.md).

**Adenda 2026-08-26 (V Chin aberto).** Leonardo abriu o menu V Chin (`v_chin`, «V do queixo»): forma da ponta, Δx, L/R da foto. Superado pelo fecho no mesmo dia.

**Adenda 2026-08-26 (Chin Length bipolar).** Leonardo reabriu o Chin **só** para slider bipolar (alongar + encurtar, rótulo «Tamanho do queixo»). Calibração vigente: amplitude `0.07 × faceWidth`, crista no oval até 172/397 (cauda 0.08, só Δy; gônios fora da crista). Preview de rosto sem debounce (coalesce). Documento [`v2-chin-length-bipolar.md`](./v2-chin-length-bipolar.md). Cheekbones H intacto.

Ordem seguinte **depois** de Cheekbones (C → D → E):

1. Temple
2. Hairline
3. Width / Jaw Angle — baixa prioridade (o Jaw já cobre o essencial)
4. Lift
5. Double Chin — bloqueado (falta pescoço)

V Chin: **feito** (aprovado 2026-08-26).  
V Shape: **em inspecção** (silhueta externa; não o arco maçã).

Fora do roadmap: Face Slim, Narrow Face, Smooth (pele, não Rosto).

Face Rig (`v2-face-rig-migration-plan.md`): **congelado**. Não implementar.

---

## Documentos canónicos vs. ignorar

**Seguir**

- Este ficheiro (`PROJECT_CONTEXT.md`)
- [`FacialWarpV2-Development-Rules.md`](./FacialWarpV2-Development-Rules.md)
- Relatório da sprint **aberta** do efeito actual
- Roadmap / audit / spec só se este ficheiro os apontar como vigentes

**Vigente para V Shape**

- [`v2-v-shape.md`](./v2-v-shape.md) — **Field e UI no disco**; inspecção no editor (não é C)

**Vigente para V Chin**

- [`v2-v-chin.md`](./v2-v-chin.md) — **aprovado e encerrado** (Field e UI no disco)

**Vigente para Chin Length bipolar**

- [`v2-chin-length-bipolar.md`](./v2-chin-length-bipolar.md) — calibração do slider `chin` (não é sprint nova)

**Vigentes para Cheekbones**

- [`v2-cheekbones-h-report.md`](./v2-cheekbones-h-report.md) — **Field e UI no disco**
- [`v2-product-audit.md`](./v2-product-audit.md) — aprovado (adenda: `cheekbone` já não é fantasma)
- [`v2-product-roadmap.md`](./v2-product-roadmap.md) — aprovado
- [`v2-cheekbones-spec.md`](./v2-cheekbones-spec.md) — spec de região **A**; emendada por H (gônio/oval)
- [`v2-cheekbones-plan.md`](./v2-cheekbones-plan.md) — plano A–E; A encerrada; H em inspecção
- [`v2-cheekbones-product-analysis.md`](./v2-cheekbones-product-analysis.md) — pesquisa encerrada; L/R e cauda mandibular confirmados no editor
- [`v2-cheekbones-a-report.md`](./v2-cheekbones-a-report.md) — A1 (arquivo)
- [`v2-cheekbones-a2-report.md`](./v2-cheekbones-a2-report.md) — A2 interrompida (arquivo)
- [`v2-cheekbones-a-lessons-learned.md`](./v2-cheekbones-a-lessons-learned.md) — síntese A1 vs A2
- [`v2-cheekbones-field-model-analysis.md`](./v2-cheekbones-field-model-analysis.md) — A1/A2; H ainda é `dx = A · w`
- [`v2-cheekbones-model-validation.md`](./v2-cheekbones-model-validation.md) — A1 vs A2 no código antigo

**Não usar como mapa do sistema actual**

- `30-estado-atual-arquitetura.md`, `31-sistema-facial-atual.md`, `32-extended-roi.md`
- Relatórios ROI / Mesh / MLS / pipeline abandonada
- Plano Face Rig (congelado)
- Plano Face Slim (arquivo; não continuar C/D/E)

---

## Como actualizar este ficheiro

No mesmo turno em que ocorrer qualquer um destes factos:

- sprint A/B/C/D/E começa, termina ou é rejeitada
- um efeito é aprovado, arquivado ou encerrado
- o roadmap muda
- uma proibição ou decisão arquitectural nasce ou morre
- a calibração vigente do efeito aberto muda de forma material

Actualizar: **Estado actual**, a ficha do efeito, **Próximo passo**, data no topo.  
Não apagar decisões; marcar o estado novo.  
Não despejar hipóteses de chat. Só o que ficou oficial.
