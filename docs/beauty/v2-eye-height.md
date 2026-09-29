# Eye Height — altura do olho

Efeito novo. **Não** é a Altura da sobrancelha (`eyebrow_height`). **Não** é Tamanho (`eye_size`). **Não** é Width, Length, Distance nem Puffy eyes.

No Meitu, **Height** é o segundo ícone do tab Olhos. O slider à direita sobe o olho. À esquerda desce. Geral / Esquerda / Direita = lados da foto.

Data: 2026-09-29.  
Estado: no editor para aprovação visual. Sem B escrita. Sem C assinada. Sem E. Tamanho e os Fields vivos **não se mexem**.

Módulo: `lib/features/editor/beauty_engine/warp/v2/eye_height/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

---

## 1. Papel

O olho inteiro sobe ou desce. A íris vai junto. A sobrancelha, o nariz, a boca e a linha do cabelo ficam.

| Peça | Vigente |
|---|---|
| Key | `eye_height` (nunca `eyebrow_height` nem `eye_size`) |
| Label | **Altura** (tab Olhos) |
| Slider | Bipolar. Geral / L / R = lados da **foto** |
| Convenção | **Esquerda = desce** (`t < 0`). **Direita = sobe** (`t > 0`) |
| Field | Só Δy. `dx = 0` |
| Amplitude | `0.030 × faceWidth` |
| Params | `eye_height`, `eye_height_left`, `eye_height_right`, `eye_height_side` |

O Tamanho escala em volta da íris e a íris fica. Aqui a íris anda. Copiar o Tamanho só mudava o tamanho outra vez.

---

## 2. Equação

```
t ∈ [-1, 1] por lado da foto
identidade se |tPhotoLeft| e |tPhotoRight| ≤ 1e-6

dx = 0
dy = −t_lado · 0.030 · faceWidth · w
```

`dy < 0` sobe, porque o y da imagem cresce para baixo.

Foto esquerda = íris **468**.  
Foto direita = íris **473**.

```
w = planalto(hull do olho) × BoundaryFeather × porta(sobrancelha) × porta(nariz)
```

Cada olho tem o seu hull. Onde os dois se encontram fica o de maior peso, para o meio não somar dois planaltos. Sem disco binário. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Tamanho nem os outros Fields.

O runtime cacheia `w` de cada olho. O slider só escala `dy`. `w` **não** depende de `t`.

---

## 3. Domínio

O mesmo hull do Tamanho, copiado. Não importado.

| Constante | Valor |
|---|---|
| Amplitude | `0.030 × faceWidth` |
| Hull pad | `0.025 × faceWidth` |
| Rampa de bordo | `0.07 × faceWidth` |
| Porta sobrancelha / nariz | `0.04 × faceWidth` |
| 468 / 473 | **andam** em Δy |
| 105 / 334 | **ficam** |
| nariz / boca / 10 | ≈ 0 |

---

## 4. Pipeline e menu

```
head → hairline → eyebrow_height → eyebrow_width → eyebrow_end → eye_size → eye_height → jaw → …
```

Tab Olhos, ícone Altura ao lado de Tamanho. Preview e export partilham `applyFaceWarpChain`.

---

## 5. O que não entra

- Alterar Tamanho nem os Fields vivos
- Key `eyebrow_height`
- Width, Length, Distance, Puffy eyes
