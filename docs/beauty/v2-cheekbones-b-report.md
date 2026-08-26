# Cheekbones Sprint B — lab offline (`v2Raw`)

**Arquivo da B sobre um Field antigo.** O lab em `facial_warp_v2_cheekbones_lab_test.dart` ainda existe; os dumps em `.cursor/facial-warp-v2/cheekbones/` de B **não** descrevem H. Vigente: [`v2-cheekbones-h-report.md`](./v2-cheekbones-h-report.md). Sprint C **não** foi assinada.


JawField, ChinField, renderer e regras V2 **não** foram alterados.

A Sprint C (aprovação visual) **não foi iniciada**.

```
CheekbonesField.build(face:, imageSize:, t: cheekbone)
BackwardBilinearWarp.apply(WarpRequest(...))
```

## O que foi feito

O teste `facial_warp_v2_cheekbones_lab_test.dart` carrega **p05 → p12 → p01**, constrói o CheekbonesField e chama o renderer. Sem API nova. Sem slider, preview ou export.

Matriz: **3 fotos × 3 intensidades = 9 runs**. cheekbone `t = 0 / 0.25 / 0.50`.

| Foto | Asset | Landmarks | Papel nesta B |
|---|---|---|---|
| p05 | `test/beauty_engine/warp/fixtures/phase12/p05-young-woman.png` | `real-p05` | primeira revisão |
| p12 | `test/beauty_engine/warp/fixtures/phase12/p12.jpg` | `real-p12` | segundo sorriso / mid-face |
| p01 | `test/beauty_engine/warp/fixtures/phase12/p01-man-5021469.png` | `real-p01` | vazamento para o maxilar |

## Calibrações desta sprint

O contrato continua a ser a **região malar**, não os IDs. Só constantes do módulo Cheekbones.

| Peça | A (semente) | B (vigente) | Justificativa |
|---|---|---|---|
| Amplitude | `t * 0.04 * faceWidth` | `t * 0.08 * faceWidth` | A semente dava Δ largura malar ~4–6 px a t=0.5; no `v2Raw` a redução das maçãs era demasiado subtil. Duplicar a semente dá ~9–12 px nas três fotos, `minDetJ` ainda > 0.5, Jaw/Chin a zero. Não é contrato. |
| Primários 123 / 411 | calibração A | **inalterados** | Activos, Δx para a midline, energia > 40% de `influenceMax`. Continuam calibração, não contrato. |
| Hull malar curto (dois lados, sem 352) | A | **inalterado** | Mapas B continuam dois lóbulos malar; hull cheio não foi necessário. |
| Rampa (`falloff` 0.10) | A | **inalterada** | Sem dobra no nariz/boca; `minDetJ > 0`. |
| Kernel (`sigma` 0.07) | A | **inalterado** | Energia nos primários suficiente após a amplitude. |

Não se criaram regiões novas nem sliders. Não se tocou na arquitectura.

## Gates

| Gate | Resultado |
|---|---|
| t=0: `v2Raw` byte-igual à fonte | passou nas 3 fotos |
| t=0: `invalidSource = 0` | passou |
| t>0: `changedPixelCount > 0` | passou |
| t>0: `cheekbonesNarrows`; 58/288/152 \|d\| = 0; protecções p95 = 0; `minDetJ > 0` | passou |
| `invalidSource` não preenchido | `invalidCount = 0` nas 9 runs |
| Mapas limitados às maçãs | `influenceMap` / `ownershipMap`: dois lóbulos; Jaw/Chin em protecção |
| Imports sem fill V1 / pipeline / controller / Device Lab / outros Fields | passou |

## Testes

`flutter test test/beauty_engine/warp/v2/`

**42/42 passaram.** Contratos Jaw / Chin / renderer / displacement / lab Jaw / Device Lab / Cheekbones A intactos. +2 casos desta B.

## Métricas das 9 runs

