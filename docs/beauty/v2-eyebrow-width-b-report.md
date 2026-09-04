# Eyebrow Width Sprint B — lab offline (`v2Raw`)

Lab: `EyebrowWidthField.build` (Sprint A vigente) + `BackwardBilinearWarp.apply` (V2.0). Só `v2Raw`. Sem fill, sem Telea, sem controller, sem UI, sem export.

A Sprint C está assinada: [`v2-eyebrow-width-c-report.md`](./v2-eyebrow-width-c-report.md).

```
EyebrowWidthField.build(face:, imageSize:, t:, tPhotoLeft:, tPhotoRight:)
BackwardBilinearWarp.apply(WarpRequest(...))
```

## O que foi feito

O teste `facial_warp_v2_eyebrow_width_lab_test.dart` carrega p01 / p05 / p12, constrói o Field e chama o renderer. Sem API nova em `lib/`.

Matriz: **3 fotos × 7 runs = 21**. Geral `t = −1 / −0,5 / 0 / 0,5 / 1`. L/R no extremo (`L100` = foto esquerda a +1, engrossa; `R100` = foto direita a +1, engrossa).

| Foto | Asset | Landmarks |
|---|---|---|
| p01 | `test/beauty_engine/warp/fixtures/phase12/p01-man-5021469.png` | `real-p01` |
| p05 | `test/beauty_engine/warp/fixtures/phase12/p05-young-woman.png` | `real-p05` |
| p12 | `test/beauty_engine/warp/fixtures/phase12/p12.jpg` | `real-p12` |

Field vigente: `dy = t_lado · 0.008 · faceWidth · w · s`, `dx = 0`. `s = tanh((y − y_eixo) / halfBand)`. `y_eixo` interpolado em X e misturado L/R com `leftFrac`.

## Gates

| Gate | Resultado |
|---|---|
| t=0: `v2Raw` byte-igual à fonte | passou nas 3 (hashes iguais aos labs Height/Head) |
| t=0: `invalidSource = 0` | passou |
| t≠0: `changedPixelCount > 0` | passou |
| t<0 Geral: `browsThin`, arco `dy > 0`, base `dy < 0` | passou |
| t>0 Geral: `browsThicken`, arco `dy < 0`, base `dy > 0` | passou |
| L100: 105/52 mexem, 334/282 ≈ 0 | passou |
| R100: 334/282 mexem, 105/52 ≈ 0 | passou |
| `dx` nulo | passou nas 21 |
| pico `< 0.012 × faceWidth` | passou (pior 2,81 px em p01; `0,0074 × faceWidth`) |
| Olhos p95 = 0; pálpebra ≤ 30% do pico | passou (lids 0) |
| Dobra externa (vão 70–33 / 300–263) ≤ 20% do pico | passou (≤ 0,021 px no extremo) |
| Landmark 10 ≈ 0; boca/nariz p95 = 0; fora do hull p95 = 0 | passou |
| `minDetJ > 0`; vinco < 0,30; degrau < 0,25 | passou (pior `minDetJ` 0,594 em p12 t=−1; vinco 0,213; degrau 0,012) |
| Fundo longe parado | `(8,8)` igual à fonte nas 21 |
| `invalidSource` **não** preenchido | `invalidCount = 0` nas 21 |
| Imports sem fill V1 / pipeline / controller / Altura | passou |

Os discos de métrica em L (`21`/`251`, têmporas) sobrepõem o pad do hull: `hairline.p95Abs` chega a ~1,8 px. **Não** é o landmark 10 (está a 0) nem a linha do cabelo do Field Hairline. Mesma sobreposição da Altura; não se fura L no campo.

## Testes

`flutter test test/beauty_engine/warp/v2/facial_warp_v2_eyebrow_width_field_test.dart`  
`flutter test test/beauty_engine/warp/v2/facial_warp_v2_eyebrow_width_lab_test.dart`

A 6/6. B 2/2. Fields vivos intocados. Zero alterações em `lib/`.

## Métricas das 21 runs

