# P1.1 + P1.3 + P2-diagnóstico

Sprint controlada após o P0. **Não houve P3, P4, P5, P6 nem P7.** O default de produto permanece `A + chin baseline + curvatureCorrection=on`. `amplitudeScale` continua `0.5`.

Dumps: `.cursor/extended-roi/p1-p2/<fixture>/<scenario>/<intensity>/<variant>/`  
Resumo: `.cursor/extended-roi/p1-p2/summary.json`

## O que mudou no código

Flags de laboratório em `FaceWarpV3Config` (default = comportamento P0):

| Flag | Default | Função |
|---|---|---|
| `chinNeckPolicy` | `baseline` | `baseline` / `chinOnly` / `chinNeckLab` |
| `curvatureCorrection` | `true` | `curvature * 0.25` em `DenseWarpingField.compute` |
| `roiRendererVariant` | `A` | `A` current / `B` backward-regional / `C` forward-coverage |

- **P1.1:** o slider público continua no coupling 1:1. `chinOnly` aplica só core + submental curto (≤ 0.08 faceH). `chinNeckLab` é camada separada (amplitude 0.40, sigma 0.18 faceW, fade linear) e **não** entra no slider.
- **P1.3:** desligar curvatura zera o `dy` extra do bordo; o default permanece ligado.
- **P2:** A é o caminho atual. B força `blend=1` no core do morph. C usa splat forward como fonte primária. Contadores vivos em `WarpRenderStats`.
- Parsing não solicitado é `unknown`. Parsing ausente **não** conta como proteção.

## Testes

| Suíte | Resultado |
|---|---|
| `extended_roi_p1_p2_diagnostic_test.dart` | **7/7 passed** (identidade A/B/C, audit on/off, hash A = P0, preview/export A, chin-only, jaw-only, matriz 36 dumps) |
| `extended_roi_preview_grid_test.dart` | **15 passed, 1 failed** — `p01 chin+jaw` ghost **0.5907 > 0.58**. Limiar **não** foi alterado. |
| sprint 0–7 + routing | **75 passed** |
| `extended_roi_v9_contour_test.dart` | **5 failed** em `contourRoughnessPx` (4.309–4.477 vs teto V7 4.301). Os hashes RGBA batem com o P0 (`chin_puro` = `-789e86966bb9f37b`). Falha pré-existente de limiar apertado, **não** causada por esta sprint. Thresholds não foram mexidos. |

Confirmações pedidas:

- Variante A, flags experimentais off, p01 jaw 50%: hash **`5580e606c837f9e2`** (idêntico ao P0).
- Preview/export A: mesmo RGBA.
- Audit on/off A: mesmo RGBA.
- Identidade 0% A/B/C: RGBA = original.
- `parsingStatus=unknown`, `requested=false`, `used=false`, `segments=off`.

## P1.1 — chin-only vs chin-neck-lab (p01 chin 50%)

Âncoras na grelha (`dy` px). Olhos, boca, nariz, orelhas e gônio permanecem `dy≈0`.

| Variante | chinTip | submental | neck | coupling neck/tip | ghost raw→final |
|---|---|---|---|---|---|
| `A_baseline` | −17.25 | −17.33 | −17.36 | **1.00** | 0.709 → 0.454 |
| `A_chinOnly` | −15.59 | −6.57 | **0.00** | **0.00** | 0.885 → 0.544 |
| `A_chinNeckLab` | −12.50 | −5.60 | −2.50 | **0.20** | 0.840 → 0.617 |

Jaw-only continua horizontal: gônio `dx≈±9.8`, `dy` de grelha = 0 em chinTip, pescoço, olhos, boca, nariz e orelhas.

`jaw+chin` chin-only: soma dos componentes (`gonion dx≈±9.8` + chin tip `dy≈−15.6`) **sem** injetar o mesmo `dy` no pescoço (`neck_dy=0`).

O `chinTip_dy` do baseline é um pouco maior que o do chin-only porque a amostra bilinear no tip inclui células do pescoço 1:1. O coupling P0 não era só “pescoço segue o queixo”: o queixo amostrado também puxava o pescoço.

## P1.3 — curvatura on/off

p01 jaw 50%, mesma grelha 80×100:

