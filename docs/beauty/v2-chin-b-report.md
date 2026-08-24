# Chin Sprint B — lab offline (`v2Raw`)

Lab: `ChinField.build` (Sprint A) + `BackwardBilinearWarp.apply` (V2.0). Só `v2Raw`. Sem fill, sem Telea, sem controller, sem UI, sem export, sem Device Lab. **Nenhum ficheiro em `lib/` foi alterado.**

A Sprint C (aprovação visual) **não foi iniciada**.

```
ChinField.build(face:, imageSize:, t: chin)
BackwardBilinearWarp.apply(WarpRequest(...))
```

## O que foi feito

O teste `facial_warp_v2_chin_lab_test.dart` carrega p01 / p05 / p12, constrói o ChinField e chama o renderer. Sem API nova em `lib/`.

Matriz: **3 fotos × 3 intensidades = 9 runs**. chin `t = 0 / 0.25 / 0.50`.

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
| t>0: `changedPixelCount > 0` | passou |
| t>0: `chinShortens`, gônios \|d\| = 0, protecções p95 = 0, `minDetJ > 0` | passou |
| `invalidSource` não preenchido | `invalidCount = 0` nas 9 runs |
| Imports sem fill V1 / pipeline / controller / Device Lab | passou |

## Testes

`flutter test test/beauty_engine/warp/v2/`

**31/31 passaram.** Contratos Jaw / renderer / displacement / lab Jaw / Device Lab / Chin A intactos. +2 casos desta B.

## Métricas das 9 runs

| Foto | t | changed | invalid | coverageMean | dy@152 | Δy 152 | gônios \|d\| | minDetJ | hash v2Raw |
|---|---|---|---|---|---|---|---|---|---|
| p01 | 0 | 0 | 0 | 255 | 0 | 0 | 0 | 1.000 | `12c756dd` |
| p01 | 0.25 | 10842 | 0 | 255 | −1.83 | **−1.83** | 0 | 0.873 | `0038fd55` |
| p01 | 0.50 | 11744 | 0 | 255 | −3.66 | **−3.66** | 0 | 0.746 | `00dc88cc` |
| p05 | 0 | 0 | 0 | 255 | 0 | 0 | 0 | 1.000 | `0ced20b4` |
| p05 | 0.25 | 4042 | 0 | 255 | −1.42 | **−1.42** | 0 | 0.886 | `0457a1d9` |
| p05 | 0.50 | 4779 | 0 | 255 | −2.83 | **−2.83** | 0 | 0.771 | `1fa18e24` |
| p12 | 0 | 0 | 0 | 255 | 0 | 0 | 0 | 1.000 | `1bcb2e94` |
| p12 | 0.25 | 6092 | 0 | 255 | −1.67 | **−1.67** | 0 | 0.877 | `1e1d8034` |
| p12 | 0.50 | 7238 | 0 | 255 | −3.33 | **−3.33** | 0 | 0.754 | `07fbfa58` |

Protecções (olhos, brows, nariz, boca, centro, orelhas, domínio Jaw) e `outsideChinZoneP95`: **0** nas 9 runs. Hashes t=0 iguais aos do lab Jaw (mesma fonte).

JSON: `.cursor/facial-warp-v2/chin/B/summary.json` e `.../{p01,p05,p12}/{0,25,50}/metrics.json`.

## Dumps

Raiz: `.cursor/facial-warp-v2/chin/B/`

Por run, em `{p01,p05,p12}/{0,25,50}/`:

| Ficheiro | Conteúdo |
|---|---|
| `original.png` | foto fonte |
| `v2Raw.png` | saída do renderer (sem fill) |
| `coverage.png` | cobertura bilinear |
| `invalidSource.png` | origem inválida (vazia nesta matriz) |
| `displacementField.png` | dx→R, dy→G, centro 128, escala 12 |
| `influenceMap.png` | \|d\| normalizado |
| `protectedMask.png` | hard-zero Chin |
| `ownershipMap.png` | R=protegido, G=chinActive, B=invalidSource |
| `metrics.json` | métricas + hash `v2Raw` |

### v2Raw (revisão visual = Sprint C)

Smear / ghost no `v2Raw` é esperado. Não se preenche.

- `.cursor/facial-warp-v2/chin/B/p01/{0,25,50}/v2Raw.png`
- `.cursor/facial-warp-v2/chin/B/p05/{0,25,50}/v2Raw.png`
- `.cursor/facial-warp-v2/chin/B/p12/{0,25,50}/v2Raw.png`

## Isolamento

- Lab só em `test/`. Zero mudanças em `lib/`.
- Renderer, JawField e ChinField **não** foram alterados.
- Zero fill no grafo.

## Arquivos

**Criados**

- `test/beauty_engine/warp/v2/facial_warp_v2_chin_lab_test.dart`
- `docs/beauty/v2-chin-b-report.md` (este relatório)
- `.cursor/facial-warp-v2/chin/B/` — 9 pastas + `summary.json`

**Modificados em `lib/`:** nenhum.

## Sprint C

**Não iniciada.** Falta o sign-off visual humano das 9 imagens `v2Raw`. Sem essa aprovação, preview (D) não existe.
