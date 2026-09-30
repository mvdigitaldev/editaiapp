# Eye Length — comprimento do olho

Efeito novo. **Não** é a Largura (`eye_width`). **Não** é Tamanho (`eye_size`). **Não** é Altura (`eye_height`). **Não** é Distance nem Puffy eyes.

No Meitu, **Length** é o quarto ícone do tab Olhos. O slider à direita alonga o olho pelo canto de fora. À esquerda encurta. A íris e o canto de dentro ficam. Geral / Esquerda / Direita = lados da foto.

Data: 2026-09-29.  
Estado: no editor para aprovação visual. Sem B escrita. Sem C assinada. Sem E. Tamanho, Altura, Largura e os Fields vivos **não se mexem**.

Módulo: `lib/features/editor/beauty_engine/warp/v2/eye_length/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

---

## 1. Papel

O olho fica mais comprido ou mais curto. Quem anda é o canto externo. A íris fica. O canto interno fica. A altura da pálpebra não muda.

| Peça | Vigente |
|---|---|
| Key | `eye_length` (nunca `eye_width`) |
| Label | **Comprimento** (tab Olhos) |
| Slider | Bipolar. Geral / L / R = lados da **foto** |
| Convenção | **Esquerda = encurta** (`t < 0`). **Direita = alonga** (`t > 0`) |
| Field | Só Δx. `dy = 0` |
| Amplitude | `0.028 × faceWidth` no canto externo |
| Params | `eye_length`, `eye_length_left`, `eye_length_right`, `eye_length_side` |

A Largura escala os dois lados da íris. Aqui o lado de dentro da íris fica parado, e o canto de fora é que sai ou entra.

---

## 2. Equação

```
t ∈ [-1, 1] por lado da foto
identidade se |tPhotoLeft| e |tPhotoRight| ≤ 1e-6

dx = t_lado · 0.028 · faceWidth · w · perfil · side
dy = 0
```

`side` aponta da íris para o canto externo (−1 na foto esquerda, +1 na direita).

`perfil` é 0 da íris para o canto interno. Sobe em smoothstep até 1 no canto externo e fica em 1 para lá dele, até a rampa do hull o apagar.

Foto esquerda = íris **468**, externo **33**, interno **133**.  
Foto direita = íris **473**, externo **263**, interno **362**.

```
w = planalto(hull do olho) × BoundaryFeather × porta(sobrancelha) × porta(nariz)
```

Cada olho tem o seu hull. Onde os dois se encontram fica o centro mais próximo. Sem disco binário. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Tamanho, Altura, Largura nem os outros Fields.

O runtime cacheia `w · perfil · side`. O slider só escala `dx`. O perfil **não** depende de `t`.

---

## 3. Domínio

O mesmo hull do Tamanho, copiado. Não importado.

| Constante | Valor |
|---|---|
| Amplitude | `0.028 × faceWidth` |
| Hull pad | `0.025 × faceWidth` |
| Rampa de bordo | `0.07 × faceWidth` |
| Porta sobrancelha / nariz | `0.04 × faceWidth` |
| 33 / 263 | **andam** para fora se `t > 0`, para dentro se `t < 0` |
| 133 / 362 | **ficam** |
| 468 / 473 | **ficam** |
| `dy` | **0** em todo o campo |
| 105 / 334 | **ficam** |
| nariz / boca / 10 | ≈ 0 |

---

## 4. Pipeline e menu

```
head → hairline → eyebrow_height → eyebrow_width → eyebrow_end → eye_size → eye_height → eye_width → eye_length → jaw → …
```

Tab Olhos, ícone Comprimento ao lado de Largura. Preview e export partilham `applyFaceWarpChain`.

---

## 5. O que não entra

- Alterar Tamanho, Altura, Largura nem os Fields vivos
- Key `eye_width`
- Distance, Puffy eyes
