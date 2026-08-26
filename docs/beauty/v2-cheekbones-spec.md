# Especificação — Cheekbones V2 (análise)

**Estado:** spec de região da Sprint A. **Emendada** em 2026-08-26 pela hipótese H.

Vigente no código: [`v2-cheekbones-h-report.md`](./v2-cheekbones-h-report.md) e [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).  
Este texto abaixo **não** se reescreve: é o que gerou o plano A–E. Onde H contradiz, **H ganha**.

### Emenda H (2026-08-26)

| Item na spec A | Vigente em H |
|---|---|
| `t` em `[0, 1]` | `[-1, 1]` bipolar; L/R da foto independentes |
| Não inclui gônio; 58/288 a zero | Crista no oval **até ao gônio** (peso 0.22). Mento continua a zero. Não é o slider Jaw |
| Primários 123 / 411 | Métrica 123 / **352**. 411 é espelho de 187 — não usar |
| Não usar 58, 132, 234, 93, 323, 454 como handles | Crista **234→93→132→58** e espelho. 323/454 são oval, não cadeado de orelha |
| Hard-zero no domínio Jaw | Só Chin/olhos/nariz/boca (e pina da orelha fora do oval) |
| Key fantasma | Key no painel (inspecção; sem C) |

Produto aprovado: [`v2-product-audit.md`](./v2-product-audit.md), [`v2-product-roadmap.md`](./v2-product-roadmap.md). Jaw e Chin **encerrados**. Face Slim **arquivado** (lab). [`v2-face-rig-migration-plan.md`](./v2-face-rig-migration-plan.md) **congelado**.


Isto não é o plano de sprints. É a região, o isolamento e as métricas. O plano A–E segue o **mesmo template do Chin** (módulo novo, Jaw/Chin/renderer intocados).

Key de produto já existente (fantasma): `cheekbone` em `FaceParams` / l10n (“Maçãs do rosto”).

---

## 1. Região anatómica

O slider Cheekbones do Meitu marca o **mid-face lateral**, à altura das maçãs: setas **para dentro** em ambos os lados, **acima** da linha da mandíbula e **abaixo** das têmporas.

O Field deve controlar só essa faixa:

- **Inclui:** corpo da bochecha / eminência malar (entre o canto do olho e o sulco nasolabial, para fora da asa do nariz, para dentro da orelha).
- **Não inclui:** gônio (canto da mandíbula), corpo da mandíbula, mento, têmpora, testa, orelha, olho, nariz, boca.

Não é “afinar o rosto”. Não é Jawline. Não é Temple. É o volume **no meio da largura da cara**.

Direcção alinhada ao ícone Meitu: **Δx para a midline** em cada lado (estreitar / esculpir a maçã). Sem Δy de mento. Sem levar a silhueta mandibular.

---

## 2. Diferença para Jaw e Chin

| | Jaw (encerrado) | Chin (encerrado) | Cheekbones (proposto) |
|---|---|---|---|
| Sítio | silhueta mandibular, gônios 58/288 | ponta do mento 152 | mid-face, maçãs |
| Eixo | só Δx | só Δy | só Δx (ícone = setas horizontais) |
| Métrica viva | largura 58–288 cai | 152 sobe | largura **entre as maçãs** cai; 58/288 e 152 **não** mexem |
| Ícone Meitu | Jawline / Width / Jaw angle | Chin Length | Cheekbones |

Jaw e Chin já ocupam o andar de baixo da cara. Cheekbones ocupa o andar do meio. Se o campo chegar ao gônio ou ao 152, deixou de ser este slider.

O módulo Face Slim **não** é este efeito: misturava anel do oval + spline mandibular e forçava zero no gônio. Cheekbones não usa essa silhueta.

---

## 3. Landmarks MediaPipe

Já nomeados no repo (não inventar IDs novos sem Sprint A no sítio):

**Conjunto malar curto** — [`FaceWarpUtils`](../../lib/features/editor/beauty_engine/filters/face/face_warp_utils.dart):

- esquerda: `{116, 123, 147, 187}`
- direita: `{345, 352, 411, 425}`

**Cheek completo** — [`MeshTopology`](../../lib/features/editor/beauty_engine/mesh/mesh_topology.dart) `leftCheek` / `rightCheek` (iguais ao Face Slim):

- esquerda: `{116, 123, 147, 187, 207, 206, 203, 142, 126, 217}`
- direita: `{345, 352, 411, 425, 427, 436, 426, 423, 266, 371}`

**Primários — hipótese inicial, não verdade definitiva. Não são contrato.**

`123` e `411` são a hipótese de partida porque o laboratório Face Slim mostrou que `352` cai no disco da orelha em p01 e que `123`/`411` ficaram na bochecha. Isso **não** prova que sejam os melhores pontos para Cheekbones.

A Sprint A **confirma ou substitui** estes primários só com base no comportamento anatómico das maçãs nas três fotos lab (p05 primeiro). Pode escolher outro ID de `leftCheek` / `rightCheek`. **Não** pode ir para IDs Jaw/Chin/orelha/têmpora. A A usou 123/411 como **calibração inicial**; o contrato do módulo continua a ser a região malar, não estes IDs.

| Lado | Hipótese A | Origem da hipótese |
|---|---|---|
| Esquerda | 123 | Face Slim lab; não é gônio |
| Direita | 411 | 352 falhou (orelha) no mesmo lab |

