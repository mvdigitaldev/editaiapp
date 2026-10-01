# Body lab — catálogo de fotos de corpo

Laboratório novo. **Não** é o lab facial (`.cursor/facial-warp-v2/`). **Não** altera Jaw, lábios, nariz nem os outros Fields do rosto.

Data: 2026-10-01.  
Estado: catálogo semeado. Menu de produto **zerado** (2026-10-01): sem sliders, sem filtros MLS, sem estratégias regionais. O compose de corpo é identidade. O editor **Ajustar corpo** (`bodyOnly`) carrega `body-p01`…`body-p04` e mostra «Sem ferramentas ainda.». O lab facial (`p01` / `p05` / `p12` / `p15`) fica no retoque de rosto. Sem pose JSON ainda. Sem Field de corpo novo.

Fotos: `test/beauty_engine/warp/fixtures/body/real/`.  
Loader: `test/beauty_engine/filters/body/mvp_benchmark_bodies.dart`.  
Dumps: `.cursor/body-reshape-v2/catalog/{p01,p02,p03,p04}/original.png`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

---

## 1. Papel

Quatro fotos reais para medir cintura, quadril, peito, pernas e braços. Os labs do rosto (`real-p01` / `p05` / `p12`) ficam. Não se misturam.

| ID | Dump | Foto | Enquadramento |
|---|---|---|---|
| `body-p01` | `p01` | mulher, set cinza, deserto, braços no ar | corpo inteiro |
| `body-p02` | `p02` | mulher, top roxo, saia, mãos na cintura | até à coxa |
| `body-p03` | `p03` | homem, t-shirt preta, terraço, mãos juntas | até à coxa |
| `body-p04` | `p04` | mulher, set azul, janela, um braço no ar | até ao joelho |

---

## 2. O que ainda não existe

- JSON de pose MediaPipe (33 pontos). O loader aceita `poseJson` no manifesto quando houver.
- Field V2 de corpo. Os sliders antigos (`waist_slim`, `hip`, `body_slim`, `leg_length`, `leg_slim`, `arm_slim`, `neck_slim`, `shoulder_width` e os V2 mesh) foram **apagados**.
- Relatório B/C/E. Isto é só o catálogo + a casca vazia do menu.

---

## 3. Como regenerar os dumps

```
flutter test test/beauty_engine/body_reshape/body_reshape_catalog_lab_test.dart
```

O teste grava `original.png`, `meta.json` e `summary.json` em `.cursor/body-reshape-v2/catalog/`. Essa pasta está no `.gitignore` (como o lab facial).
