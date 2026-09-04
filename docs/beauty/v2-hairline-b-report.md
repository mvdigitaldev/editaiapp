# Hairline Sprint B — lab offline (`v2Raw`)

Lab: `HairlineField.build` (Sprint A vigente) + `BackwardBilinearWarp.apply` (V2.0). Só `v2Raw`. Sem fill, sem Telea, sem controller, sem UI, sem export.

A Sprint C (aprovação visual) **não foi iniciada**.

```
HairlineField.build(face:, imageSize:, t: hairline)
BackwardBilinearWarp.apply(WarpRequest(...))
```

## O que mudou nesta B

A primeira B (Δy-only no landmark 10) foi **rejeitada** por Leonardo: o contorno do cabelo não mexia. O 10 é a hairline do oval, 170–290 px abaixo do cabelo contra o fundo.

Field vigente: escala radial `D = −sign(t) · |t| · 0.10 · w · (p − 151)` e crista **levantada** ao cap. Infla de dentro para fora; desincha de fora para dentro.

## O que foi feito

O teste `facial_warp_v2_hairline_lab_test.dart` carrega p01 / p05 / p12, constrói o HairlineField e chama o renderer.

Matriz bipolar: **3 fotos × 5 intensidades = 15 runs**. `t = −0.50 / −0.25 / 0 / 0.25 / 0.50`.

| Foto | Asset | Landmarks |
|---|---|---|
| p01 | `test/beauty_engine/warp/fixtures/phase12/p01-man-5021469.png` | `real-p01` |
| p05 | `test/beauty_engine/warp/fixtures/phase12/p05-young-woman.png` | `real-p05` |
| p12 | `test/beauty_engine/warp/fixtures/phase12/p12.jpg` | `real-p12` |

## Gates

| Gate | Resultado |
|---|---|
| t=0: `v2Raw` byte-igual à fonte | passou nas 3 fotos |
| t=0: `invalidSource = 0` | passou |
| t≠0: `changedPixelCount > 0` | passou |
| t<0: `hairlineInflates`, `dy@crown < 0` | passou |
| t>0: `hairlineDeflates`, `dy@crown > 0` | passou |
| Têmporas \|d\| < 35% do pico no cap | passou (têmporas 0,00 nas 15) |
| Protecções p95 = 0, `minDetJ > 0` | passou (pior `minDetJ` 0,673 em p12 t=−0,5) |
| `invalidSource` não preenchido | `invalidCount = 0` nas 15 runs |
| Silhueta do cabelo (p05, t=±0,5) | topo **−7 / +7 px** contra o fundo |
| Imports sem fill V1 / pipeline / controller / outros Fields | passou |

## Testes

`flutter test test/beauty_engine/warp/v2/facial_warp_v2_hairline_field_test.dart`  
`flutter test test/beauty_engine/warp/v2/facial_warp_v2_hairline_lab_test.dart`

A 6/6. B 2/2. Os seis Fields vivos intocados.

## Métricas das 15 runs