Não usar como handles: `{58, 288, 132, 361, 172, 136, 365, 397}` (Jaw), `{152, 148, 176, 149, 377, 400, 378}` (Chin), `{323, 454}` (orelha), oval de têmpora `{127, 234, 356, 93}`.

**Hull activo (hipótese inicial):** união `leftCheek` ∪ `rightCheek`, **sem** IDs Jaw/Chin.

O hull completo da bochecha pode ser grande demais. A Sprint A **poderá reduzi-lo ao subconjunto malar** (`FaceWarpUtils` ou outro recorte das maçãs) se o hull cheio causar influência perceptível sobre a mandíbula ou o sulco nasolabial.

---

## 4. Como não interferir com Jaw e Chin

O mesmo princípio que o Chin usou com o Jaw: **hard-zero no domínio do outro efeito**, IDs **copiados no módulo Cheekbones**, sem importar `jaw_field.dart` nem `chin_field.dart`.

| Zona | Tratamento no Field Cheekbones |
|---|---|
| Olhos, brows, nariz, boca, faceCenter, orelhas | hard-zero (igual Jaw/Chin) |
| Domínio Jaw `{58, 288, 132, 361}` + `{172, 136, 365, 397}` | hard-zero |
| Domínio Chin `{152, 148, 176, 149, 377, 400, 378}` | hard-zero |
| Fora do hull das bochechas | zero |

Jaw e Chin **não se editam**. Não se “compensa” o Cheekbones mexendo gônios. Se o afinamento das maçãs só for visível a mexer 58/288 → **PARADA** (o mesmo critério que o plano Chin/Face Slim já usou no sentido inverso).

Sobreposição espacial: o hull da bochecha pode chegar perto do maxilar. A rampa de fronteira + os discos Jaw/Chin são o isolamento. Não reutilizar a spline mandibular do Face Slim.

---

## 5. Cabe no V2 actual?

**Sim.** Um efeito novo, um Field, o mesmo renderer.

```
CheekbonesField.build(face, size, t) → DisplacementField
BackwardBilinearWarp.apply(WarpRequest) → WarpResult
```

`t = parameters['cheekbone']` em `[0, 1]`. Sem face ou `t == 0`: identidade deste efeito.

Quando (e só quando) houver plano A–E aprovado:

- módulo `warp/v2/cheekbones/` (ou `cheek/`) — field, máscaras, métricas
- **não** alterar `jaw_field.dart`, módulo `chin/`, `DisplacementField`, `BackwardBilinearWarp`
- preview (D): `applyCheekbonesWarp` a seguir a `applyChinWarp`, mesmo padrão
- até C: zero controller / UI / export

Isto é o template Chin. Não exige mixer, receitas nem alterar as Development Rules.

Face Slim: **não** promover, **não** renomear para Cheekbones. Geometria de IDs pode ser **lida** como referência; o Field é código novo no módulo novo.

---

## 6. Métricas objectivas

Espelho do Jaw (largura) e do Chin (isolamento), noutro par de pontos.

| Métrica | Gate |
|---|---|
| `malarWidth` entre os primários **vigentes após a A** | `malarWidthAfter < malarWidthBefore` (`cheekbonesNarrows`) |
| `dx` no primário esquerdo / direito | esquerdo > 0, direito < 0 (para a midline) |
| `\|d\|` nos primários | na ordem de `influenceMax` (calibrar na A; Jaw usou > 40%) |
| `dy` no campo | 0 em todo o lado (se a A confirmar só Δx) |
| `\|d\|` em 58, 288, 152 | ≈ 0 (eps 0.5 px, como Chin) |
| Jaw/Chin/olhos/boca/nariz/orelhas p95 | ≤ 0.5 |
| `outsideCheekZoneP95` | ≤ 0.5 |
| `minDetJ` | > 0 |
| t=0 | campo zero; `v2Raw` = fonte |

Percepção (B/C): nas três fotos, as maçãs entram **sem** a linha 58–288 se mexer e **sem** o mento subir.

---

## 7. Imagens lab

As mesmas três do contrato V2. Nenhuma foto nova nesta spec.

| Foto | Porquê para Cheekbones |
|---|---|
| **p05** (`p05-young-woman`) | Melhor caso: sorriso empurra as maçãs para fora; o ícone Meitu (setas para dentro) lê-se aqui. Primeira foto de sign-off visual. |
| **p12** | Segundo sorriso / mid-face cheio; confirma que não é um truque de uma cara. |
| **p01** (`p01-man`) | Menos volume malar; serve para **não** vazar para o maxilar. Se o primário direito da hipótese (411) não estiver activo ou cair na orelha, a A escolhe outro ID de `rightCheek` — **sem** ir aos gônios. |

Matriz lab (quando houver B): p01 / p05 / p12 × `cheekbone` 0 / 0.25 / 0.50. t=0 identidade.

---

## 8. Relação com o roadmap

Este slider é a região anatómica **Cheek** (maçãs).

- **Não** implementa V Face / V shape.
- **Não** implementa Narrow Face.
- **Não** implementa Face Slim.
- **Não** implementa Temple nem Hairline.

Jaw e Chin continuam encerrados e independentes. Face Slim permanece arquivo de laboratório.

Qualquer reutilização futura desta região por sliders compostos está **fora do âmbito** desta spec e do plano A–E que se seguir.

---

## Fora desta spec

Implementação, slider no painel, Face Slim C/D/E, alterar Jaw/Chin, alterar regras V2.

**Próximo documento:** plano A–E de Cheekbones (template Chin), com primários e hull **hipótese → confirmação na A**.
