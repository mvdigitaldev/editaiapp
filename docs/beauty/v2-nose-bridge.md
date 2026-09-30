# Nose Bridge — largura do dorso

Efeito novo. **Não** é `nose_size`. **Não** é `nose_slim`. **Não** é Lift, Ala, Root nem Tip.

No Meitu, **Bridge** é o quinto ícone do tab Nariz. O slider à direita afina o dorso (o terço do meio). À esquerda alarga. Um slider só. Sem Geral / L / R. A raiz (entre os olhos), as asas e a ponta ficam.

Data: 2026-09-30.  
Estado: no editor para aprovação visual. Sem B escrita. Sem C assinada. Sem E. Tamanho, Elevação, Largura e os Fields vivos **não se mexem**. Root e Tip ainda não existem.

Módulo: `lib/features/editor/beauty_engine/warp/v2/nose_bridge/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

---

## 1. Papel

Os lados do dorso aproximam-se ou afastam-se da linha do meio. A raiz, as asas, a ponta, os olhos, a boca e as sobrancelhas ficam.

| Peça | Vigente |
|---|---|
| Key | `nose_bridge` |
| Label | **Ponte** (tab Nariz) |
| Slider | Bipolar. Um só, o dorso inteiro |
| Convenção | **Esquerda = alarga** (`t < 0`). **Direita = afina** (`t > 0`) |
| Field | Só Δx |
| Ganho | `k = 0.28` (`s` de 0.72 a 1.28), só em x |
| Params | `nose_bridge` |

---

## 2. Equação

Escala horizontal em volta da midline, só no terço do meio:

```
t ∈ [-1, 1]
identidade se |t| ≤ 1e-6

s = 1 − 0.28 · t
α = 1 − 1/s
dx = α · w · perfil · midGate · (x − x_mid)
dy = 0
```

`x_mid` é a média do x de **168** e **1**. `midGate` é 0 na midline e 1 a partir de `0.022 × faceWidth`, para a crista não andar em x.

```
u = projecção de (p − nasion) em (ponta − nasion)
perfil = 0 se u ≤ 0.18 ou u ≥ 0.70
         1 se 0.32 ≤ u ≤ 0.50
         smoothstep nos vãos
```

```
w = planalto(hull do nariz) × BoundaryFeather × porta(olhos) × porta(boca) × porta(sobrancelha)
```

A porta é smoothstep da distância à máscara. Sem disco binário. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Tamanho, Elevação, Largura nem os outros Fields.

O runtime cacheia `w · perfil · midGate · (x − x_mid)`. O slider só entra em `α(t)`. `w` **não** depende de `t`.

---

## 3. Domínio

Hull de `V2RegionCatalog.nose`, dilatado `0.055 × faceWidth`. Olhos, boca e sobrancelha não são buraco no hull.

| Constante | Valor |
|---|---|
| Ganho | `0.28` |
| Hull pad | `0.055 × faceWidth` |
| Rampa de bordo | `0.070 × faceWidth` |
| Porta da midline | `0.022 × faceWidth` |
| Porta olhos / boca / sobrancelha | `0.045 × faceWidth` |
| Perfil | banda `0.18–0.70`, cheia em `0.32–0.50` |
| 196 / 419 | **andam** em x |
| 98 / 327 / 1 / 168 | **ficam** em x |
| 468 / 473 / 13 / 105 / 10 | **ficam** |

---

## 4. Pipeline e menu

```
… → nose_ala → nose_bridge → jaw → …
```

Tab **Nariz**, ícone Ponte à direita de Largura. Preview e export partilham `applyFaceWarpChain`.
