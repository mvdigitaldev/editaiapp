# Eyebrow Width — largura / espessura da sobrancelha

Efeito novo. **Não** é o makeup `eyebrows`. **Não** é Altura (`eyebrow_height`). **Não** é Length / End / Front / Angle / Shape.

Data: 2026-09-04.  
Estado: Sprint D (preview). C assinada. Sem E escrita. Jaw, Chin, V Chin, V Shape, Cheekbones H, Jaw Angle, Hairline, Head e Eyebrow Height **não se mexem**.

Módulo: `lib/features/editor/beauty_engine/warp/v2/eyebrow_width/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).  
Plano: [`v2-eyebrow-width-plan.md`](./v2-eyebrow-width-plan.md).

---

## 1. Papel

A ilha da sobrancelha **engrossa ou afina** a partir do eixo: o arco sobe um pouco, a base desce um pouco. Os olhos ficam. A linha do cabelo fica. O arco não muda de forma (isso é Shape).

Leonardo (2026-09-04): «deixar ela minimamente mais larga, é bem pouca coisa para ficar bem real, se não fica com cara de edição… uma leve engrossada».

| Peça | Vigente (Sprint D) |
|---|---|
| Key | `eyebrow_width` (nunca `eyebrows` nem `eyebrow_height`) |
| Label | **Largura** (tab Sobrancelha) |
| Slider | Bipolar Meitu. Geral / L / R = lados da **foto** |
| Convenção | **Esquerda = afina** (`t < 0`). **Direita = engrossa** (`t > 0`) |
| Field | Só Δy. `dx = 0`. Peso assinado a partir do eixo da ilha |
| Amplitude | `0.008 × faceWidth` (~¼ da Altura; teto de produto: leve) |
| Params | `eyebrow_width`, `eyebrow_width_left`, `eyebrow_width_right`, `eyebrow_width_side` |

A Altura é um planalto que sobe em bloco. Copiar essa equação aqui só levantaria a sobrancelha outra vez. A estrutura é a mesma (ilha, `lidGate`, L/R, runtime); o sinal não.

---

## 2. Equação

```
t ∈ [-1, 1] por lado da foto
identidade se |tPhotoLeft| e |tPhotoRight| ≤ 1e-6

dx = 0
dy = t_lado · 0.008 · faceWidth · w · s
s = tanh((y − y_eixo) / halfBand)
```

`y_eixo` = interpolação em X da polilinha dos médios, misturada L/R com o mesmo `leftFrac` da amplitude. Sem argmin de segmento (empatava na medial e o `s` dava degrau; em p05 o vinco no núcleo era 0,46). Sem `clamp` linear (joelho nas bandas do núcleo): `tanh`.  
`s > 0` abaixo do eixo (para a pálpebra). `s < 0` acima.

- `t > 0` → engrossa: arco `dy < 0`, base `dy > 0`
- `t < 0` → afina: o contrário
- `t = 0` → campo nulo

```
w = planalto(hull) × BoundaryFeather × lidGate
```

`lidGate` = o da Altura: prateleira no terço externo + amostras no vão cauda→canto. Sem disco binário. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar o Field da Altura.

`leftFrac` contínuo (`0.12 × faceWidth`). O runtime cacheia `w · s`. O slider só escala `dy`.

---

## 3. Domínio

Mesma ilha dilatada da Altura. Olhos **não** são buraco no domínio. Landmark 10 parado. Não se furam discos em L.

| Constante | Valor |
|---|---|
| Amplitude | `0.008 × faceWidth` |
| halfBand | metade da espessura medida, clamp `0.012…0.024 × faceWidth` |
| Hull pad | `0.14 × faceWidth` |
| Rampa de bordo | `0.12 × faceWidth` |
| Lid falloff | `0.08 × faceWidth` |
| Outer lid lift | `0.026 × faceWidth` |
| 334 / 105 | **andam para cima** ao engrossar |
| 282 / 52 | **andam para baixo** ao engrossar |
| 159 / 386 | **parados** |
| vão 70–33 / 300–263 | **≤ 20%** do pico |
| 10 / olhos / boca / nariz | ≈ 0 |

Pico do campo no extremo `< 0.012 × faceWidth` (trava a «cara de edição»).

---

## 4. Landmarks

| Lado | Papel | IDs |
|---|---|---|
| MP esquerdo (foto direita) | hull | `276 283 282 295 285 336 296 334 293 300` |
| MP direito (foto esquerda) | hull | `46 53 52 65 55 107 66 105 63 70` |
| Eixo | médios (sup, inf) | `(300,276) (293,283) (334,282) (296,295) (336,285)` / `(70,46) (63,53) (105,52) (66,65) (107,55)` |

---

## 5. Pipeline e menu

Cadeia (D):

```
head → hairline → eyebrow_height → eyebrow_width → jaw → …
```

Tab Sobrancelha, ícone Largura ao lado de Altura. Preview e export partilham `applyFaceWarpChain`.

---

## 6. O que não entra

- Alterar Jaw / Chin / V Chin / V Shape / Cheekbones H / Jaw Angle / Hairline / Head / Eyebrow Height
- Key `eyebrows` (makeup)
- Length, End, Front, Angle, Shape
- Alterar o Field sem calibração pedida
- Assinar Sprint E (export já é o mesmo grafo)
