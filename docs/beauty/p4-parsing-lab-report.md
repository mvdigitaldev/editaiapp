# P4 — parsing real em laboratório

Somente laboratório. **`semanticReleasedFill` continua `false` no default.** Sem P5/P6/P7. Sem promoção de same-class com parsing real.

## Pré-voo (APIs reais)

Não existe `FacePartsResult` neste repositório. O tipo é `FacePartsSegmentation` (`FacePartClass`: `background, hair, bodySkin, faceSkin, clothes, others`). **Não há ear.**

| Tipo | API usada |
|---|---|
| `FaceParsingDetector` | `detect({source, face, parts}) → FaceParsingResult?` |
| `FaceParsingResult` | `classes, width, height, source, confidence, classAt, coverageOf` |
| `FaceParsingSource` | `bisenet \| mappedMulticlass \| geometric` |
| `FacePartsDetector` | `detect(source) → FacePartsSegmentation?` |
| `FaceParsingMapper.build` | 6 classes + landmarks → 19 classes |

Nativo: `_supportsNativeMediapipe` = Android/iOS. Desktop/testes usam stubs.

- `FacePartsDetectorStub.detect` → `null`.
- `FaceParsingDetectorStub.detect` sem parts → mapper **geométrico** (elipse = skin).
- `detectFaceParsing` nativo (Android/iOS) **devolve `null`** até BiSeNet TFLite/CoreML (Sprint 4). Não foi simulado.

`requested=false`, `empty=true` ou `source=geometric` **não** são protecção de hair/ear/neck.

## Ambiente deste lab

`ParsingLabProbe.isNativeMediapipePlatform = false` (macOS / `flutter test`).

| Caso | Status | Motivo |
|---|---|---|
| A. ausente/unknown | **ran** | harness sem `parsing:` |
| B. mappedMulticlass | **blocked** | stub de parts devolve null; mapper geométrico **não** é B |
| C. BiSeNet/19 | **blocked** | modelo não empacotado; stub/mapper devolve `geometric`, rejeitado |

Contrato mapper (sintético, **rotulado**, não substitui B nas fotos): `FacePartsSegmentation` com hair/bodySkin/clothes/faceSkin → `mappedMulticlass` com hair/neck/cloth; `earL`/`earR` = 0.

## Dumps

`.cursor/extended-roi/p4/<fixture>/jaw/50/<absent\|mapped\|bisenet>/`

Nomes `stem_fixture/intensity.ext`. `frameAudit` e `total_ms` partilham `frameId`, `fixture`, `intensity`, hashes e `dir`. P0/P1/P2/P3 **não** foram sobrescritos.

Por caso: `faceParsingMask` (`ABSENT.txt` ou `BLOCKED.txt`), `availableClassMap`, `semanticExpectedClass`, `semanticSourceClass`, `semanticFilledMask`, original/raw/final/diffs, `metrics.json`, `log.txt`.

## Matriz jaw 50%

Flag on **só** no caso A, harness rotulado `p4_lab_absent`. B/C blocked correm com flag **off** (hashes P0).

| Fixture | Caso | Status | Flag | Hash | sameClass | hair/ear/neck | ghost raw→final |
|---|---|---|---|---|---|---|---|
| p01 | A absent | unknown | on | `0754b4a37dbb6b95` | 172 bg | 0/0/0 | 0.986→0.970 |
| p01 | B mapped | blocked | off | `5580e606c837f9e2` | 0 | — | 0.986→0.977 |
| p01 | C bisenet | blocked | off | `5580e606c837f9e2` | 0 | — | 0.986→0.977 |
| p05 | A absent | unknown | on | `6be67c7b271676fe` | 19 bg | 0/0/0 | 0.986→0.965 |
| p05 | B mapped | blocked | off | `2d26e8a3dc1d7807` | 0 | — | 0.986→0.969 |
| p05 | C bisenet | blocked | off | `2d26e8a3dc1d7807` | 0 | — | 0.986→0.969 |
| p12 | A absent | unknown | on | `5a74ce412270b2df` * | 13 bg | 0/0/0 | 0.989→0.984 |
| p12 | B mapped | blocked | off | `5a74ce412270b2df` | 0 | — | 0.989→0.987 |
| p12 | C bisenet | blocked | off | `5a74ce412270b2df` | 0 | — | 0.989→0.987 |

\* Fingerprint `hashBytes` pode omitir 13 px (igual P3).

Hashes P0 jaw 50% (flag off): p01 `5580e606c837f9e2`, p05 `2d26e8a3dc1d7807`, p12 `5a74ce412270b2df`.

p01 A: rgb p95 raw→final = 101, max = 187 (ContourBandFill **fora** de released, como P3). `trustedBackgroundPx=0`, Telea released=0, `usedPersonNeighbor=false`, `usedJawBackgroundInpaint=false`. Released∩abandoned continua recusado (`rejected.region=2647` em p01).

## Protecção semântica (código, flag off)

`allowEar` agora exige `source == bisenet` **e** cobertura real de `earL` ou `earR`. BiSeNet sem orelha na máscara não autoriza ear. `mappedMulticlass` nunca autoriza ear.

Skin continua sem cópia para released.

## Testes

- ausência/geometric não aceita hair/ear
- mappedMulticlass (mapper) reconhece hair/neck/bodySkin/clothing, ear=0
- BiSeNet aceita ear só com `earL`/`earR` presentes
- skin nunca copia
- flag off = hashes P0
- auditoria on/off RGBA idêntica
- p01→p05→p12 sem misturar logs
- limiar chin+jaw **0.58** intacto (`extended_roi_preview_grid_test.dart`)

## O que isto prova

Neste ambiente **não há cobertura real** de hair/ear/neck/clothing nas fotos p01/p05/p12. A fonte efectiva do caso A é unknown: só background heurístico. B e C estão blocked; não foram substituídos por elipse. **Não** há evidência para permitir same-class do P3 com parsing real.

## Não feito

- `semanticReleasedFill` default continua `false`
- P5/P6/P7 não iniciados
- BackwardWarp2D, morphs, slider, `amplitudeScale=0.5`, curvatura, chin policy, `ContourBandFill.write` e flags antigas intactos
