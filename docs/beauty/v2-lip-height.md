# Lip Height — altura dos lábios

Efeito novo. **Não** é `lip_size` nem `lip_width`. **Não** é Angle, Rotate nem M-shaped.

No Meitu, **Height** é o terceiro ícone do tab Lábios. O slider à direita sobe a boca. À esquerda desce. Um slider só. Sem Geral / L / R.

Data: 2026-09-30.  
Estado: no editor para aprovação visual. Sem B escrita. Sem C assinada. Sem E. Tamanho, Largura e os Fields vivos **não se mexem**. Angle / Rotate / M-shaped ainda não existem.

Módulo: `lib/features/editor/beauty_engine/warp/v2/lip_height/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

---

## 1. Papel

A boca sobe ou desce como um bloco. O nariz, o queixo e os olhos ficam.

| Peça | Vigente |
|---|---|
| Key | `lip_height` |
| Label | **Altura** (tab Lábios) |
| Slider | Bipolar. Um só, a boca inteira |
| Convenção | **Esquerda = desce** (`t < 0`). **Direita = sobe** (`t > 0`) |
| Field | Só Δy |
| Ganho | `0.024 × faceWidth` |
| Params | `lip_height` |

---

## 2. Equação

```
t ∈ [-1, 1]
identidade se |t| ≤ 1e-6

dy = −t · 0.024 · faceWidth · w
dx = 0
```

```
w = planalto(hull dos lábios) × BoundaryFeather × porta(nariz) × porta(queixo) × porta(olhos) × porta(sobrancelha)
```

Sem disco binário. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Tamanho, Largura nem os outros Fields.

O runtime cacheia `w`. O slider só entra em `−t · amplitude`.

---

## 3. Domínio

Hull de `V2RegionCatalog.lips`, dilatado `0.040 × faceWidth`.

| Constante | Valor |
|---|---|
| Amplitude | `0.024 × faceWidth` |
| Hull pad | `0.040 × faceWidth` |
| Rampa de bordo | `0.055 × faceWidth` |
| Porta nariz / queixo / olhos / sobrancelha | `0.045 × faceWidth` |
| 0 / 17 / 61 / 291 | **andam** em y |
| 1 / 152 / 468 / 473 / 105 / 10 | **ficam** |

---

## 4. Pipeline e menu

```
… → lip_width → lip_height → lip_angle → lip_plump → jaw → …
```

Tab **Lábios**, ícone Altura à direita de Largura.
