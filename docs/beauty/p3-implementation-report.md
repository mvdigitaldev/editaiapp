# P3 — SemanticReleasedFill (laboratório)

Implementação isolada após o design aprovado. **A flag permanece `semanticReleasedFill=false`.** Não houve P4. O default de produto continua `A + chin baseline + curvatureCorrection=on`. `amplitudeScale` continua `0.5`.

Dumps: `.cursor/extended-roi/p3/<fixture>/<scenario>/<intensity>/`  
Resumo: `.cursor/extended-roi/p3/summary.json`  
Dumps P0/P1/P2 **não** foram sobrescritos.

## Pré-voo

A ordem real do pipeline era `ContourMasks → warp A → ContourBandFill → Telea`. Parsing entra só como `FaceParsingResult?` em `compose`. `FacePartsSegmentation` (6 classes, **sem ear**) só chega ao ROI via mapper `mappedMulticlass` (hair→hair, bodySkin→neck, clothes→cloth). `FaceParsingClass` 19 classes inclui `earL`/`earR` apenas em `bisenet`. Parsing `geometric` pinta elipse de pele — **não** é cabelo/orelha/pescoço válido.

Nenhuma API foi inventada para parts/ear. A taxonomia P3 (`background|skin|hair|ear|neck|clothing|unknown`) é interna e **não** substitui `ContourSourceClass`.

## O que mudou no código

| Arquivo | Papel |
|---|---|
| `lib/features/editor/beauty_engine/config/face_warp_v3_config.dart` | Flag `semanticReleasedFill = false` |
| `lib/features/editor/beauty_engine/warp/extended_roi/semantic_released_fill.dart` | **Novo.** Fill same-class da faixa released |
| `lib/features/editor/beauty_engine/warp/extended_roi/extended_roi_pipeline.dart` | Ordem: warp A → `SemanticReleasedFill?` → `ContourBandFill` → Telea. Cópia do warped; `warpResult.rgba` intacto |
| `lib/features/editor/beauty_engine/warp/extended_roi/extended_roi_p0_dump.dart` | `p3Root`, métricas `semanticReleasedFill`, PNGs de classe |
| `test/beauty_engine/warp/extended_roi/extended_roi_p3_semantic_fill_test.dart` | **Novo.** Hashes, identidade, auditoria, parsing ausente, parsing sintético, rejeições |
| testes P0/P1–P2 | Reset da flag para `false` no `setUp` |

**Não alterado:** `BackwardWarp2D`, morphs, slider, `amplitudeScale`, curvatura, `chinNeckPolicy`, renderer A, `ContourBandFill.write` (released continua recusado), Telea, flags experimentais (continuam off), limiar `0.58` do teste `p01 chin+jaw`.

## Contrato da flag

- **Off:** RGBA do caminho A = P0. Validado em p01, p05 e p12 jaw 50%.
- **On, parsing ausente/unknown:** só `background`, com `person < 0.30`, `sdfOld < -3`, `sdfNew < 0`, confiança ≥ 0.45, fora de `invalidSourceMask`.
- **On, parsing presente e não geométrico:** `background` / `hair` / `neck` / `clothing` same-class. `ear` **somente** se `source == bisenet`.
- `skin` e `unknown` nunca são copiados. Sem fonte same-class, o destino fica unfilled — sem segunda classe.
- Destino válido: `jawActive` ∧ `releasedLateralBand==1` ∧ `sdfNew<0` ∧ `abandoned==0`. Destinos released∩abandoned são recusados (`rejected.region`).

## Testes

| Suíte | Resultado |
|---|---|
| `extended_roi_p3_semantic_fill_test.dart` | **7/7 passed** |
| `p01 chin+jaw` | **continua a falhar** ghost **0.5907 > 0.58**. Limiar **não** foi elevado. Flag P3 estava off. |

Confirmações:

