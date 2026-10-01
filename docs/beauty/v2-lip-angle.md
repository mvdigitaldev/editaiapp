# Lip Angle — ângulo dos lábios

Efeito novo. **Não** é `lip_size`, `lip_width` nem `lip_height`. **Não** é Rotate nem M-shaped.

No Meitu, **Angle** é o quarto ícone do tab Lábios. O slider à direita inclina a boca na diagonal: o canto da foto à esquerda desce e o da direita sobe. À esquerda, o contrário. Um slider só. Sem Geral / L / R.

Data: 2026-09-30.  
Estado: no editor para aprovação visual. Sem B escrita. Sem C assinada. Sem E. Tamanho, Largura, Altura e os Fields vivos **não se mexem**. Rotate / M-shaped ainda não existem.

Módulo: `lib/features/editor/beauty_engine/warp/v2/lip_angle/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

---

## 1. Papel

A boca inclina em volta do centróide. Cada canto anda na diagonal (Δx e Δy). O nariz, o queixo e os olhos ficam.

| Peça | Vigente |
|---|---|
| Key | `lip_angle` |
| Label | **Ângulo** (tab Lábios) |
| Slider | Bipolar. Um só, a boca inteira |
| Convenção | **Esquerda = `\`** (`t < 0`, canto esquerdo sobe). **Direita = `/`** (`t > 0`, canto esquerdo desce) |
| Field | Δx e Δy |
| Ganho | `θ = 0.12 · t` radianos (~7°) |
| Params | `lip_angle` |

---

## 2. Equação

Rotação infinitesimal em volta do centróide dos lábios, com o sinal do Meitu:

```
t ∈ [-1, 1]
identidade se |t| ≤ 1e-6

θ = 0.12 · t
dx = θ · w · (y − c.y)
dy = −θ · w · (x − c.x)
```

```
w = planalto(hull dos lábios) × BoundaryFeather × porta(nariz) × porta(queixo) × porta(olhos) × porta(sobrancelha)
```

Sem disco binário. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Tamanho, Largura, Altura nem os outros Fields.

O runtime cacheia `w · (y − c.y)` e `w · −(x − c.x)`. O slider só entra em `θ(t)`.

---

## 3. Domínio

Hull de `V2RegionCatalog.lips`, dilatado `0.040 × faceWidth`.

| Constante | Valor |
|---|---|
| Ganho | `0.12` rad |
| Hull pad | `0.040 × faceWidth` |
| Rampa de bordo | `0.055 × faceWidth` |
| Porta nariz / queixo / olhos / sobrancelha | `0.045 × faceWidth` |
| 61 / 291 | **andam** na diagonal |
| 0 no centróide | **fica** |
| 1 / 152 / 468 / 473 / 105 / 10 | **ficam** |

---

## 4. Pipeline e menu

```
… → lip_height → lip_angle → jaw → …
```

Tab **Lábios**, ícone Ângulo à direita de Altura.
