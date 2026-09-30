# Nose Ala — largura das asas

Efeito novo. **Não** é `nose_size`. **Não** é `nose_slim`. **Não** é Lift, Root, Bridge nem Tip.

No Meitu, **Ala** é o terceiro ícone do tab Nariz. O slider à direita afina as asas. À esquerda alarga. Tem Geral / esquerda / direita. L/R da foto: o lado seleccionado é o único que anda.

Data: 2026-09-30.  
Estado: no editor para aprovação visual. Sem B escrita. Sem C assinada. Sem E. Tamanho, Elevação e os Fields vivos **não se mexem**. **Intacto** na Ponte. Root e Tip ainda não existem.

Módulo: `lib/features/editor/beauty_engine/warp/v2/nose_ala/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

---

## 1. Papel

As asas aproximam-se ou afastam-se da linha do meio. A raiz, a ponta (em x), os olhos, a boca e as sobrancelhas ficam.

| Peça | Vigente |
|---|---|
| Key | `nose_ala` |
| Label | **Largura** (tab Nariz) |
| Slider | Bipolar. Geral / esquerda / direita |
| Convenção | **Esquerda = alarga** (`t < 0`). **Direita = afina** (`t > 0`) |
| Field | Só Δx |
| Ganho | `k = 0.24` (`s` de 0.76 a 1.24), só em x |
| Params | `nose_ala`, `nose_ala_left`, `nose_ala_right` |

---

## 2. Equação

Escala horizontal em volta da midline do nariz, com perfil 0 na raiz:

```
t ∈ [-1, 1]
identidade se |t_lado| ≤ 1e-6

s = 1 − 0.24 · t
α = 1 − 1/s
dx = α · w · perfil · midGate · (x − x_mid)
dy = 0
```

`x_mid` é a média do x de **168** e **1**. `midGate` é 0 na midline e 1 a partir de `0.028 × faceWidth`, para a ponta e a columela não andarem em x. Foto esquerda = `x < x_mid` (asa **98**). Foto direita = `x > x_mid` (asa **327**).

```
u = projecção de (p − nasion) em (ponta − nasion)
perfil = 0 se u ≤ 0.12
         1 se u ≥ 0.42
         smoothstep no vão
```

```
w = planalto(hull do nariz) × BoundaryFeather × porta(olhos) × porta(boca) × porta(sobrancelha)
```

A porta é smoothstep da distância à máscara. Sem disco binário. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Tamanho, Elevação, Olhos nem os outros Fields.

O runtime cacheia `w · perfil · midGate · (x − x_mid)` por lado. O slider só entra em `α(t_lado)`. `w` **não** depende de `t`.

---

## 3. Domínio

Hull de `V2RegionCatalog.nose`, dilatado `0.050 × faceWidth`. Olhos, boca e sobrancelha não são buraco no hull.

| Constante | Valor |
|---|---|
| Ganho | `0.24` |
| Hull pad | `0.050 × faceWidth` |
| Rampa de bordo | `0.065 × faceWidth` |
| Porta da midline | `0.028 × faceWidth` |
| Porta olhos / boca / sobrancelha | `0.045 × faceWidth` |
| Perfil | 0 até `u = 0.12`, 1 a partir de `u = 0.42` |
| 98 / 327 | **andam** em x |
| 1 / 168 | **ficam** em x |
| 468 / 473 / 13 / 105 / 10 | **ficam** |

---

## 4. Pipeline e menu

```
… → nose_lift → nose_ala → nose_bridge → lip_size → jaw → …
```

Tab **Nariz**, ícone Largura à direita de Elevação. Preview e export partilham `applyFaceWarpChain`.