| | on | off |
|---|---|---|
| `finalOutputHash` | `5580e606c837f9e2` | `-29fdd7b42cdb03db` |
| ghost raw/final | 0.986 / 0.977 | 0.986 / 0.977 |
| RGB p95/max original→raw | 32 / 92 | 32 / 92 |
| fill p95/max raw→final | 101 / 187 | 101 / 187 |
| gônio `warpDy` | −0.37 | **0** |
| inferior max `\|warpDy\|` | 0.375 | **0** |
| minDetJ / folds | 0.296 / 0 | 0.296 / 0 |

A curvatura injeta no máximo **<0.4 px** de `dy` no bordo/gônio. Não explica o smear. Chin 50% on/off produz o **mesmo** hash: o efeito é irrelevante no interior do queixo.

## P2 — renderer A/B/C (p01 jaw 50%)

| | A current | B backward-regional | C forward-coverage |
|---|---|---|---|
| hash | `5580e606c837f9e2` | **idêntico a A** | `-710641a103c5fcff` |
| ghost raw | 0.986 | 0.986 | 0.986 |
| fieldAppliedPx | 18628 | 18628 | 18628 |
| backwardUsedPx | 18628 | 18628 | 5640 |
| forwardSplatUsedPx | 12988 | 12988 | 12988 |
| blendWithOriginalPx | **0** | 0 | 0 |
| pullOntoPersonPx | 32 | 32 | 32 |
| holePx | 0 | 0 | 0 |
| rejectedPersonMaskPx | 13341 | 13341 | 13341 |
| rejectedInvalidSourcePx | 6961 | 6961 | 6961 |
| releasedUnfilled | 3139 | 3139 | 3139 |
| Telea | 0 | 0 | 0 |

B é no-op no jaw: A **já** não mistura com o original no core (`blend=0`). C troca a fonte (forward-only) e muda o hash, mas o ghost permanece 0.986 e a faixa released continua 100% unfilled. O defeito do jaw **não** é o renderer.

O mesmo padrão replica em p05 e p12: A≡B no hash; C difere; ghost raw ≈ 0.97–0.99.

## Artefactos

36 casos a 50% × p01/p05/p12 × jaw/chin/jaw_chin, mais identidade e audit. Cada dump tem:

`original.png`, `rawWarp.png`, `finalOutput.png`, `diff_original_to_raw.png`, `diff_raw_to_final.png`, `jawInfluence.png`, `releasedBand.png`, `invalidSourceMask.png`, `metrics.json`, `log.txt`.

18 `diff_curvature_on_off.png` (pares on/off de `A_baseline`).

## Recomendação (aguardar aprovação)

1. **Não promover nada.** Default continua A + baseline + curvature on.
2. **Não ligar `chinOnly` no slider.** O campo fica anatomicamente correcto, mas o ghost raw sobe (0.71→0.89) porque o pescoço deixa de acompanhar o queixo e a reconstrução actual não tapa esse vão.
3. **Não gastar a próxima sprint a reescrever o renderer.** B não muda o jaw. C muda pixels e não muda o ghost. `pullOntoPerson` no jaw é só 32 px.
4. **Curvatura:** deixar ligada. Não é a causa do smear.
5. **Próximo passo, se aprovado:** P3 fill semântico da faixa released do jaw (P0 já mostrou 3139/3139 unfilled e o fill a piorar p95 32→101). Sem Telea mais agressivo como substituto.
6. Manter o limiar 0.58 do `p01 chin+jaw` falho até haver análise visual de P3.

**PAREI.** Não comecei P3/P4.

## Ficheiros desta sprint

- `lib/features/editor/beauty_engine/config/face_warp_v3_config.dart`
- `lib/features/editor/beauty_engine/warp/extended_roi/artistic_morphs/chin_shortening.dart`
- `lib/features/editor/beauty_engine/warp/extended_roi/backward_warp_2d.dart`
- `lib/features/editor/beauty_engine/warp/extended_roi/extended_roi_payload.dart`
- `lib/features/editor/beauty_engine/warp/extended_roi/extended_roi_p0_dump.dart`
- `lib/features/editor/beauty_engine/warp/extended_roi/extended_roi_pipeline.dart`
- `test/beauty_engine/warp/extended_roi/extended_roi_preview_grid_test.dart`
- `test/beauty_engine/warp/extended_roi/extended_roi_p1_p2_diagnostic_test.dart`
- `docs/beauty/p1-p2-diagnostic-report.md`
