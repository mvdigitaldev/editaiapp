# Eyebrow Height — altura da sobrancelha

Efeito novo. **Não** é o makeup `eyebrows` (escurecer OKLab na tab Pele). **Não** é Hairline, Head, Temple nem Shape/Angle da sobrancelha.

Data: 2026-09-04.  
Estado: Sprint D no editor. Sem E escrita. Jaw, Chin, V Chin, V Shape, Cheekbones H, Jaw Angle, Hairline e Head **não se mexem**. Lab: [`v2-eyebrow-height-b-report.md`](./v2-eyebrow-height-b-report.md). C: [`v2-eyebrow-height-c-report.md`](./v2-eyebrow-height-c-report.md). D: [`v2-eyebrow-height-d-report.md`](./v2-eyebrow-height-d-report.md).

Módulo: `lib/features/editor/beauty_engine/warp/v2/eyebrow_height/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).  
Plano: [`v2-eyebrow-height-plan.md`](./v2-eyebrow-height-plan.md).

---

## 1. Papel

A **ilha da sobrancelha** sobe ou desce em bloco. Os olhos ficam. A linha do cabelo fica. A forma do arco não muda (isso é Shape / Angle, menus futuros).

| Peça | Vigente (Sprint A) |
|---|---|
| Key | `eyebrow_height` (nunca `eyebrows`) |
| Label | **Altura** (tab Sobrancelha) |
| Slider | Bipolar Meitu: centro = 0. Flag Geral / Esquerda / Direita = lados da **foto** |
| Convenção | **Esquerda = baixa** (`t < 0`, `dy > 0`). **Direita = sobe** (`t > 0`, `dy < 0`) |
| Field | Só Δy. `dx = 0`. Planalto no hull dos 10 IDs por lado. Sem pico no arco |
| Amplitude | `0.035 × faceWidth` (teto de produto B7: ≤8% da altura da cara) |
| Params | `eyebrow_height`, `eyebrow_height_left`, `eyebrow_height_right`, `eyebrow_height_side` |

Não é Width / Length / End / Front / Angle / Shape.

---

## 2. Equação

```
t ∈ [-1, 1] por lado da foto
identidade se |tPhotoLeft| e |tPhotoRight| ≤ 1e-6

dx = 0
dy = −t_lado · 0.035 · faceWidth · w
```

Foto esquerda = cadeia MediaPipe direita (`browRight`, primário **105**).  
Foto direita = cadeia MediaPipe esquerda (`browLeft`, primário **334**).

```
w = planalto(hull) × BoundaryFeather × lidGate
```

- `t > 0` → sobrancelha sobe (`dy < 0` em 334/105)
- `t < 0` → sobrancelha baixa (`dy > 0`)
- `t = 0` → campo nulo

O planalto é o hull convexo dos 10 landmarks da sobrancelha, dilatado. **Não** é `RidgeWeight` com pesos a cair no arco (isso seria Shape). **Não** é `max` de gaussianas. **Não** é leque a partir do 9.

`lidGate` = smoothstep da distância euclidiana ao hull dos olhos: 0 em cima da pálpebra, 1 a `0.08 × faceWidth`. Sem disco binário no vão. O hull dos olhos inclui a prateleira `0.026 × faceWidth` no terço externo (33/246/161, 263/466/388) e amostras a 30/45/58% do vão cauda→canto (70–33 / 300–263), para a dobra não ir com a brow. Spec B7: pálpebra `|D| ≤ 30%` do pico; dobra externa `|D| ≤ 20%`.

L/R não é porta binária: `leftFrac` é smoothstep da diferença de distâncias aos centróides (`0.12 × faceWidth`). Porta seca na glabela invertia (`minDetJ < 0`).

O runtime cacheia `unitWeight` / `useLeft`. O slider só escala `dy`. `w` **não** depende de `t`.

---

## 3. Domínio

Quem precisa de `w > 0` é o píxel de **destino** (remap backward). O hull dilatado cobre a ilha original **e** o sítio para onde a sobrancelha vai no extremo (`±A`).

Olhos **não** são um buraco no domínio: furar o hull punha a rampa de bordo no vão e comia o planalto. O `lidGate` zera a pálpebra por cima. Nariz, boca e linha L ficam de fora porque o hull não chega ao 10; **não** se furam discos em L (isso invertia o campo nas têmporas, `minDetJ < 0`).

| Constante | Valor |
|---|---|
| Amplitude | `0.035 × faceWidth` |
| Hull pad | `0.14 × faceWidth` |
| Rampa de bordo | `0.12 × faceWidth` |
| Lid falloff | `0.08 × faceWidth` |
| Outer lid lift | `0.026 × faceWidth` (prateleira no terço externo: 33/246/161 e 263/466/388) |
| Side blend | `0.12 × faceWidth` |
| 334 / 105 | **andam** (arco; métrica primária) |
| 282 / 52 | **andam** (contorno inferior; a ilha toda, não só o arco) |
| 159 / 386 | **parados** (pálpebra superior) |
| vão cauda→canto (70–33 / 300–263) | **≤ 20%** do pico (Leonardo 2026-09-04: puxava a dobra externa) |
| 10 / linha L | **parados** |
| olhos / boca / nariz | ≈ 0 |

---

## 4. Landmarks

| Lado | Papel | IDs |
|---|---|---|
| MP esquerdo (foto direita) | hull | `276 283 282 295 285 336 296 334 293 300` |
| MP direito (foto esquerda) | hull | `46 53 52 65 55 107 66 105 63 70` |
| Primário | métrica | **334** / **105** |
| Inferior | métrica (ilha) | **282** / **52** |
| Pálpebra | protecção | **386** / **159** |
| Terço externo + dobra | prateleira no hull dos olhos | 33/246/161, 263/466/388; vão 70–33 / 300–263 |

L/R: `useLeft` = mais perto do centróide MP esquerdo do que do direito.

---

## 5. Pipeline e menu

Cadeia (D):

```
head → hairline → eyebrow_height → eyebrow_width → jaw → …
```

Hairline continua a pôr brows em hard-zero **no campo dele** — correcto. Este Field é que as mexe. Sem importar Hairline.

Tab Sobrancelha, ícone Altura: no editor. Preview e export partilham `applyFaceWarpChain`.

---

## 6. O que não entra

- Alterar Jaw / Chin / V Chin / V Shape / Cheekbones H / Jaw Angle / Hairline / Head
- Key `eyebrows` (makeup)
- `PersonMask`, parsing `browG`, Telea
- Pico no arco / crista com pesos a cair
- Width, Length, End, Front, Angle, Shape
- Relatório E (o export já usa a mesma cadeia; sem sprint à parte até pedido)
