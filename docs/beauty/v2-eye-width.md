# Eye Width — largura do olho

Efeito novo. **Não** é a Largura da sobrancelha (`eyebrow_width`). **Não** é Tamanho (`eye_size`). **Não** é Altura (`eye_height`). **Não** é Length, Distance nem Puffy eyes.

No Meitu, **Width** é o terceiro ícone do tab Olhos. O slider à direita alarga o olho na horizontal. À esquerda estreita. A abertura vertical fica. Geral / Esquerda / Direita = lados da foto.

Data: 2026-09-29.  
Estado: no editor para aprovação visual. Sem B escrita. Sem C assinada. Sem E. Tamanho, Altura e os Fields vivos **não se mexem**.

Módulo: `lib/features/editor/beauty_engine/warp/v2/eye_width/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

---

## 1. Papel

O olho fica mais largo ou mais estreito. A íris fica no sítio. A altura da pálpebra não muda. A sobrancelha, o nariz, a boca e a linha do cabelo ficam.

| Peça | Vigente |
|---|---|
| Key | `eye_width` (nunca `eyebrow_width` nem `eye_size`) |
| Label | **Largura** (tab Olhos) |
| Slider | Bipolar. Geral / L / R = lados da **foto** |
| Convenção | **Esquerda = estreita** (`t < 0`). **Direita = alarga** (`t > 0`) |
| Field | Só Δx. `dy = 0` |
| Ganho | `k = 0.28` (`s` de 0.72 a 1.28, só em x) |
| Params | `eye_width`, `eye_width_left`, `eye_width_right`, `eye_width_side` |

O Tamanho escala os dois eixos e muda a altura junto. Aqui só o eixo horizontal anda.

---

## 2. Equação

```
t ∈ [-1, 1] por lado da foto
identidade se |tPhotoLeft| e |tPhotoRight| ≤ 1e-6

s = 1 + 0.28 · t_lado
α = 1 − 1/s
dx = α · w · (x − c_x)
dy = 0
```

`c` é a íris daquele olho (468 e 473), calculada por lado. Não se mistura o centro com `leftFrac`.

Foto esquerda = íris **468**, canto **33**.  
Foto direita = íris **473**, canto **263**.

```
w = planalto(hull do olho) × BoundaryFeather × porta(sobrancelha) × porta(nariz)
```

Cada olho tem o seu hull. Onde os dois se encontram fica o centro mais próximo. Sem disco binário. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Tamanho, Altura nem os outros Fields.

O runtime cacheia `w · (x − c_x)`. O slider só entra em `α(t)`. `w` **não** depende de `t`.

---

## 3. Domínio

O mesmo hull do Tamanho, copiado. Não importado.

| Constante | Valor |
|---|---|
| Ganho | `0.28` |
| Hull pad | `0.025 × faceWidth` |
| Rampa de bordo | `0.07 × faceWidth` |
| Porta sobrancelha / nariz | `0.04 × faceWidth` |
| 33 / 263 | **andam** para fora se `t > 0`, para dentro se `t < 0` |
| 468 / 473 | **ficam** |
| `dy` | **0** em todo o campo |
| 105 / 334 | **ficam** |
| nariz / boca / 10 | ≈ 0 |

---

## 4. Pipeline e menu

```
head → hairline → eyebrow_height → eyebrow_width → eyebrow_end → eye_size → eye_height → eye_width → jaw → …
```

Tab Olhos, ícone Largura ao lado de Altura. Preview e export partilham `applyFaceWarpChain`.

---

## 5. O que não entra

- Alterar Tamanho, Altura nem os Fields vivos
- Key `eyebrow_width`
- Length, Distance, Puffy eyes
