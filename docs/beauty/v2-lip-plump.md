# Lip Plump — volume dos lábios

Efeito novo. **Não** é `lip_size`, `lip_width`, `lip_height` nem `lip_angle`. **Não** é `lip_thickness`. **Não** é Rotate, M-shaped, Smile nem Whiten.

No Meitu, **Plump** é o ícone com o beiço tracejado. O slider à direita engrossa o beiço. À esquerda afina. Menu **Geral / Apenas superior / Apenas inferior**.

Data: 2026-09-30.  
Estado: no editor para aprovação visual. Sem B escrita. Sem C assinada. Sem E. Tamanho, Largura, Altura, Ângulo e os Fields vivos **não se mexem**. Rotate / M-shaped / Smile / Whiten ainda não existem.

Módulo: `lib/features/editor/beauty_engine/warp/v2/lip_plump/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

---

## 1. Papel

O beiço abre a partir da fenda. O de cima sobe, o de baixo desce. Os cantos, o nariz e o queixo ficam.

| Peça | Vigente |
|---|---|
| Key | `lip_plump` |
| Label | **Volume** (tab Lábios) |
| Slider | Bipolar. Geral / Apenas superior / Apenas inferior |
| Convenção | **Esquerda = afina** (`t < 0`). **Direita = engrossa** (`t > 0`) |
| Field | Só Δy |
| Ganho | `k = 0.22` (`s` de 0,78 a 1,22) |
| Params | `lip_plump`, `lip_plump_upper`, `lip_plump_lower`, `lip_plump_side` |

---

## 2. Equação

```
tUpper, tLower ∈ [-1, 1]
identidade se |tUpper| ≤ 1e-6 e |tLower| ≤ 1e-6

s = 1 + 0.22 · t
α = 1 − 1/s
dy = αUpper · wUpper · (y − y_fenda) + αLower · wLower · (y − y_fenda)
dx = 0
```

O eixo da fenda é a média em y de 13 e 14. `wUpper` vive acima; `wLower` abaixo. Porta na fenda, cauda nos cantos ao longo de 61→291.

```
w = planalto(hull dos lábios) × BoundaryFeather × porta(nariz) × porta(queixo) × porta(olhos) × porta(sobrancelha)
```

Sem disco binário. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Tamanho, Largura, Altura, Ângulo nem os outros Fields.

O runtime cacheia `wUpper` e `wLower`. O slider só escala `dy`.

---

## 3. Domínio

Hull de `V2RegionCatalog.lips`, dilatado `0.040 × faceWidth`.

| Constante | Valor |
|---|---|
| Ganho | `0.22` |
| Hull pad | `0.040 × faceWidth` |
| Rampa de bordo | `0.055 × faceWidth` |
| 0 | **anda** em y se superior activo |
| 17 | **anda** em y se inferior activo |
| 61 / 291 | **ficam** |
| 1 / 152 / 468 / 473 / 105 / 10 | **ficam** |

---

## 4. Pipeline e menu

```
… → lip_angle → lip_plump → lip_smile → jaw → …
```

Tab **Lábios**, ícone Volume à direita de Ângulo.
