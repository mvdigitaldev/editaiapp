# Eyebrow End — ponta interna (juntar / separar)

Efeito novo. **Não** é o makeup `eyebrows`. **Não** é Altura (`eyebrow_height`). **Não** é Largura (`eyebrow_width`). **Não** é Length / Front / Angle / Shape.

No Meitu, **End** é a ponta **interna** (glabela), não a cauda. O ícone aponta para o lado do nariz.

Data: 2026-09-04.  
Estado: Sprint D no editor. Sem E escrita. Jaw, Chin, V Chin, V Shape, Cheekbones H, Jaw Angle, Hairline, Head, Eyebrow Height e Eyebrow Width **não se mexem**. Lab: [`v2-eyebrow-end-b-report.md`](./v2-eyebrow-end-b-report.md). C: [`v2-eyebrow-end-c-report.md`](./v2-eyebrow-end-c-report.md). D: [`v2-eyebrow-end-d-report.md`](./v2-eyebrow-end-d-report.md).

Módulo: `lib/features/editor/beauty_engine/warp/v2/eyebrow_end/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).  
Plano: [`v2-eyebrow-end-plan.md`](./v2-eyebrow-end-plan.md).

---

## 1. Papel

As **pontas internas** aproximam-se ou afastam-se da linha média. A cauda fica. O arco quase não anda. Os olhos ficam. A linha do cabelo fica.

Leonardo (2026-09-04): «junta a sobrancelha se o slider for pra esquerda e separa se for pra direita, bem sutil, sem estragar e movendo apenas a sobrancelha».

| Peça | Vigente (Sprint D) |
|---|---|
| Key | `eyebrow_end` (nunca `eyebrows`, `eyebrow_height` nem `eyebrow_width`) |
| Label | **Ponta** (tab Sobrancelha) |
| Slider | Bipolar Meitu. Geral / L / R = lados da **foto** |
| Convenção | **Esquerda = junta** (`t < 0`). **Direita = separa** (`t > 0`) |
| Field | Só Δx. `dy = 0`. Terço interno; cauda e arco quase parados |
| Amplitude | `0.030 × faceWidth` (tecto de produto: `influenceMax < 0.040 × faceWidth`) |
| Params | `eyebrow_end`, `eyebrow_end_left`, `eyebrow_end_right`, `eyebrow_end_side` |

A Altura é um planalto Δy. A Largura abre a ilha em Δy a partir do eixo. Copiar qualquer uma aqui só subia ou engrossava outra vez. Aqui o sinal é horizontal e só na glabela.

---

## 2. Equação

```
t ∈ [-1, 1] por lado da foto
identidade se |tPhotoLeft| e |tPhotoRight| ≤ 1e-6

dx = t_lado · 0.030 · faceWidth · w · band · s_inner · away
dy = 0
away = 2 · leftFrac − 1
s_inner = 1 se u ≤ 0.12; 0 se u ≥ 0.48; smoothstep no meio
u = (x − x_inner) / (x_outer − x_inner)
band = exp(−0.5 · (signedY / (1.4 · halfBand))²)
```

`s_inner` calcula-se **por lado** (`u` em 336→300 e em 107→70) e só depois mistura com `leftFrac`. Misturar os extremos primeiro colapsa o vão na glabela (`span → 0`) e o gate salta. `y_eixo` mistura L/R com o mesmo `leftFrac` (sem argmin de segmento).  
Foto esquerda = cadeia MediaPipe direita (ponta **107**).  
Foto direita = cadeia MediaPipe esquerda (ponta **336**).

`away = +1` no MP esquerdo / foto direita; `away = −1` no MP direito / foto esquerda. Com `t > 0` as pontas saem da midline; com `t < 0` entram.

```
w = planalto(hull) × BoundaryFeather × lidGate
```

`lidGate` = o da Altura/Largura: prateleira no terço externo + amostras no vão cauda→canto. Sem disco binário. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Altura nem Largura.

`leftFrac` contínuo (`0.12 × faceWidth`). Porta seca na glabela invertia. O runtime cacheia `w · band · s_inner · away`. O slider só escala `dx`. `w` **não** depende de `t`.

---

## 3. Domínio

Mesma ilha dilatada da Altura/Largura. Olhos **não** são buraco no domínio. Landmark 10 parado. Não se furam discos em L.

| Constante | Valor |
|---|---|
| Amplitude | `0.030 × faceWidth` |
| innerHold / innerEnd | `0.12` / `0.48` |
| bandScale | `1.4` |
| halfBand | metade da espessura medida, clamp `0.012…0.024 × faceWidth` |
| Hull pad | `0.14 × faceWidth` |
| Rampa de bordo | `0.12 × faceWidth` |
| Lid falloff | `0.08 × faceWidth` |
| Outer lid lift | `0.026 × faceWidth` |
| 336 / 107 | **andam** (ponta interna; métrica primária) |
| 334 / 105 | **quase parados** (≤ 45% do pico interno) |
| 300 / 70 | **quase parados** (≤ 25% do pico interno) |
| 159 / 386 | **parados** |
| vão 70–33 / 300–263 | **≤ 20%** do pico |
| 10 / olhos / boca / nariz | ≈ 0 |

Pico do campo no extremo `< 0.040 × faceWidth`. Calibração 2026-09-04: `0.010`…`0.020` ainda sutis; vigente `0.030`.

---

## 4. Landmarks

| Lado | Papel | IDs |
|---|---|---|
| MP esquerdo (foto direita) | hull | `276 283 282 295 285 336 296 334 293 300` |
| MP direito (foto esquerda) | hull | `46 53 52 65 55 107 66 105 63 70` |
| Primário | ponta interna | **336** / **107** |
| Arco | deve ficar | **334** / **105** |
| Cauda | deve ficar | **300** / **70** |
| Eixo (banda) | médios (sup, inf) | `(300,276) (293,283) (334,282) (296,295) (336,285)` / `(70,46) (63,53) (105,52) (66,65) (107,55)` |

---

## 5. Pipeline e menu

Cadeia (D):

```
head → hairline → eyebrow_height → eyebrow_width → eyebrow_end → jaw → …
```

Tab Sobrancelha, ícone Ponta ao lado de Largura. Preview e export partilham `applyFaceWarpChain`.

---

## 6. O que não entra

- Alterar Jaw / Chin / V Chin / V Shape / Cheekbones H / Jaw Angle / Hairline / Head / Eyebrow Height / Eyebrow Width
- Key `eyebrows` (makeup)
- Length, Front, Angle, Shape
- Alterar o Field sem calibração pedida
- Assinar Sprint E (export já é o mesmo grafo)
- Mexer a cauda (300/70) ou o arco como se fossem a ponta
- `PersonMask`, parsing `browG`, Telea
