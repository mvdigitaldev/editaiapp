# Eyebrow End Sprint B — lab offline (`v2Raw`)

Lab: `EyebrowEndField.build` (Sprint A vigente) + `BackwardBilinearWarp.apply` (V2.0). Só `v2Raw`. Sem fill, sem Telea, sem controller, sem UI, sem export.

A Sprint C está assinada: [`v2-eyebrow-end-c-report.md`](./v2-eyebrow-end-c-report.md).

```
EyebrowEndField.build(face:, imageSize:, t:, tPhotoLeft:, tPhotoRight:)
BackwardBilinearWarp.apply(WarpRequest(...))
```

## O que foi feito

O teste `facial_warp_v2_eyebrow_end_lab_test.dart` carrega p01 / p05 / p12, constrói o Field e chama o renderer. Sem API nova em `lib/`.

Matriz: **3 fotos × 7 runs = 21**. Geral `t = −1 / −0,5 / 0 / 0,5 / 1`. L/R no extremo (`L100` = foto esquerda a +1, separa; `R100` = foto direita a +1, separa).

| Foto | Asset | Landmarks |
|---|---|---|
| p01 | `test/beauty_engine/warp/fixtures/phase12/p01-man-5021469.png` | `real-p01` |
| p05 | `test/beauty_engine/warp/fixtures/phase12/p05-young-woman.png` | `real-p05` |
| p12 | `test/beauty_engine/warp/fixtures/phase12/p12.jpg` | `real-p12` |

Field vigente: `dx = t_lado · 0.010 · faceWidth · w · band · s_inner · away`, `dy = 0`. `s_inner` por lado (336→300 / 107→70) e só depois mistura com `leftFrac`.

## Gates

| Gate | Resultado |
|---|---|
| t=0: `v2Raw` byte-igual à fonte | passou nas 3 (hashes iguais aos labs Width/Height/Head) |
| t=0: `invalidSource = 0` | passou |
| t≠0: `changedPixelCount > 0` | passou |
| t<0 Geral: `browsJoin`, dx 336 < 0, dx 107 > 0 | passou |
| t>0 Geral: `browsSeparate`, dx 336 > 0, dx 107 < 0 | passou |
| L100: 107 mexe, 336 ≈ 0 | passou |
| R100: 336 mexe, 107 ≈ 0 | passou |
| `dy` nulo | passou nas 21 |
| cauda 300/70 e arco 334/105 ≈ 0 | passou (sample a 0 nas 21) |
| pico `< 0.016 × faceWidth` | passou (pior 3,10 px em p01; `0,0082 × faceWidth`) |
| Olhos p95 = 0; pálpebra ≤ 30% do pico | passou (lids 0) |
| Dobra externa (vão 70–33 / 300–263) ≤ 20% do pico | passou (0) |
| Landmark 10 ≈ 0; boca/nariz p95 = 0; fora do hull p95 = 0 | passou |
| `minDetJ > 0`; vinco < 0,30; degrau < 0,25 | passou (pior `minDetJ` 0,792 em p05 t=−1; vinco 0,073; degrau 0,008) |
| Fundo longe parado | `(8,8)` igual à fonte nas 21 |
| `invalidSource` **não** preenchido | `invalidCount = 0` nas 21 |
| Imports sem fill V1 / pipeline / controller / Altura / Largura | passou |

O suporte é só o terço interno: `hairline.p95Abs = 0` nas 21 (os discos 21/251 da têmpora não sobrepõem, ao contrário da Altura/Largura). Não se fura L no campo.

## Testes

`flutter test test/beauty_engine/warp/v2/facial_warp_v2_eyebrow_end_field_test.dart`  
`flutter test test/beauty_engine/warp/v2/facial_warp_v2_eyebrow_end_lab_test.dart`

A 6/6. B 2/2. Fields vivos intocados. Zero alterações em `lib/`.

## Métricas das 21 runs