| Foto | run | changed | invalid | arco 334/105 | base 282/52 | minDetJ | hash v2Raw |
|---|---|---|---|---|---|---|---|
| p01 | −100 | 30020 | 0 | **+2,12 / +2,11** | −1,34 / −1,44 | 0,649 | `0313d388` |
| p01 | −50 | 25461 | 0 | +1,06 / +1,05 | −0,67 / −0,72 | 0,824 | `00960349` |
| p01 | 0 | 0 | 0 | 0 / 0 | 0 / 0 | 1,000 | `12c756dd` |
| p01 | 50 | 25025 | 0 | −1,06 / −1,05 | +0,67 / +0,72 | 0,940 | `134c0607` |
| p01 | 100 | 30341 | 0 | **−2,12 / −2,11** | +1,34 / +1,44 | 0,879 | `0a58f15a` |
| p01 | L100 | 15462 | 0 | −0 / **−2,11** | 0 / **+1,44** | 0,879 | `1ef353d6` |
| p01 | R100 | 15656 | 0 | **−2,12** / −0 | **+1,34** / 0 | 0,883 | `12ffc76b` |
| p05 | −100 | 15539 | 0 | **+1,69 / +1,54** | −1,61 / −1,72 | 0,634 | `094097ee` |
| p05 | −50 | 12333 | 0 | +0,85 / +0,77 | −0,81 / −0,86 | 0,817 | `1133ea69` |
| p05 | 0 | 0 | 0 | 0 / 0 | 0 / 0 | 1,000 | `0ced20b4` |
| p05 | 50 | 11941 | 0 | −0,85 / −0,77 | +0,81 / +0,86 | 0,926 | `181444dc` |
| p05 | 100 | 15901 | 0 | **−1,69 / −1,54** | +1,61 / +1,72 | 0,852 | `12dd4ef3` |
| p05 | L100 | 7460 | 0 | −0 / **−1,54** | 0 / **+1,72** | 0,853 | `1f435808` |
| p05 | R100 | 8522 | 0 | **−1,69** / −0 | **+1,61** / 0 | 0,852 | `1d6452d0` |
| p12 | −100 | 20515 | 0 | **+1,83 / +1,88** | −1,61 / −1,38 | 0,594 | `0dee4332` |
| p12 | −50 | 16394 | 0 | +0,92 / +0,94 | −0,81 / −0,69 | 0,797 | `1c3b240b` |
| p12 | 0 | 0 | 0 | 0 / 0 | 0 / 0 | 1,000 | `1bcb2e94` |
| p12 | 50 | 16085 | 0 | −0,92 / −0,94 | +0,81 / +0,69 | 0,931 | `1b4b7ccd` |
| p12 | 100 | 20934 | 0 | **−1,83 / −1,88** | +1,61 / +1,38 | 0,863 | `0b06dfd0` |
| p12 | L100 | 10433 | 0 | −0 / **−1,88** | 0 / **+1,38** | 0,867 | `00a2dc23` |
| p12 | R100 | 10786 | 0 | **−1,83** / −0 | **+1,61** / 0 | 0,863 | `14cb4647` |

`outsideBrowZoneP95 = 0` nas 21. Olhos p95 = 0. Pico no extremo ~2,1–2,8 px (Altura no mesmo p01 era ~13 px). Hashes t=0 iguais aos do lab Height.

JSON: `.cursor/facial-warp-v2/eyebrow_width/B/summary.json` e `.../{p01,p05,p12}/{…}/metrics.json`.

## Dumps

Raiz: `.cursor/facial-warp-v2/eyebrow_width/B/`

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

- t positivo = sobrancelha **engrossa** (arco sobe, base desce; vão da pálpebra quase intacto)
- t negativo = sobrancelha **afina** (o contrário)
- L100 / R100 = um lado só, a engrossar
- Olhos e linha do cabelo (topo, landmark 10) devem ficar
- A dobra externa (vão cauda da brow → canto) deve ficar
- Comparar `p01/100/v2Raw.png` e `p01/-100/v2Raw.png` com `p01/0/original.png`
- A mudança é **pequena de propósito** (~2 px no arco em p01). Se não se vir, é o tecto de produto, não um Field morto

## Isolamento

- Lab em `test/`. Field em `warp/v2/eyebrow_width/` **intacto**.
- Os Fields vivos (incluindo Altura), o renderer e a cadeia **não** foram alterados.
- Zero fill no grafo. Sem slider, sem ícone Largura.

## Arquivos

**Criados**

- `test/beauty_engine/warp/v2/facial_warp_v2_eyebrow_width_lab_test.dart`
- `.cursor/facial-warp-v2/eyebrow_width/B/` — 21 pastas + `summary.json`
- `docs/beauty/v2-eyebrow-width-b-report.md` — este relatório

**Modificados em `lib/`:** nenhum.

## Sprint C

Assinada 2026-09-04. Relatório [`v2-eyebrow-width-c-report.md`](./v2-eyebrow-width-c-report.md).