- Flag off, p01/p05/p12 jaw 50%: hashes P0 **`5580e606c837f9e2`**, **`2d26e8a3dc1d7807`**, **`5a74ce412270b2df`**.
- Identidade 0% on e off = original.
- Auditoria on/off com flag off: RGBA idêntico.
- Parsing ausente: `parsingStatus=unknown`; cópias hair/ear/neck/clothing/skin = 0; `allowEar=false`; Telea/person-neighbor/`JawBackgroundInpaint` não usados.
- Parsing sintético (nota `synthetic`): background→background, hair→hair, clothing→clothing, ear→ear só com `bisenet`, skin rejeitado, `geometric` não produz hair.
- Rejeição: unknown, skin, invalid, person alto, `sdfOld` insuficiente, dest fora de released.

## Jaw 50% — flag on vs P0 (parsing unknown)

| | p01 | p05 | p12 |
|---|---|---|---|
| Hash A/P0 (flag off) | `5580e606c837f9e2` | `2d26e8a3dc1d7807` | `5a74ce412270b2df` |
| Hash flag on | `0754b4a37dbb6b95` | `6be67c7b271676fe` | `5a74ce412270b2df` * |
| ghost raw → final | 0.986 → **0.970** | 0.986 → **0.965** | 0.989 → **0.984** |
| sameClassCopiedPx | **172** background | **19** background | **13** background |
| releasedDomain (não abandoned) | 492 | 258 | 339 |
| releasedUnfilled (P3) | 320 | 239 | 326 |
| ContourBandFill releasedUnfilled | 3139 | 1390 | 1958 |
| skin copiado | 0 | 0 | 0 |
| hair/ear/neck/clothing | 0 | 0 | 0 |
| Telea released | 0 | 0 | 0 |
| trustedBackgroundPx | 0 | 0 | 0 |
| RGB p95 original→raw | 32 | 18 | 28 |
| RGB p95 raw→final | 101 | 92 | 75 |

\* O fingerprint P0 amostra ~1/8192 dos bytes (`hashBytes`). 13 px em p12 podem cair fora da amostragem; o hash igual **não** prova RGBA idêntico.

`ghostFinal ≤ ghostRaw` em todos. `ContourBandFill` continua a escrever pele/vizinho **fora** de released; o p95 32→101 **não** é o P3 — é o fill pré-existente. P3 só copia RGB do original no anel outward 4–12 px (média ~4.4 px em p01).

A maior parte da faixa released em p01 (2647/3139) é também `abandoned` e foi recusada de propósito.

## Limitações

1. Sem parsing real neste harness, hair/ear/neck/clothing ficam unknown/unfilled. Só background heurístico (person+saturação) é copiado. **Isto é preferível a inventar conteúdo.**
2. `FacePartsSegmentation` não tem ear; ear só existe com parsing 19 classes (`bisenet`). O adaptador 6 classes **não** promove `others`/`skin` a ear.
3. Parsing geométrico/elíptico/ausente não gera hair/ear/neck.
4. `releasedUnfilled` do ContourBandFill continua 100% — esse passo **não** escreve released. A redução P3 está em `semanticReleasedFill.releasedUnfilledPx`.
5. O p95 raw→final 101 em p01 persiste por causa do ContourBandFill em destinos não-released. P3 não reabre esse passo.
6. `JawBackgroundInpaint.apply` continua código morto e desligado.

**Não declarar qualidade profissional** só porque `releasedUnfilled` do P3 desceu de 492 para 320. O smear do warp A permanece; 172 px de fundo em p01 são um recorte estreito da silhueta.

## Recomendação

Manter `semanticReleasedFill=false` até aprovação visual dos PNGs em `.cursor/extended-roi/p3/*/jaw/50/` (`original`, `rawWarp`, `finalOutput`, `diff_*`, `releasedBand`, `semanticExpectedClass`, `semanticSourceClass`, `semanticFilledMask`).

Próximo passo **só após essa aprovação**: ligar parsing 19 classes no harness (não no default de produto) para medir hair/ear, ou P4. Não promover a flag. Não começar P4 neste encerramento.
