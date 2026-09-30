# Nose Size — tamanho do nariz

Efeito novo. **Não** é `nose_slim`, `nose_length`, `nose_height`, `nose_tip` nem `nose_bridge`. **Não** é Head.

No Meitu, **Size** é o primeiro ícone do tab Nariz. O slider à direita encolhe o nariz inteiro. À esquerda aumenta, na mesma proporção largura/altura. Um slider só. Sem Geral / L / R.

Data: 2026-09-30.  
Estado: no editor para aprovação visual. Sem B escrita. Sem C assinada. Sem E. Os Fields vivos **não se mexem**.

Módulo: `lib/features/editor/beauty_engine/warp/v2/nose_size/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

---

## 1. Papel

O nariz cresce ou encolhe como um bloco, em volta do centro da ilha. Os olhos, a boca, as sobrancelhas e a linha do cabelo ficam.

| Peça | Vigente |
|---|---|
| Key | `nose_size` |
| Label | **Tamanho** (tab Nariz) |
| Slider | Bipolar. Um só, o nariz inteiro |
| Convenção | **Esquerda = aumenta** (`t < 0`). **Direita = encolhe** (`t > 0`) |
| Field | Escala local. `dx` e `dy` |
| Ganho | `k = 0.14` (`s` de 0.86 a 1.14) |
| Params | `nose_size` |

---

## 2. Equação

Igual à Cabeça, no nariz:

```
t ∈ [-1, 1]
identidade se |t| ≤ 1e-6

s = 1 − 0.14 · t
α = 1 − 1/s
D = α · w · (p − c)
```

`c` é o centróide dos landmarks do nariz. A escala é isotrópica: a razão largura/altura do próprio nariz fica.

```
w = planalto(hull do nariz) × BoundaryFeather × porta(olhos) × porta(boca) × porta(sobrancelha)
```

A porta é smoothstep da distância à máscara. Sem disco binário. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Olhos, Head nem os outros Fields.

O runtime cacheia `w · (p − c)`. O slider só entra em `α(t)`. `w` **não** depende de `t`.

---

## 3. Domínio

Hull de `V2RegionCatalog.nose`, dilatado `0.040 × faceWidth`. Olhos, boca e sobrancelha não são buraco no hull: o Field corta-os com a distância.

| Constante | Valor |
|---|---|
| Ganho | `0.14` |
| Hull pad | `0.040 × faceWidth` |
| Rampa de bordo | `0.055 × faceWidth` |
| Porta olhos / boca / sobrancelha | `0.045 × faceWidth` |
| 1 (ponta), 98 / 327 (asas) | **andam** para o centro se `t > 0`, para fora se `t < 0` |
| 468 / 473 / 13 / 105 / 10 | **ficam** |

---

## 4. Pipeline e menu

```
… → eye_distance → nose_size → nose_lift → nose_ala → nose_bridge → lip_size → jaw → …
```

Tab **Nariz**, ícone Tamanho. Preview e export partilham `applyFaceWarpChain`.
