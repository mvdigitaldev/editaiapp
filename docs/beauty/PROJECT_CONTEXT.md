# PROJECT_CONTEXT — Facial Warp V2

**Fonte oficial do estado do projeto.**  
Última actualização: 2026-08-26 (H crista oval confirmada no editor; docs alinhadas)

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
| **Chin** | Aprovado. Vivo no produto (`chin`). Encerrado. Não alterar. |
| **Face Slim** | Arquivado. Lab A/B no disco. Sem C/D/E. Sem slider. Não promover. Não renomear para Cheekbones. |
| **Roadmap de produto** | Aprovado. Próximo slider: Cheekbones. Face Rig congelado. |
| **Cheekbones** | Em desenvolvimento. Hipótese H vigente (crista oval). Inspecção no editor. Sem C. Relatório [`v2-cheekbones-h-report.md`](./v2-cheekbones-h-report.md). |

Pipeline viva no produto:

```
RGBA → applyJawWarp → applyChinWarp → applyCheekbonesWarp → Body → Skin → Color
```

Cheekbones está na cadeia de preview/export como inspecção da hipótese H. **Não** é Sprint C/D aprovada.

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
- Alterar Chin
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

### Chin — encerrado

- Key: `chin` (Queixo).
- Só Δy (152 sobe). `dx = 0`. Gônios a zero neste Field.
- Módulo: `warp/v2/chin/`.
- Papel de produto: Chin Length (encurtar). Não é V Chin nem Double Chin. Não reabrir.
- Nota 2026-08-26: Leonardo quer alinhar ao Meitu (sangria residual no maxilar) **depois** de gravar H. Só com aprovação explícita. Não misturar com Cheekbones.

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
- Sprint A encerrada (A1 carimbo; A2 arco interrompido). Hull/losango e dumps B antigos **não** são o Field no disco.
- **Próximo passo:** Sprint C quando Leonardo assinar as fotos lab. A seguir, Leonardo quer alinhar o **Chin** ao Meitu (sangria residual). Chin permanece encerrado até aprovação explícita para reabrir. Não “ajustar” Chin para compensar Cheekbones.

---

## Roadmap de produto (aprovado)

Leonardo indicou (2026-08-26), **depois** de gravar H: alinhar o Chin ao Meitu (sangria residual no maxilar). Isso **reabre Chin** só com aprovação escrita. Até lá o Chin permanece encerrado. Não misturar com Cheekbones.

Ordem seguinte **depois** de Cheekbones (C → D → E):

1. Temple
2. Hairline
3. Width / Jaw Angle — baixa prioridade (o Jaw já cobre o essencial)
4. V Chin
5. V shape — só depois de Cheek + Jaw + Chin existirem como sliders
6. Lift
7. Double Chin — bloqueado (falta pescoço)

Fora do roadmap: Face Slim, Narrow Face, Smooth (pele, não Rosto).

Face Rig (`v2-face-rig-migration-plan.md`): **congelado**. Não implementar.

---

## Documentos canónicos vs. ignorar

**Seguir**

- Este ficheiro (`PROJECT_CONTEXT.md`)
- [`FacialWarpV2-Development-Rules.md`](./FacialWarpV2-Development-Rules.md)
- Relatório da sprint **aberta** do efeito actual
- Roadmap / audit / spec só se este ficheiro os apontar como vigentes

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
