# Lip Size — tamanho dos lábios

Efeito novo. **Não** é `lip_thickness`. **Não** é Width, Height, Angle, Rotate nem M-shaped.

No Meitu, **Size** é o primeiro ícone do tab Lábios. O slider à direita encolhe os lábios. À esquerda aumenta, na mesma proporção largura/altura. Um detalhe suave. Um slider só. Sem Geral / L / R.

Data: 2026-09-30.  
Estado: no editor para aprovação visual. Sem B escrita. Sem C assinada. Sem E. Nariz e os Fields vivos **não se mexem**. Width / Height / Angle / Rotate / M-shaped ainda não existem.

Módulo: `lib/features/editor/beauty_engine/warp/v2/lip_size/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

---

## 1. Papel

Os lábios crescem ou encolhem como um bloco, em volta do centro da ilha. O nariz, o queixo, os olhos e as sobrancelhas ficam.

| Peça | Vigente |
|---|---|
| Key | `lip_size` |
| Label | **Tamanho** (tab Lábios) |
| Slider | Bipolar. Um só, a boca inteira |
| Convenção | **Esquerda = aumenta** (`t < 0`). **Direita = encolhe** (`t > 0`) |
| Field | Escala local. `dx` e `dy` |
| Ganho | `k = 0.12` (`s` de 0.88 a 1.12) |
| Params | `lip_size` |

---

## 2. Equação

Igual à Cabeça e ao Tamanho do nariz, nos lábios:

```
t ∈ [-1, 1]
identidade se |t| ≤ 1e-6

s = 1 − 0.12 · t
α = 1 − 1/s
D = α · w · (p − c)
```

`c` é o centróide dos landmarks dos lábios. A escala é isotrópica: a razão largura/altura da própria boca fica.

```
w = planalto(hull dos lábios) × BoundaryFeather × porta(nariz) × porta(queixo) × porta(olhos) × porta(sobrancelha)
```

A porta é smoothstep da distância à máscara. Sem disco binário. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Nariz, Head nem os outros Fields.

O runtime cacheia `w · (p − c)`. O slider só entra em `α(t)`. `w` **não** depende de `t`.

---

## 3. Domínio

Hull de `V2RegionCatalog.lips`, dilatado `0.030 × faceWidth`. Nariz, queixo, olhos e sobrancelha não são buraco no hull: o Field corta-os com a distância.

| Constante | Valor |
|---|---|
| Ganho | `0.12` |
| Hull pad | `0.030 × faceWidth` |
| Rampa de bordo | `0.042 × faceWidth` |
| Porta nariz / queixo / olhos / sobrancelha | `0.045 × faceWidth` |
| 0 / 17 / 61 / 291 | **andam** para o centro se `t > 0`, para fora se `t < 0` |
| 1 / 152 / 468 / 473 / 105 / 10 | **ficam** |

---

## 4. Pipeline e menu

```
… → nose_bridge → lip_size → lip_width → lip_height → lip_angle → lip_plump → jaw → …
```

Tab **Lábios**, ícone Tamanho. Preview e export partilham `applyFaceWarpChain`.
