# Eye Size — tamanho do olho

Efeito novo. **Não** é `eye_scale`. **Não** é Height, Width, Length, Distance nem Puffy eyes. **Não** é makeup (`eyelashes`, `iris_enhance`).

No Meitu, **Size** é o primeiro ícone do tab Olhos. O slider à esquerda encolhe os dois olhos. À direita aumenta. Geral / Esquerda / Direita = lados da foto.

Data: 2026-09-29.  
Estado: no editor para aprovação visual. Sem B escrita. Sem C assinada. Sem E. Os Fields vivos **não se mexem**.

Módulo: `lib/features/editor/beauty_engine/warp/v2/eye_size/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

---

## 1. Papel

A abertura do olho cresce ou encolhe em volta da íris. A íris fica no sítio. A sobrancelha, o nariz, a boca e a linha do cabelo ficam.

| Peça | Vigente |
|---|---|
| Key | `eye_size` (nunca `eye_scale`) |
| Label | **Tamanho** (tab Olhos) |
| Slider | Bipolar. Geral / L / R = lados da **foto** |
| Convenção | **Esquerda = encolhe** (`t < 0`). **Direita = aumenta** (`t > 0`) |
| Field | Escala local. `dx` e `dy` |
| Ganho | `k = 0.28` (`s` de 0.72 a 1.28) |
| Params | `eye_size`, `eye_size_left`, `eye_size_right`, `eye_size_side` |

---

## 2. Equação

```
t ∈ [-1, 1] por lado da foto
identidade se |tPhotoLeft| e |tPhotoRight| ≤ 1e-6

s = 1 + 0.28 · t_lado
α = 1 − 1/s
D = α · w · (p − c)
```

`c` é a íris daquele olho, calculada **por lado** (468 e 473). Não se mistura o centro com `leftFrac`: no meio os dois hulls empatam e o campo saltava.

Foto esquerda = íris **468**, canto **33**.  
Foto direita = íris **473**, canto **263**.

```
w = planalto(hull do olho) × BoundaryFeather × porta(sobrancelha) × porta(nariz)
```

A porta é smoothstep da distância à máscara. Sem disco binário. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Sobrancelha, Head nem os outros Fields.

O runtime cacheia `w · (p − c)`. O slider só entra em `α(t)`. `w` **não** depende de `t`.

---

## 3. Domínio

Hull do contorno de cada olho, dilatado `0.025 × faceWidth`. Olhos separados. A sobrancelha não é buraco no hull.

| Constante | Valor |
|---|---|
| Ganho | `0.28` |
| Hull pad | `0.025 × faceWidth` |
| Rampa de bordo | `0.07 × faceWidth` |
| Porta sobrancelha / nariz | `0.04 × faceWidth` |
| 33 / 263 | **andam** para fora se `t > 0`, para dentro se `t < 0` |
| 468 / 473 | **ficam** |
| 105 / 334 | **ficam** |
| nariz / boca / 10 | ≈ 0 |

---

## 4. Pipeline e menu

```
head → hairline → eyebrow_height → eyebrow_width → eyebrow_end → eye_size → jaw → …
```

Tab Olhos, ícone Tamanho. Preview e export partilham `applyFaceWarpChain`.

---

## 5. O que não entra

- Alterar Jaw / Chin / V Chin / V Shape / Cheekbones H / Jaw Angle / Hairline / Head / Eyebrow Height / Eyebrow Width / Eyebrow End
- Key `eye_scale`
- Height, Width, Length, Distance, Puffy eyes
- Makeup de cílios ou íris
