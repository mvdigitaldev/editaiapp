# Face Slim Sprint B — lab offline (`v2Raw`)

Lab: `FaceSlimField.build` (Sprint A) + `BackwardBilinearWarp.apply` (V2.0). Só `v2Raw`. Sem fill, sem Telea, sem controller, sem UI, sem export, sem Device Lab. **Nenhum ficheiro em `lib/` foi alterado.**

A Sprint C (aprovação visual) **não foi iniciada**.

```
FaceSlimField.build(...)
        ↓
DisplacementField

BackwardBilinearWarp.apply(...)
        ↓
WarpResult / v2Raw
```

## O que foi feito

O teste `facial_warp_v2_face_slim_lab_test.dart` carrega p01 / p05 / p12, constrói o FaceSlimField e chama o renderer. Sem API nova em `lib/`.

Matriz: **3 fotos × 3 intensidades = 9 runs**. `face_slim` `t = 0 / 0.25 / 0.50`.

| Foto | Asset | Landmarks |
|---|---|---|
| p01 | `test/beauty_engine/warp/fixtures/phase12/p01-man-5021469.png` | `real-p01` |
| p05 | `test/beauty_engine/warp/fixtures/phase12/p05-young-woman.png` | `real-p05` |
| p12 | `test/beauty_engine/warp/fixtures/phase12/p12.jpg` | `real-p12` |

## Gates

| Gate | Resultado |
|---|---|
| t=0: `v2Raw` byte-igual à fonte | passou nas 3 fotos |
| t=0: `invalidSource = 0`, `changed = 0` | passou |
| t>0: `changedPixelCount > 0` | passou |
| t>0: `faceSlimNarrows`, \|d\| 58/288/152 = 0, protecções p95 = 0, `outsideSlimZoneP95` = 0, `minDetJ > 0` | passou |
| `invalidSource` não preenchido | `invalidCount = 0` nas 9 runs |
| Imports sem fill V1 / pipeline / controller / Device Lab / `jaw_field` / `chin_field` | passou |

## Testes

`flutter test test/beauty_engine/warp/v2/`

**36/36 passaram.** Contratos Jaw / Chin / renderer / displacement / lab Jaw / Device Lab / Face Slim A intactos. +2 casos desta B.

## Métricas das 9 runs

| Foto | t | changed | invalid | coverageMean | influenceMax | Δ largura | faceSlimNarrows | minDetJ | hash v2Raw |
|---|---|---|---|---|---|---|---|---|---|
| p01 | 0 | 0 | 0 | 255 | 0 | 0 | false | 1.000 | `12c756dd` |
| p01 | 0.25 | 27319 | 0 | 255 | 3.79 | **5.35** | true | 0.685 | `074efead` |
| p01 | 0.50 | 28323 | 0 | 255 | 7.58 | **10.70** | true | 0.370 | `1aeade44` |
| p05 | 0 | 0 | 0 | 255 | 0 | 0 | false | 1.000 | `0ced20b4` |
| p05 | 0.25 | 13780 | 0 | 255 | 2.87 | **5.75** | true | 0.671 | `1446d69b` |
| p05 | 0.50 | 14587 | 0 | 255 | 5.75 | **11.49** | true | 0.341 | `00a22ae5` |
| p12 | 0 | 0 | 0 | 255 | 0 | 0 | false | 1.000 | `1bcb2e94` |
| p12 | 0.25 | 18574 | 0 | 255 | 3.25 | **6.51** | true | 0.638 | `1839d009` |
| p12 | 0.50 | 19171 | 0 | 255 | 6.51 | **13.02** | true | 0.277 | `189323d3` |

`|d|` em 58, 288 e 152 = 0 nas 9 runs. Protecções (olhos, brows, nariz, boca, centro, orelhas, Jaw, Chin) e `outsideSlimZoneP95`: **0** nas 9 runs. Hashes t=0 iguais aos do lab Jaw/Chin (mesma fonte).

JSON: `.cursor/facial-warp-v2/face-slim/B/summary.json` e `.../{p01,p05,p12}/{0,25,50}/metrics.json`.

## Dumps

Raiz: `.cursor/facial-warp-v2/face-slim/B/`

Por run, em `{p01,p05,p12}/{0,25,50}/`:

| Ficheiro | Conteúdo |
|---|---|
| `original.png` | foto fonte |
| `v2Raw.png` | saída do renderer (sem fill) |
| `coverage.png` | cobertura bilinear |
| `invalidSource.png` | origem inválida (vazia nesta matriz) |
| `displacementField.png` | dx→R, dy→G, centro 128, escala 12 |
| `influenceMap.png` | \|d\| normalizado |
| `protectedMask.png` | hard-zero Face Slim |
| `ownershipMap.png` | R=protegido, G=slimActive, B=invalidSource |
| `metrics.json` | métricas + hash `v2Raw` |

### v2Raw (revisão visual = Sprint C)

Smear / ghost no `v2Raw` é esperado. Não se preenche.

- `.cursor/facial-warp-v2/face-slim/B/p01/{0,25,50}/v2Raw.png`
- `.cursor/facial-warp-v2/face-slim/B/p05/{0,25,50}/v2Raw.png`
- `.cursor/facial-warp-v2/face-slim/B/p12/{0,25,50}/v2Raw.png`

## Isolamento

- Lab só em `test/`. Zero mudanças em `lib/`.
- Renderer, JawField e ChinField **não** foram alterados.
- Zero fill no grafo.

## Observações técnicas

- p01 a t=0.50 continua com dx@411 mais fraco (−3.12 vs +7.58 em 123), herdado da Sprint A. O campo mesmo assim afina (`faceSlimNarrows`, Δ 10.7 px) e muda 28k pixéis.
- `minDetJ` desce com t (0.37 / 0.34 / 0.28 a t=0.50) mas permanece > 0. Sem fold, sem `invalidSource`.
- A percepção do afinamento nas três fotos é o gate da Sprint C. Esta B só prova geometria + `v2Raw` sem fill.

## Arquivos

**Criados**

- `test/beauty_engine/warp/v2/facial_warp_v2_face_slim_lab_test.dart`
- `docs/beauty/v2-face-slim-b-report.md` (este relatório)
- `.cursor/facial-warp-v2/face-slim/B/` — 9 pastas + `summary.json`

**Modificados em `lib/`:** nenhum.

## Sprint C

**Não iniciada.** Falta o sign-off visual humano das 9 imagens `v2Raw`. Sem essa aprovação, preview (D) não existe.