| Foto | t | changed | invalid | dy@crown | Δy cap | temple \|d\| | minDetJ | hash v2Raw |
|---|---|---|---|---|---|---|---|---|
| p01 | −0,50 | 58165 | 0 | −9,99 | **−9,99** | 0,00 | 0,682 | `1efcd4e8` |
| p01 | −0,25 | 48508 | 0 | −5,00 | **−5,00** | 0,00 | 0,843 | `08f90ec0` |
| p01 | 0 | 0 | 0 | 0 | 0 | 0 | 1,000 | `12c756dd` |
| p01 | 0,25 | 48322 | 0 | +5,00 | **+5,00** | 0,00 | 0,915 | `010e5672` |
| p01 | 0,50 | 57903 | 0 | +9,99 | **+9,99** | 0,00 | 0,834 | `1d7b852a` |
| p05 | −0,50 | 29829 | 0 | −5,65 | **−5,65** | 0,00 | 0,773 | `12fe41e3` |
| p05 | −0,25 | 25604 | 0 | −2,83 | **−2,83** | 0,00 | 0,887 | `19e0db37` |
| p05 | 0 | 0 | 0 | 0 | 0 | 0 | 1,000 | `0ced20b4` |
| p05 | 0,25 | 25330 | 0 | +2,83 | **+2,83** | 0,00 | 0,928 | `197d5757` |
| p05 | 0,50 | 29368 | 0 | +5,65 | **+5,65** | 0,00 | 0,859 | `02dccf34` |
| p12 | −0,50 | 43497 | 0 | −8,82 | **−8,82** | 0,00 | 0,673 | `0a4a8857` |
| p12 | −0,25 | 36516 | 0 | −4,41 | **−4,41** | 0,00 | 0,838 | `0516f9a5` |
| p12 | 0 | 0 | 0 | 0 | 0 | 0 | 1,000 | `1bcb2e94` |
| p12 | 0,25 | 36032 | 0 | +4,41 | **+4,41** | 0,00 | 0,914 | `198339a0` |
| p12 | 0,50 | 42963 | 0 | +8,82 | **+8,82** | 0,00 | 0,831 | `0f1932e1` |

Protecções (olhos, brows, nariz, boca, centro, orelhas, maçãs, mandíbula) e `outsideHairlineZoneP95`: **0** nas 15 runs. Hashes t=0 iguais aos do lab Chin/Jaw (mesma fonte). `dx@crown ≈ 0`.

p01 tem a cabeça cortada no topo do crop: o inflar não tem pixels de fundo acima para mostrar o arco a crescer. Olhar **p05** (silhueta completa contra o cinzento).

JSON: `.cursor/facial-warp-v2/hairline/B/summary.json` e `.../{p01,p05,p12}/{-50,-25,0,25,50}/metrics.json`.

## Dumps

Raiz: `.cursor/facial-warp-v2/hairline/B/`

Por run, em `{p01,p05,p12}/{-50,-25,0,25,50}/`:

| Ficheiro | Conteúdo |
|---|---|
| `original.png` | foto fonte |
| `v2Raw.png` | saída do renderer (sem fill) |
| `coverage.png` | cobertura bilinear |
| `invalidSource.png` | origem inválida (vazia nesta matriz) |
| `displacementField.png` | dx→R, dy→G, centro 128, escala 12 |
| `influenceMap.png` | \|d\| normalizado |
| `protectedMask.png` | hard-zero Hairline |
| `ownershipMap.png` | R=protegido, G=hairlineActive, B=invalidSource |
| `metrics.json` | métricas + hash `v2Raw` |

### v2Raw (revisão visual = Sprint C)

Smear / ghost no `v2Raw` é esperado. Não se preenche.

- `.cursor/facial-warp-v2/hairline/B/p01/{-50,-25,0,25,50}/v2Raw.png`
- `.cursor/facial-warp-v2/hairline/B/p05/{-50,-25,0,25,50}/v2Raw.png`
- `.cursor/facial-warp-v2/hairline/B/p12/{-50,-25,0,25,50}/v2Raw.png`

Olhar o **contorno do cabelo contra o fundo**, não a pele da testa. t negativo = infla (de dentro para fora). t positivo = desincha (de fora para dentro). Têmporas, olhos e maçãs devem ficar parados. Comparar lado a lado: `p05/-50/v2Raw.png` e `p05/50/v2Raw.png` com `p05/0/original.png`.

## Isolamento

- Lab em `test/`. Field A em `warp/v2/hairline/` (esta B regenera dumps do Field novo).
- Os seis Fields vivos, o renderer e a cadeia **não** foram alterados.
- Zero fill no grafo. Sem slider, sem painel.

## Arquivos

**Criados / regenerados**

- `.cursor/facial-warp-v2/hairline/B/` — 15 pastas + `summary.json`

**Modificados em `lib/` nesta ronda:** só `warp/v2/hairline/` (Field A). Não é produto.

## Sprint C

Assinada 2026-09-03. Relatório [`v2-hairline-c-report.md`](./v2-hairline-c-report.md).
