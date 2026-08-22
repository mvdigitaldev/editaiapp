# P3 — design fechado (fill semântico da faixa released)

Só design. **Sem implementação.** Default A permanece. Renderer, Telea, `amplitudeScale`, limiar `0.58` e flags experimentais antigas não entram nesta proposta.

Evidência P0/P1/P2 (p01 jaw 50%, A): raw ghost≈0.986, released 3139/3139 unfilled, Telea=0, `trustedBackgroundPx=0`, `segments=off`, `hairTransport=0`, `earTransport=0`, `parsingStatus=unknown`. B≡A. C não reduz ghost. O fill actual **aumenta** p95 RGB 32→101.

---

## 1. Por que a fonte released é rejeitada

Não é um único limiar. São **três cadeias em série**, e a primeira já impede qualquer escrita.

### 1.1 `ContourBandFill.write` recusa o destino released

```72:74:lib/features/editor/beauty_engine/warp/extended_roi/contour_band_fill.dart
      if (masks.releasedLateralBand[i] == 1) {
        return false;
      }
```

`i` é o **destino**. Qualquer candidato válido morre aqui. Por isso `releasedFilledPx` não pode subir. O comentário (“só fundo validado”) não corresponde ao código: o dest released nunca recebe RGB.

### 1.2 A busca de fundo, se passasse do `write`, ainda falharia

Para dest released, `tryOriginalAt(..., background)` exige, nesta ordem:

1. fonte não está em `invalidSourceMask`;
2. classe ≠ `unknown` (`releasedUnknownRejectedPx`);
3. `oldPersonMask[src] < 128` e `person < 0.30` (`releasedPersonRejectedPx`);
4. `sdfOld[src] < -3` (`releasedOldContourRejectedPx`);
5. `sdfNew[src] < 0`;
6. classe ≠ skin e ≠ clothing;
7. `sourceAllowedForBackground` **e** classe **exactamente** `wall`;
8. `JawBackgroundInpaint.lumaAllowed` contra segmentos.

`sourceAllowedForBackground` na faixa released: só `wall` com confiança ≥ 0.45. `unknown` é rejeitado mesmo com confiança alta.

`lumaAllowed` com `jawBackgroundInpaintExperimental=false`: `buildTrustedMask` **não corre**, `lastSegments=[]`, `_segmentForDest` devolve null → **sempre false**. `segments=off` e `trustedBackgroundPx=0` no P0 são isto, não “fundo inexistente”.

Passo de vizinhos: dest released faz `continue` (`releasedNeighborRejectedPx`). Sem pele, sem vizinho de pessoa — correcto — mas também sem vizinho de fundo.

### 1.3 Telea não toca released

`HoleFillInpaint.fill` copia `holeMask` só se **não** for abandoned, released nem invalid. Telea=0 no jaw é política, não falha de iteração.

### 1.4 `JawBackgroundInpaint.apply` é código morto

Não há nenhuma chamada a `JawBackgroundInpaint.apply` no repositório. Só `buildTrustedMask` (atrás da flag experimental) e `lumaAllowed` (que, com segmentos vazios, bloqueia o fill). Não reactivar este caminho no P3.

### 1.5 Parsing não entra no classificador nos testes / no ROI se não for passado

`ExtendedRoiPipeline.compose` só usa parsing se o caller passar `FaceParsingResult`. O controller faz `parsing ?? lastFaceParsing`. Os harness P0/P1/P2 **não passam parsing**. Resultado: `lastParsingRequested=false`, `parsingStatus=unknown`.

Sem parsing, `ContourSourceClassifier` usa person + chroma:

- `person ≥ 0.70` + chroma de pele → `skin`
- `person ≥ 0.70` na banda do pescoço, sat baixa → `clothing` ou `unknown`
- `person < 0.25` + sat baixa → `wall`
- resto → `unknown`

Cabelo, orelha e pescoço **não existem** nesta taxonomia de 4 classes. Hair no parsing 19 classes é mapeado para `unknown`; neck/ear são mapeados para `skin`.

---

## 2. Classes e fontes que existem de verdade

### 2.1 Fill actual — `ContourSourceClass` (4)

`skin | clothing | wall | unknown`

`unknown` nunca é tratado como skin no classificador. Na faixa released também **não** é tratado como fundo.

### 2.2 Parsing 19 classes — `FaceParsingClass`

`background, skin, nose, eyes, brows, ears, mouth, lips, hair, hat, earRing, neck, neckL, cloth, others`

Origens (`FaceParsingSource`): `bisenet` | `mappedMulticlass` | `geometric`.

Detector: `FaceParsingDetector` → BiSeNet nativo ou `FaceParsingMapper`. Stub desktop/testes devolve mapper/null.

### 2.3 Adaptador 6 classes — `FacePartsSegmentation` / `FacePartClass`