| Foto | run | changed | invalid | dx 336 / 107 | minDetJ | hash v2Raw |
|---|---|---|---|---|---|---|
| p01 | −100 | 5889 | 0 | **−2,31 / +2,35** | 0,845 | `00b43f7f` |
| p01 | −50 | 4791 | 0 | −1,16 / +1,17 | 0,922 | `061d4498` |
| p01 | 0 | 0 | 0 | 0 / 0 | 1,000 | `12c756dd` |
| p01 | 50 | 4719 | 0 | +1,16 / −1,17 | 0,940 | `124fcbd0` |
| p01 | 100 | 5872 | 0 | **+2,31 / −2,35** | 0,881 | `05e14863` |
| p01 | L100 | 3068 | 0 | −0 / **−2,35** | 0,881 | `0c601c8b` |
| p01 | R100 | 2909 | 0 | **+2,31** / −0 | 0,884 | `0fbc25e3` |
| p05 | −100 | 3456 | 0 | **−1,87 / +1,83** | 0,792 | `0d73e9c4` |
| p05 | −50 | 2724 | 0 | −0,93 / +0,91 | 0,896 | `0e930423` |
| p05 | 0 | 0 | 0 | 0 / 0 | 1,000 | `0ced20b4` |
| p05 | 50 | 2757 | 0 | +0,93 / −0,91 | 0,925 | `0f41e0e4` |
| p05 | 100 | 3513 | 0 | **+1,87 / −1,83** | 0,850 | `09f2c557` |
| p05 | L100 | 1733 | 0 | −0 / **−1,83** | 0,850 | `0f54d08e` |
| p05 | R100 | 1794 | 0 | **+1,87** / −0 | 0,862 | `1dc8ad85` |
| p12 | −100 | 3914 | 0 | **−1,83 / +1,84** | 0,868 | `0ea25d05` |
| p12 | −50 | 3129 | 0 | −0,91 / +0,92 | 0,934 | `14a5d86e` |
| p12 | 0 | 0 | 0 | 0 / 0 | 1,000 | `1bcb2e94` |
| p12 | 50 | 3143 | 0 | +0,91 / −0,92 | 0,936 | `0387bb54` |
| p12 | 100 | 3937 | 0 | **+1,83 / −1,84** | 0,873 | `0ffb5845` |
| p12 | L100 | 1957 | 0 | −0 / **−1,84** | 0,873 | `024955a2` |
| p12 | R100 | 2110 | 0 | **+1,83** / −0 | 0,873 | `1481cf2f` |

`outsideBrowZoneP95 = 0` nas 21. Olhos p95 = 0. Arco 334/105 e cauda 300/70 a 0 nas samples. Pico no extremo ~2,5–3,1 px (Largura no mesmo p01 era ~2,8 px no arco; Altura ~13 px). Hashes t=0 iguais aos do lab Width.

JSON: `.cursor/facial-warp-v2/eyebrow_end/B/summary.json` e `.../{p01,p05,p12}/{…}/metrics.json`.

## Dumps

Raiz: `.cursor/facial-warp-v2/eyebrow_end/B/`

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

- t negativo = pontas internas **juntam** (336 para a midline, 107 para a midline)
- t positivo = pontas internas **separam**
- L100 / R100 = um lado só, a separar
- Cauda, arco, olhos e linha do cabelo (topo, landmark 10) devem ficar
- Comparar `p01/100/v2Raw.png` e `p01/-100/v2Raw.png` com `p01/0/original.png`
- A mudança é **pequena de propósito** (~2,3 px nas pontas em p01). Se não se vir de longe, é o tecto de produto, não um Field morto

## Isolamento

- Lab em `test/`. Field em `warp/v2/eyebrow_end/` **intacto**.
- Os Fields vivos (incluindo Altura e Largura), o renderer e a cadeia **não** foram alterados.
- Zero fill no grafo. Sem slider, sem ícone Ponta.

## Arquivos

**Criados**

- `test/beauty_engine/warp/v2/facial_warp_v2_eyebrow_end_lab_test.dart`
- `.cursor/facial-warp-v2/eyebrow_end/B/` — 21 pastas + `summary.json`
- `docs/beauty/v2-eyebrow-end-b-report.md` — este relatório

**Modificados em `lib/`:** nenhum.

## Sprint C

Assinada 2026-09-04. Relatório [`v2-eyebrow-end-c-report.md`](./v2-eyebrow-end-c-report.md).