| Foto | t | changed | invalid | Δ largura malar | dx@123 | dx@411 | 58/288/152 | minDetJ | hash v2Raw |
|---|---|---|---|---|---|---|---|---|---|
| p05 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1.000 | `0ced20b4` |
| p05 | 0.25 | 3242 | 0 | **4.40** | +2.40 | −2.00 | 0 | 0.774 | `060ff409` |
| p05 | 0.50 | 3774 | 0 | **8.79** | +4.79 | −4.00 | 0 | 0.547 | `0a83c8df` |
| p12 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1.000 | `1bcb2e94` |
| p12 | 0.25 | 4743 | 0 | **5.19** | +2.80 | −2.40 | 0 | 0.770 | `1628e040` |
| p12 | 0.50 | 5266 | 0 | **10.39** | +5.59 | −4.80 | 0 | 0.539 | `02ccf8d9` |
| p01 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1.000 | `12c756dd` |
| p01 | 0.25 | 6525 | 0 | **5.80** | +3.20 | −2.60 | 0 | 0.768 | `05d95aa6` |
| p01 | 0.50 | 7209 | 0 | **11.60** | +6.40 | −5.20 | 0 | 0.537 | `120aab12` |

Protecções (olhos, brows, nariz, boca, centro, orelhas, domínio Jaw, domínio Chin) e `outsideCheekZoneP95`: **0** nas 9 runs. Hashes t=0 iguais aos do lab Jaw/Chin (mesma fonte).

JSON: `.cursor/facial-warp-v2/cheekbones/B/summary.json` e `.../{p05,p12,p01}/{0,25,50}/metrics.json`.

## Dumps

Raiz: `.cursor/facial-warp-v2/cheekbones/B/`

Por run, em `{p05,p12,p01}/{0,25,50}/`:

| Ficheiro | Conteúdo |
|---|---|
| `original.png` | foto fonte |
| `v2Raw.png` | saída do renderer (sem fill) |
| `coverage.png` | cobertura bilinear |
| `invalidSource.png` | origem inválida (vazia nesta matriz) |
| `displacementField.png` | dx→R, dy→G, centro 128, escala 12 |
| `influenceMap.png` | \|d\| normalizado — só maçãs |
| `cheekActive.png` | domínio activo |
| `protectedMask.png` | hard-zero Cheekbones |
| `ownershipMap.png` | R=protegido, G=cheekActive, B=invalidSource |
| `metrics.json` | métricas + hash `v2Raw` |

### v2Raw (revisão visual = Sprint C)

Smear / ghost no `v2Raw` é esperado. Não se preenche.

- `.cursor/facial-warp-v2/cheekbones/B/p05/{0,25,50}/v2Raw.png` — primeira foto
- `.cursor/facial-warp-v2/cheekbones/B/p12/{0,25,50}/v2Raw.png`
- `.cursor/facial-warp-v2/cheekbones/B/p01/{0,25,50}/v2Raw.png`

Leitura de lab (não substitui C): a t=0.5 as maçãs entram; a linha 58–288 e o mento 152 não recebem campo; nariz/boca/orelhas sem dobra no mapa nem em `minDetJ`.

## Isolamento

- Lab em `test/`. Em `lib/` só a constante `amplitudeFaceWidth` do módulo Cheekbones (0.04 → 0.08).
- Renderer, `JawField` e módulo `chin/` **não** foram alterados.
- Zero fill no grafo.

## Arquivos

**Criados**

- `test/beauty_engine/warp/v2/facial_warp_v2_cheekbones_lab_test.dart`
- `docs/beauty/v2-cheekbones-b-report.md` (este relatório)
- `.cursor/facial-warp-v2/cheekbones/B/` — 9 pastas + `summary.json`

**Modificados em `lib/`**

- `warp/v2/cheekbones/cheekbones_field.dart` — só `amplitudeFaceWidth` 0.04 → 0.08. Sem mudança de arquitectura.

**Não alterados**

`BackwardBilinearWarp`, `DisplacementField`, `JawField`, módulo `chin/`, `RegionMasks`, `FieldMetrics`, `region_catalog.dart`, controller, preview, export, UI, Device Lab, regras V2.

## Sprint C

**Não iniciada.** Falta o sign-off visual humano das 9 imagens `v2Raw`. Sem essa aprovação, preview (D) não existe.