MediaPipe `selfie_multiclass_256x256`, 256×256, amostragem normalizada:

`background, hair, bodySkin, faceSkin, clothes, others`

Mapper:

| FacePartClass | FaceParsingClass |
|---|---|
| background | background |
| hair | hair |
| bodySkin | neck |
| faceSkin | skin |
| clothes | cloth |
| others | others |

**Não há classe ear** no modelo de 6 classes. Orelha só existe no parsing 19 classes (BiSeNet ou landmarks; o mapper geométrico marca olhos/boca/sobrancelhas, não orelhas).

`ParsingFallbackPolicy`: usa multiclass se `faceSkin` coverage ≥ 0.005; senão geométrico. Geométrico pinta elipse facial como skin e o resto como background — **não** é parsing de cabelo/orelha. Ausência ou fallback geométrico fraco ≠ protecção de cabelo.

### 2.4 Person mask

`PersonMask` (uint8 0–255, bilinear). Não mudou semanticamente. Nos testes ROI é um oval+pescoço **sintético**, não o selfie segmenter. Person alta no interior do oval faz a borda released parecer “pessoa” para os gates `person < 0.30`.

### 2.5 Testes existentes

Não há ficheiros unitários `contour_source_classifier_test` / `jaw_background_inpaint_test` / `contour_band_fill_test`.

- `extended_roi_v9_contour_test.dart`: testes de `sourceAllowedForSkin` / `sourceAllowedForBackground` (unknown na released é false; wall 0.45 na released é true).
- `extended_roi_preview_grid_test.dart`: lê `ContourBandFill.lastStats` e `JawBackgroundInpaint.lastSegments` (vazio com flag off).

---

## 3. Como usar fundo / pele / cabelo / orelha / pescoço / unknown

Nova taxonomia de **fill** (não substituir `ContourSourceClass` no default; camada P3):

`background | skin | hair | ear | neck | clothing | unknown`

### 3.1 Quando parsing/parts **existem neste frame** (`requested=true` e `!isEmpty`)

Mapear para a taxonomia P3 **sem colapsar cabelo/orelha em skin**:

- `background` → background
- `hair` → hair
- `earL` / `earR` → ear
- `neck` / `neckL` / `bodySkin` → neck
- `cloth` / `hat` / `clothes` → clothing
- pele facial e features internas → skin
- `others` / `earRing` / falta de cobertura → unknown

Fonte preferida: `FaceParsingResult` se `source != geometric` ou se multiclass tiver hair/clothes coverage útil. Se só `geometric`, tratar hair/ear como **unknown**, não como skin.

### 3.2 Quando parsing **não foi pedido ou está vazio** (`status=unknown`)

Registar `parsingStatus=unknown`. **Não** inventar hair/ear/neck. **Não** tratar unknown como parede nem como pessoa protegida.

Permitido só com person+luma, com o mesmo espírito actual:

- `person < 0.25` e saturação baixa → background (candidato a copiar)
- chroma de pele e `person ≥ 0.70` → skin (proibido na released)
- resto → unknown → **não copiar**

Cabelo contra fundo escuro, sem parts, fica unknown. Melhor buraco visível do que smear de pele ou “protecção” fantasma.

### 3.3 O que cada classe pode fazer na released (jaw)

| Classe fonte (original, outward) | Copiar para dest released? |
|---|---|
| background | sim, se person baixo e fora do old contour |
| hair | sim, same-class, se parsing/parts confirmar hair |
| clothing | sim, same-class (ombro/gola lateral) |
| neck | só se dest estiver abaixo do gônio / banda de pescoço, não na jowl |
| ear | sim, same-class, só com parsing 19 classes; senão unknown |
| skin | **não** (recria o ghost do maxilar) |
| unknown | **não** |

Pele continua a servir o fill **abandoned** (queixo), que já existe e não é o P3.

---

## 4. Transporte same-class antes de Telea

Novo passo de laboratório `SemanticReleasedFill`, **depois** do warp A e **antes** de `ContourBandFill`/Telea. Não altera `BackwardWarp2D`.

Para cada dest em `releasedLateralBand`:

1. Classe esperada = maioria da **anel outward** no original (4–12 px além de `sdfOld`, normal já em `SignedContourFields`), não a classe do dest (o dest é pele antiga).
2. Procurar no original ao longo da mesma normal, raio curto (reutilizar 4–12 px de `JawBackgroundInpaint`, sem os gates mortos de segmentos), um pixel com **a mesma classe**, `invalidSourceMask=0`, `sdfOld < 0`.
3. Se a classe esperada for background: exigir `person < 0.30` na fonte.
4. Se hair/ear/clothing/neck: exigir parsing/parts **deste frame**; senão skip (unknown).
5. Copiar RGB do original (nearest ou bilinear). Sem blend com o warped no core da faixa (P2 mostrou que blend-com-original no core do morph não é o problema; misturar pele warped com fundo é o smear do fill actual).
6. Destinos sem fonte same-class ficam unfilled. **Não** Telea. **Não** vizinho de pessoa. **Não** `JawBackgroundInpaint.apply`.

