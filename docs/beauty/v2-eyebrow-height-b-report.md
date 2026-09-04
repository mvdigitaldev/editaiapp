# Eyebrow Height Sprint B — lab offline (`v2Raw`)

Lab: `EyebrowHeightField.build` (Sprint A vigente) + `BackwardBilinearWarp.apply` (V2.0). Só `v2Raw`. Sem fill, sem Telea, sem controller, sem UI, sem export.

A Sprint C está assinada: [`v2-eyebrow-height-c-report.md`](./v2-eyebrow-height-c-report.md).

```
EyebrowHeightField.build(face:, imageSize:, t:, tPhotoLeft:, tPhotoRight:)
BackwardBilinearWarp.apply(WarpRequest(...))
```

## O que foi feito

O teste `facial_warp_v2_eyebrow_height_lab_test.dart` carrega p01 / p05 / p12, constrói o Field e chama o renderer.

Calibração 2026-09-04 (depois do lab inicial): Leonardo marcou os cantos externos da pálpebra superior. O `lidGate` passou a incluir a prateleira do terço externo e amostras no vão cauda→canto. Dumps refeitos. Amplitude `0.035` intacta.

Matriz: **3 fotos × 7 runs = 21**. Geral `t = −1 / −0,5 / 0 / 0,5 / 1`. L/R no extremo (`L100` = foto esquerda a +1; `R100` = foto direita a +1).

| Foto | Asset | Landmarks |
|---|---|---|
| p01 | `test/beauty_engine/warp/fixtures/phase12/p01-man-5021469.png` | `real-p01` |
| p05 | `test/beauty_engine/warp/fixtures/phase12/p05-young-woman.png` | `real-p05` |
| p12 | `test/beauty_engine/warp/fixtures/phase12/p12.jpg` | `real-p12` |

Field vigente: `dy = −t_lado · 0.035 · faceWidth · w`, `dx = 0`. Planalto no hull × rampa × `lidGate`. `leftFrac` contínuo.

## Gates

| Gate | Resultado |
|---|---|
| t=0: `v2Raw` byte-igual à fonte | passou nas 3 (hashes iguais aos labs Head/Chin/Hairline) |
| t=0: `invalidSource = 0` | passou |
| t≠0: `changedPixelCount > 0` | passou |
| t<0 Geral: `browsDrop`, `dy > 0` em 334/105 | passou |
| t>0 Geral: `browsLift`, `dy < 0` em 334/105 | passou |
| L100: 105 mexe, 334 ≈ 0 | passou |
| R100: 334 mexe, 105 ≈ 0 | passou |
| `dx` nulo | passou nas 21 |
| Olhos p95 = 0; pálpebra ≤ 30% do pico | passou (lids 0) |
| Dobra externa (vão 70–33 / 300–263) ≤ 20% do pico | passou (≤ 0,09 px no extremo; era ~70% do pico) |
| Landmark 10 ≈ 0; boca/nariz p95 = 0; fora do hull p95 = 0 | passou |
| `minDetJ > 0`; vinco < 0,30; degrau < 0,25 | passou (pior `minDetJ` 0,333 em p05 t=−1; vinco 0,230; degrau 0,052) |
| Fundo longe parado | `(8,8)` igual à fonte nas 21 |
| `invalidSource` **não** preenchido | `invalidCount = 0` nas 21 |
| Imports sem fill V1 / pipeline / controller / outros Fields | passou |

Os discos de métrica em L (`21`/`251`, têmporas) sobrepõem o pad do hull: `hairline.p95Abs` chega a ~8 px. **Não** é o landmark 10 (está a 0) nem a linha do cabelo do Field Hairline. C deve olhar se a têmpora anda de mais; não se fura L no campo (isso invertia, Sprint A).

## Testes

`flutter test test/beauty_engine/warp/v2/facial_warp_v2_eyebrow_height_field_test.dart`  
`flutter test test/beauty_engine/warp/v2/facial_warp_v2_eyebrow_height_lab_test.dart`

A 6/6. B 2/2. Fields vivos intocados.

## Métricas das 21 runs

