# Cheekbones — hipótese H (calibração no editor)

**Estado:** vigente no código. Inspecção visual no editor. **Não** é Sprint C. **Não** é D/E aprovada.

Data: 2026-08-26.  
Leonardo confirmou o contorno (fim do “S” no oval). Jaw e Chin **não** foram editados neste trabalho.

Módulo: `lib/features/editor/beauty_engine/warp/v2/cheekbones/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

---

## 1. O que H é

O mesmo contrato V2 de sempre:

```
CheekbonesField.build(face, size, t / tPhotoLeft / tPhotoRight)
  → DisplacementField
  → BackwardBilinearWarp
```

Um Field, só Δx para a midline, `dy = 0`. Sem MLS. Sem Face Rig. Sem receita. Sem alterar Jaw, Chin, renderer.

H **não** é A1 (carimbo em 123/411) nem A2 (arco órbita→interior).  
H é uma **crista no oval** da maçã até ao gônio, com peso a descer de forma monótona.

---

## 2. Produto no editor

| Peça | Vigente |
|---|---|
| Key | `cheekbone` (“Maçãs do rosto”) |
| Slider | Bipolar Meitu: centro = 0 (identidade), sem %. Esquerda do centro aumenta maçãs; direita reduz |
| Lados | Flag **Geral / Esquerda / Direita** = lados da **foto**. Valores independentes. Geral escreve os dois |
| Params | `cheekbone`, `cheekbone_left`, `cheekbone_right`, `cheekbone_side` (0/1/2) |
| Field | `tPhotoLeft` / `tPhotoRight`. Foto esquerda = malar MediaPipe direito; foto direita = malar MediaPipe esquerdo |
| Pipeline | `applyJawWarp` → `applyChinWarp` → `applyCheekbonesWarp` (inspecção; C não assinada) |

Isto não é slider composto: é o mesmo Field, amplitudes por lado.

---

## 3. Crista (calibração vigente)

Polilinha no **oval**, não no interior 116→147.

| Lado da cara (MediaPipe) | IDs (cima → baixo) |
|---|---|
| Esquerdo (direita da foto) | 234 → 93 → 132 → 58 |
| Direito (esquerda da foto) | 454 → 323 → 361 → 288 |

Pesos na crista (com pontos médios entre âncoras): **0.80 → 0.75 → 0.70 → 0.59 → 0.48 → 0.35 → 0.22**.

```
weight(x, y) = w_crista(s) · exp(−d² / (2 σ⊥²))
dx = sign(midlineX − x) · amplitude_lado · weight
dy = 0
```

`d` = distância à polilinha. `w_crista` interpola ao longo do segmento.  
**Não** é `max` de gaussianas centradas em handles: isso abria vales no contorno (leitura de “S”).

| Constante | Valor |
|---|---|
| `t` | `[-1, 1]` por lado |
| Amplitude | `0.022 × faceWidth` |
| σ transversal | `0.09 × faceWidth` |
| Rampa nariz/boca/chin | `0.12 × faceWidth` |
| Rampa orelha | `0.035 × faceWidth` na **pina** (disco deslocado `0.05 × faceWidth` para fora do oval) |
| Primários de métrica | 123 / **352** (espelho de 123). **Não** 411 (espelho de 187, bolbo baixo) |
| Chin / olhos / nariz / boca | hard-zero |
| Gônio | **não** hard-zero (cauda 0.22). Não substitui o slider Jaw |

---

## 4. O que falhou e ficou oficialmente rejeitado nesta calibração

Não reabrir estas geometrias como se fossem H:

| Tentativa | Sintoma no editor | Causa |
|---|---|---|
| Pico / pad em 123–411, amplitude `0.04` | Buraco na eminência | Amplitude de Jaw num suporte mais pequeno; 411 ≠ espelho de 123 |
| `max(gaussianas)` na parede 116→147 | Contorno em S | Vale entre maçã e gônio; eixo para dentro, não no oval |
| Hard-zero Jaw em 58/288/132/361 | Trava a meio da bochecha | Meitu puxa um pedaço do ângulo mandibular neste slider |
| Disco de orelha centrado em **323 / 454** | S com pico no tragus | Esses IDs **estão no oval**. A junta orelha–bochecha ficava parada; maçã e maxilar mexiam |
| Primário direito 411 | Lado direito da foto mais fraco / “travado” | 411 é o espelho de 187 (bolbo), colado à orelha em p01 |

A1/A2 (relatórios próprios) continuam arquivo de Sprint A. Não são o Field no disco.

---

## 5. Isolamento

- **JawField / ChinField:** intocados.
- **Renderer / `DisplacementField` / `WarpRequest` / `WarpResult`:** intocados.
- **Mento (152 e domínio Chin):** continua a zero neste Field.
- **Orelha:** só a pina, fora da silhueta. O oval em 323/454 **move** com a crista.

Sobreposição espacial com Jaw no gônio: aceite como no Meitu (cauda leve). Dois sliders, dois Fields, soma na pipeline. Não é receita.

---

## 6. Testes

- `test/beauty_engine/warp/v2/facial_warp_v2_cheekbones_field_test.dart` — t=0; t=0.5; t=±; `minDetJ > 0`; cauda mandibular &lt; pico; L/R da foto isolados.
- Lab B (`facial_warp_v2_cheekbones_lab_test.dart`) existe no disco; dumps em `.cursor/facial-warp-v2/cheekbones/H/`. Não substitui C.

---

## 7. O que H **não** fecha

- Sprint **C** (aprovação escrita das três fotos lab).
- Sprint **D/E** como promoção formal (o preview já está na cadeia por inspecção).
- Chin Length vs Meitu (sangria residual no maxilar). Fora deste relatório. Chin permanece encerrado até aprovação explícita para reabrir.
- Temple, Hairline, L/R noutros sliders.

---

## Fontes

Código: `cheekbones_field.dart`, `cheekbones_masks.dart`.  
Spec de região original (emendada): [`v2-cheekbones-spec.md`](./v2-cheekbones-spec.md).  
Pesquisa Meitu (encerrada): [`v2-cheekbones-product-analysis.md`](./v2-cheekbones-product-analysis.md).
