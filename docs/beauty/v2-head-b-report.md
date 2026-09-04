# Head Sprint B — lab offline (`v2Raw`)

Lab: `HeadField.build` (Sprint A vigente) + `BackwardBilinearWarp.apply` (V2.0). Só `v2Raw`. Sem fill, sem Telea, sem controller, sem UI, sem export.

A Sprint C foi assinada 2026-09-04. Relatório [`v2-head-c-report.md`](./v2-head-c-report.md).

```
HeadField.build(face:, imageSize:, t: head)
BackwardBilinearWarp.apply(WarpRequest(...))
```

## O que foi feito

O teste `facial_warp_v2_head_lab_test.dart` carrega p01 / p05 / p12, constrói o HeadField e chama o renderer.

Matriz bipolar: **3 fotos × 5 intensidades = 15 runs**. `t = −0.50 / −0.25 / 0 / 0.25 / 0.50`.

| Foto | Asset | Landmarks |
|---|---|---|
| p01 | `test/beauty_engine/warp/fixtures/phase12/p01-man-5021469.png` | `real-p01` |
| p05 | `test/beauty_engine/warp/fixtures/phase12/p05-young-woman.png` | `real-p05` |
| p12 | `test/beauty_engine/warp/fixtures/phase12/p12.jpg` | `real-p12` |

Field vigente: `D = w · (q − c) · (1 − 1/s) · min(1, R₊ / |q − c|)`, `s = 1 − 0.12 t`. `k = 0.12`. Sem crista. Sem hard-zero em olhos/boca.

## Gates

| Gate | Resultado |
|---|---|
| t=0: `v2Raw` byte-igual à fonte | passou nas 3 fotos (hashes iguais aos labs Chin/Hairline) |
| t=0: `invalidSource = 0` | passou |
| t≠0: `changedPixelCount > 0` | passou |
| t<0: `headGrows`, `s > 1` | passou |
| t>0: `headShrinks`, `s < 1` | passou |
| Fundo longe parado | `(8,8)` igual à fonte nas 15 |
| Fora do hull p95 = 0, `minDetJ > 0` | passou (pior `minDetJ` 0,518 em p12 t=−0,5) |
| Simetria 58/288 < 1,25 | passou |
| `invalidSource` **não** preenchido | passou: pixel inválido = RGBA da fonte |
| `invalid` fora do hull | 0 nas 15 |
| Imports sem fill V1 / pipeline / controller / outros Fields | passou |

## `invalidSource` no cap

No remap backward, encolher pede origem **mais longe** de `c`. Se o cabelo já está contra o topo do crop, `src` sai do rect.

| Foto | t<0 (cresce) | t>0 (encolhe) |
|---|---|---|
| p01 | 0 | **7 311 / 14 270**, todos no cap |
| p05 | 0 | **3 554 / 6 825**, todos no cap |
| p12 | 0 | 0 (há margem acima do cabelo) |

Isto **não** se preenche. O renderer deixa o destino (a fonte copiada). Smear / banda no topo do `v2Raw` a t>0 em p01 e p05 é esperado. Não é zoom de câmara: o fundo longe não anda.

## Testes

`flutter test test/beauty_engine/warp/v2/facial_warp_v2_head_field_test.dart`  
`flutter test test/beauty_engine/warp/v2/facial_warp_v2_head_lab_test.dart`

A 7/7. B 2/2. Os sete Fields vivos intocados.

## Métricas das 15 runs

