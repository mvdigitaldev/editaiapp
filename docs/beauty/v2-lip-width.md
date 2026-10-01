# Lip Width — largura dos lábios

Efeito novo. **Não** é `lip_size`. **Não** é Height, Angle, Rotate nem M-shaped.

No Meitu, **Width** é o segundo ícone do tab Lábios. O slider à direita afina a boca. À esquerda alarga. Praticamente o Tamanho, só em x. Um slider só. Sem Geral / L / R.

Data: 2026-09-30.  
Estado: no editor para aprovação visual. Sem B escrita. Sem C assinada. Sem E. Tamanho e os Fields vivos **não se mexem**. Angle / Rotate / M-shaped ainda não existem.

Módulo: `lib/features/editor/beauty_engine/warp/v2/lip_width/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

---

## 1. Papel

Os cantos aproximam-se ou afastam-se. A altura da boca, o nariz, o queixo e os olhos ficam.

| Peça | Vigente |
|---|---|
| Key | `lip_width` |
| Label | **Largura** (tab Lábios) |
| Slider | Bipolar. Um só, a boca inteira |
| Convenção | **Esquerda = alarga** (`t < 0`). **Direita = afina** (`t > 0`) |
| Field | Só Δx |
| Ganho | `k = 0.12` (`s` de 0.88 a 1.12), só em x |
| Params | `lip_width` |

---

## 2. Equação

Igual ao Tamanho, só em x:

```
t ∈ [-1, 1]
identidade se |t| ≤ 1e-6

s = 1 − 0.12 · t
α = 1 − 1/s
dx = α · w · (x − c.x)
dy = 0
```

`c` é o centróide dos landmarks dos lábios.

```
w = planalto(hull dos lábios) × BoundaryFeather × porta(nariz) × porta(queixo) × porta(olhos) × porta(sobrancelha)
```

Sem disco binário. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Tamanho nem os outros Fields.

O runtime cacheia `w · (x − c.x)`. O slider só entra em `α(t)`.

---

## 3. Domínio

Hull de `V2RegionCatalog.lips`, dilatado `0.030 × faceWidth`.

| Constante | Valor |
|---|---|
| Ganho | `0.12` |
| Hull pad | `0.030 × faceWidth` |
| Rampa de bordo | `0.042 × faceWidth` |
| Porta nariz / queixo / olhos / sobrancelha | `0.045 × faceWidth` |
| 61 / 291 | **andam** em x |
| 0 em y | **fica** |
| 1 / 152 / 468 / 473 / 105 / 10 | **ficam** |

---

## 4. Pipeline e menu

```
… → lip_size → lip_width → lip_height → lip_angle → jaw → …
```

Tab **Lábios**, ícone Largura à direita de Tamanho.