`ContourBandFill` no P3-lab: deixa de tentar released (já não escreve) e continua a tratar só `abandoned` / invalid interior. Telea permanece: holes reais, skip released/abandoned/invalid.

Ordem no pipeline A:

`warp A → SemanticReleasedFill? → ContourBandFill (abandoned) → Telea (holes reais)`

---

## 5. Limitar o domínio do fill

Entrar só se **todas** forem verdade:

- `releasedLateralBand[dest] == 1` (jaw) **ou** `holeMask` real fora dessa faixa (Telea já cuida; P3 não alarga Telea);
- `jawActive`;
- `sdfNew < 0` (fora da silhueta nova);
- não abandoned (queixo tem o outro fill);
- não dilatar a faixa (`invalidDilationRadius` continua 0);
- não escrever dentro de olhos/boca/nariz (âncoras já têm dy=0; opcional pin por landmark como no chin morph).

Não preencher a ROI inteira. Não inpaint de fundo experimental. Não composer. Não personTransport.

---

## 6. Métricas e testes a adicionar (quando implementar)

Métricas novas em `metrics.json` (dump `.cursor/extended-roi/p3/...`, sem sobrescrever P0/P1):

- `parsingStatus` (`unknown` / `empty` / `present`) + `parsingSource` + `partsUsed`
- histograma dest esperado e fonte aceite: background/hair/ear/neck/clothing/skin/unknown
- `sameClassCopiedPx`, `releasedFilledPx`, `releasedUnfilledPx`
- rejeições: `unknownRejected`, `skinRejected`, `personRejected`, `parsingAbsentRejected`
- ghost raw vs final, p95/max RGB original→raw e raw→final
- hash A, route, flags, `trustedBackgroundPx` (deve continuar 0 se experimental off)
- Telea filled (jaw deve continuar 0 na released)

Testes, **sem** subir 0.58:

1. Flag P3 off → hash p01 jaw 50% = `5580e606c837f9e2` (A/P0).
2. Identidade 0% com flag on e off.
3. Audit on/off, mesmo RGBA.
4. Preview/export A equivalentes com flag off.
5. Parsing ausente: `parsingStatus=unknown`; `sameClassCopied` de hair/ear = 0; nenhum dest released classificado como “protegido”.
6. Parsing sintético (máscara injectada, não o classificador heurístico a fingir parts): hair lateral copia hair; background copia background; skin não copia para released.
7. `releasedUnfilled` pode baixar com P3 on; p95 raw→final **não** pode repetir a regressão 32→101 do fill actual (limiar a definir **depois** do dump visual, não a priori).
8. Manter o teste `p01 chin+jaw` a falhar 0.58 até análise visual.

Não mascarar falhas novas de chin com threshold.

---

## 7. Default A e rollback

| | Default (A / produto) | P3 lab |
|---|---|---|
| Flag nova | `semanticReleasedFill = false` | `true` só em debug/harness |
| Renderer | A | A |
| `chinNeckPolicy` | baseline | baseline (P3 não muda o campo) |
| `curvatureCorrection` | on | on |
| `jawPersonTransport*` / composer / background inpaint experimental / `JawPersonBoundary` / `Phase9Local` / `faceSlimUsesRoi` | false | **continuam false** |
| `ContourBandFill.write` released | recusa (comportamento actual) | recusa; escrita só no passo novo |
| Telea | skip released | skip released |
| Rollback | flag off | RGBA = P0 |

Não promover P3 a default nesta implementação. Não ligar B/C. Não aumentar `amplitudeScale`.

`JawBackgroundInpaint` fica off. Se P3 precisar de amostragem outward, extrair a geometria da normal/SDF **sem** reactivar segmentos/lumaAllowed como gate global.

---

## 8. Fora de âmbito (não fazer no P3)

- Reescrever `ForwardBackwardWarp` / variantes B e C
- Telea mais agressivo ou Telea na released
- Fill semântico completo de abandoned/chin (já tem caminho próprio)
- Tratar parsing geométrico ou ausente como cabelo/orelha
- Implementar nesta etapa (aguarda aprovação explícita)

## 9. Critério de êxito (quando for a implementar)

p01/p05/p12 jaw 50% com a **mesma** fixture, grelha, flags e resolução: released deixa de estar 100% unfilled **apenas** com cópias same-class; ghost final ≤ ghost raw; p95 raw→final não explode como hoje; A com flag off permanece hash P0. Chin-only e curvatura não são deste sprint.