| Foto | t | changed | invalid (cap) | s | dy@152 | \|D\| 58/288 | minDetJ | hash v2Raw |
|---|---|---|---|---|---|---|---|---|
| p01 | −0,50 | 465212 | 0 | 1,06 | **+14,10** | 11,35 / 11,09 | 0,737 | `0d60890e` |
| p01 | −0,25 | 447903 | 0 | 1,03 | +7,25 | 5,84 / 5,71 | 0,866 | `002be819` |
| p01 | 0 | 0 | 0 | 1,00 | 0 | 0 / 0 | 1,000 | `12c756dd` |
| p01 | 0,25 | 440992 | **7311** | 0,97 | −7,70 | 6,20 / 6,06 | 0,939 | `198083a8` |
| p01 | 0,50 | 451871 | **14270** | 0,94 | **−15,90** | 12,79 / 12,51 | 0,876 | `12ae91f0` |
| p05 | −0,50 | 218767 | 0 | 1,06 | **+9,92** | 8,24 / 8,71 | 0,755 | `0237075c` |
| p05 | −0,25 | 209730 | 0 | 1,03 | +5,10 | 4,24 / 4,48 | 0,875 | `04dbab0c` |
| p05 | 0 | 0 | 0 | 1,00 | 0 | 0 / 0 | 1,000 | `0ced20b4` |
| p05 | 0,25 | 204602 | **3554** | 0,97 | −5,42 | 4,50 / 4,76 | 0,939 | `0360dafb` |
| p05 | 0,50 | 208857 | **6825** | 0,94 | **−11,18** | 9,29 / 9,82 | 0,876 | `086237c0` |
| p12 | −0,50 | 365737 | 0 | 1,06 | **+11,09** | 9,30 / 9,48 | 0,518 | `0e559897` |
| p12 | −0,25 | 353002 | 0 | 1,03 | +5,71 | 4,78 / 4,88 | 0,755 | `19338aa0` |
| p12 | 0 | 0 | 0 | 1,00 | 0 | 0 / 0 | 1,000 | `1bcb2e94` |
| p12 | 0,25 | 352588 | 0 | 0,97 | −6,06 | 5,08 / 5,18 | 0,939 | `171f6112` |
| p12 | 0,50 | 364891 | 0 | 0,94 | **−12,50** | 10,48 / 10,69 | 0,876 | `05cd921f` |

`outsideHeadP95 = 0` nas 15. Vinco no núcleo ≤ 0,064. Degrau de entrada ≤ 0,015. Hashes t=0 iguais aos do lab Chin/Hairline (mesma fonte).

p01 tem a cabeça cortada no topo do crop: encolher pede pixels que não existem. Olhar **p05** e **p12** para a silhueta completa; em p01, o grow ainda se lê no queixo e nas laterais.

JSON: `.cursor/facial-warp-v2/head/B/summary.json` e `.../{p01,p05,p12}/{-50,-25,0,25,50}/metrics.json`.

## Dumps

Raiz: `.cursor/facial-warp-v2/head/B/`

Por run, em `{p01,p05,p12}/{-50,-25,0,25,50}/`:

| Ficheiro | Conteúdo |
|---|---|
| `original.png` | foto fonte |
| `v2Raw.png` | saída do renderer (sem fill) |
| `coverage.png` | cobertura bilinear |
| `invalidSource.png` | origem inválida (cap no shrink de p01/p05) |
| `displacementField.png` | dx→R, dy→G, centro 128, escala 12 |
| `influenceMap.png` | \|d\| normalizado |
| `headActive.png` | hull (original ∪ enlarge extremo) |
| `ovalMask.png` | `faceOval` |
| `ownershipMap.png` | R=oval, G=headActive, B=invalidSource |
| `metrics.json` | métricas + hash `v2Raw` |

### v2Raw (revisão visual = Sprint C)

Smear / ghost / banda no topo do `v2Raw` a t>0 em p01 e p05 é esperado. Não se preenche.

- `.cursor/facial-warp-v2/head/B/p01/{-50,-25,0,25,50}/v2Raw.png`
- `.cursor/facial-warp-v2/head/B/p05/{-50,-25,0,25,50}/v2Raw.png`
- `.cursor/facial-warp-v2/head/B/p12/{-50,-25,0,25,50}/v2Raw.png`

Olhar a **cabeça inteira** (cabelo + cara + queixo) contra o fundo, não um órgão. t negativo = cresce no sítio. t positivo = encolhe. Fundo nos cantos deve ficar parado. Comparar lado a lado: `p05/-50/v2Raw.png` e `p05/50/v2Raw.png` com `p05/0/original.png`. Em p12 o cap tem margem e o shrink não fura o rect.

## Isolamento

- Lab em `test/`. Field A em `warp/v2/head/` (intacto nesta B).
- Os sete Fields vivos, o renderer e a cadeia **não** foram alterados.
- Zero fill no grafo. Sem slider, sem painel, sem tab Proporção.

## Arquivos

**Criados**

- `test/beauty_engine/warp/v2/facial_warp_v2_head_lab_test.dart`
- `.cursor/facial-warp-v2/head/B/` — 15 pastas + `summary.json`
- `docs/beauty/v2-head-b-report.md` — este relatório

**Modificados em `lib/` nesta ronda:** nenhum.

## Sprint C

Assinada 2026-09-04. Relatório [`v2-head-c-report.md`](./v2-head-c-report.md). Sem slider.
