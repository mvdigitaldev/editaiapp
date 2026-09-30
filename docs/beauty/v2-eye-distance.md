# Eye Distance — distância dos olhos

Efeito novo. **Não** é Comprimento (`eye_length`). **Não** é Largura (`eye_width`). **Não** é Tamanho (`eye_size`). **Não** é Puffy eyes.

No Meitu, **Distance** é o quinto ícone do tab Olhos. O slider à direita afasta os olhos. À esquerda aproxima. O olho inteiro anda, íris incluída. Geral / Esquerda / Direita = lados da foto.

Data: 2026-09-29.  
Estado: no editor para aprovação visual. Sem B escrita. Sem C assinada. Sem E. Tamanho, Altura, Largura, Comprimento e os Fields vivos **não se mexem**.

Módulo: `lib/features/editor/beauty_engine/warp/v2/eye_distance/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

---

## 1. Papel

Os olhos afastam-se ou aproximam-se da linha do meio. A íris vai junto. O canto externo vai junto. A sobrancelha, o nariz, a boca e a linha do cabelo ficam.

| Peça | Vigente |
|---|---|
| Key | `eye_distance` |
| Label | **Distância** (tab Olhos) |
| Slider | Bipolar. Geral / L / R = lados da **foto** |
| Convenção | **Esquerda = aproxima** (`t < 0`). **Direita = afasta** (`t > 0`) |
| Field | Só Δx. `dy = 0`. Translação do olho |
| Amplitude | `0.030 × faceWidth` |
| Params | `eye_distance`, `eye_distance_left`, `eye_distance_right`, `eye_distance_side` |

O Comprimento só puxa o canto de fora e deixa a íris. Aqui o olho inteiro desliza.

---

## 2. Equação

```
t ∈ [-1, 1] por lado da foto
identidade se |tPhotoLeft| e |tPhotoRight| ≤ 1e-6

dx = t_lado · 0.030 · faceWidth · w · side
dy = 0
```

`side` é o sinal de (íris − linha do meio). A linha do meio é a média das duas íris. Foto esquerda fica com `side = −1` (afastar é ir para a esquerda). Foto direita fica com `side = +1`.

Foto esquerda = íris **468**.  
Foto direita = íris **473**.

```
w = planalto(hull do olho) × BoundaryFeather × porta(sobrancelha) × porta(nariz)
```

Cada olho tem o seu hull. Onde as duas rampas se encontram, os `dx` opostos somam-se e o meio fica parado. Sem disco binário. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar os outros Fields.

O runtime cacheia `w · side`. O slider só escala `dx`. `w` **não** depende de `t`.

---

## 3. Domínio

O hull do Tamanho, copiado, com pad maior para o contorno ficar no planalto. Não importado.

| Constante | Valor |
|---|---|
| Amplitude | `0.030 × faceWidth` |
| Hull pad | `0.09 × faceWidth` (o contorno fica no planalto) |
| Rampa de bordo | `0.07 × faceWidth` |
| Porta nariz | `0.10 × faceWidth` |
| Porta sobrancelha | vão real até à pálpebra (159 / 386), depois um borrão curto. A pálpebra anda com a íris. A sobrancelha fica |
| 468 / 473 | **andam** para fora se `t > 0`, para dentro se `t < 0` |
| 33 / 263 | **andam** com a íris |
| `dy` | **0** em todo o campo |
| 105 / 334 | **ficam** |
| nariz / boca / 10 | ≈ 0 |

---

## 4. Pipeline e menu

```
head → hairline → eyebrow_height → eyebrow_width → eyebrow_end → eye_size → eye_height → eye_width → eye_length → eye_distance → jaw → …
```

Tab Olhos, ícone Distância ao lado de Comprimento. Preview e export partilham `applyFaceWarpChain`.

---

## 5. O que não entra

- Alterar Tamanho, Altura, Largura, Comprimento nem os Fields vivos
- Puffy eyes