| Foto | run | changed | invalid | dy 334 / 105 | minDetJ | hash v2Raw |
|---|---|---|---|---|---|---|
| p01 | −100 | 37707 | 0 | **+13,13 / +13,14** | 0,344 | `184a9c4b` |
| p01 | −50 | 34835 | 0 | +6,57 / +6,57 | 0,672 | `14e413f8` |
| p01 | 0 | 0 | 0 | 0 / 0 | 1,000 | `12c756dd` |
| p01 | 50 | 34973 | 0 | −6,57 / −6,57 | 0,795 | `0c738ea1` |
| p01 | 100 | 37598 | 0 | **−13,13 / −13,14** | 0,591 | `1887f4b0` |
| p01 | L100 | 19568 | 0 | −0 / **−13,14** | 0,615 | `0d433195` |
| p01 | R100 | 19883 | 0 | **−13,13** / −0 | 0,619 | `198b1208` |
| p05 | −100 | 20490 | 0 | **+9,92 / +9,95** | 0,333 | `00e6fe4e` |
| p05 | −50 | 18972 | 0 | +4,96 / +4,97 | 0,667 | `043ee70c` |
| p05 | 0 | 0 | 0 | 0 / 0 | 1,000 | `0ced20b4` |
| p05 | 50 | 18990 | 0 | −4,96 / −4,97 | 0,795 | `0618e424` |
| p05 | 100 | 20575 | 0 | **−9,92 / −9,95** | 0,590 | `1532e3cf` |
| p05 | L100 | 10158 | 0 | −0 / **−9,95** | 0,618 | `08f6a3c6` |
| p05 | R100 | 11206 | 0 | **−9,92** / −0 | 0,622 | `16b6db05` |
| p12 | −100 | 26945 | 0 | **+11,27 / +11,26** | 0,343 | `010e98c4` |
| p12 | −50 | 24613 | 0 | +5,63 / +5,63 | 0,672 | `0c8ca711` |
| p12 | 0 | 0 | 0 | 0 / 0 | 1,000 | `1bcb2e94` |
| p12 | 50 | 25015 | 0 | −5,63 / −5,63 | 0,795 | `16aa6a8f` |
| p12 | 100 | 27166 | 0 | **−11,27 / −11,26** | 0,590 | `1da761c6` |
| p12 | L100 | 13665 | 0 | −0 / **−11,26** | 0,618 | `0c8729d9` |
| p12 | R100 | 14547 | 0 | **−11,27** / −0 | 0,625 | `196dda8b` |

`outsideBrowZoneP95 = 0` nas 21. Olhos p95 = 0. 282/52 seguem o arco (ilha, não só o pico). Hashes t=0 iguais aos do lab Head.

JSON: `.cursor/facial-warp-v2/eyebrow_height/B/summary.json` e `.../{p01,p05,p12}/{…}/metrics.json`.

## Dumps

Raiz: `.cursor/facial-warp-v2/eyebrow_height/B/`

Por run, em `{p01,p05,p12}/{-100,-50,0,50,100,L100,R100}/`:

| Ficheiro | Conteúdo |
|---|---|
| `original.png` | foto fonte |
| `v2Raw.png` | saída do renderer (sem fill) |
| `coverage.png` | cobertura bilinear |
| `invalidSource.png` | origem inválida (vazia nesta matriz) |
| `displacementField.png` | dx→R, dy→G, centro 128, escala 12 |
| `influenceMap.png` | \|d\| normalizado |
| `browActive.png` | hull dilatado |
| `eyesMask.png` | hull dos olhos |
| `ownershipMap.png` | R=olhos, G=browActive, B=invalidSource |
| `metrics.json` | métricas + hash `v2Raw` |

### v2Raw (revisão visual = Sprint C)

Smear / ghost no `v2Raw` é esperado. Não se preenche.

- t negativo = sobrancelha **baixa** (vão pálpebra encolhe)
- t positivo = sobrancelha **sobe** (vão abre)
- L100 / R100 = um lado só
- Olhos e linha do cabelo (topo, landmark 10) devem ficar
- A dobra externa (vão cauda da brow → canto) deve ficar; não ir com a ilha
- Comparar `p01/100/v2Raw.png` e `p01/-100/v2Raw.png` com `p01/0/original.png` (é a cara que Leonardo marcou)

## Isolamento

- Lab em `test/`. Field em `warp/v2/eyebrow_height/` (calibração da dobra no `lidGate`; amplitude intacta).
- Os Fields vivos, o renderer e a cadeia **não** foram alterados.
- Zero fill no grafo. Sem slider, sem tab Sobrancelha.

## Arquivos

**Criados**

- `test/beauty_engine/warp/v2/facial_warp_v2_eyebrow_height_lab_test.dart`
- `.cursor/facial-warp-v2/eyebrow_height/B/` — 21 pastas + `summary.json`
- `docs/beauty/v2-eyebrow-height-b-report.md` — este relatório

**Modificados em `lib/` na calibração da dobra (2026-09-04):** `eyebrow_height_masks.dart`, `eyebrow_height_field.dart`, `eyebrow_height_metrics.dart`. Amplitude e IDs do hull da brow intactos.

## Sprint C

Assinada 2026-09-04. Relatório [`v2-eyebrow-height-c-report.md`](./v2-eyebrow-height-c-report.md).
