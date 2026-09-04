# Hairline — linha do cabelo

Efeito novo. **Não** é Temple. **Não** é Lift. **Não** é a key morta `forehead`.

Data: 2026-09-03.  
Aprovação: Leonardo assinou a Sprint C (2026-09-03). Vivo no produto. Jaw, Chin, V Chin, V Shape, Cheekbones H e Jaw Angle não se mexem. Temple não se abre neste efeito.

Módulo: `lib/features/editor/beauty_engine/warp/v2/hairline/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).  
Plano: [`v2-hairline-plan.md`](./v2-hairline-plan.md).

---

## 1. Papel

Meitu Hairline: a **linha do cabelo** (arco pele/cabelo, têmpora a têmpora) **não se move**. O cabelo, do lado de lá da linha, cresce para fora ou encolhe até à linha. Vale em todas as fotos: L é o arco detectado, não um desenho. Temple (Δx isolado nas têmporas) fica efeito futuro.

| Peça | Vigente (2026-09-03, a partir da linha) |
|---|---|
| Key | `hairline` (nunca `forehead`) |
| Label | **Linha do cabelo** |
| Slider | Bipolar Meitu: centro = 0. **Sem** flag L/R |
| Convenção | **Esquerda = infla** (`t < 0`, cresce a partir da linha). **Direita = desincha** (volta até à linha) |
| Field | `D ∝ w · (p − q)`, `q` = projecção em L. Em L e na testa, `D = 0` |
| Escala | `0.10` (adimensional) |
| Pico | Cap acima do **10** (o 10 fica parado) |
| Têmporas | Cauda de peso baixo em 21/251. **Nunca** disco |

A–E fechadas. C: [`v2-hairline-c-report.md`](./v2-hairline-c-report.md). Reaberto só para esta equação.

A primeira A (só Δy no 10) e o Field radial `D ∝ (p − 9)` com crista no cume ficaram rejeitados: ou a linha mexia e o cabelo não, ou só o topo do cap mexia.

---

## 2. Equação

```
t ∈ [-1, 1]
identidade se |t| ≤ 1e-6

L = 21 → 103 → 67 → 109 → 10 → 338 → 297 → 332 → 251
q = projecção de p em L

w = peso ao longo de L × rampa de bordo
    (sem decaimento transversal)

D = 0  na linha, na testa (lado do 9) e fora da banda
D = −sign(t) · |t| · 0.10 · w · (p − q)  no cabelo
```

`src = dest − D`. Em L, `p − q = 0`. No cabelo, `p − q` é o leque: cima no centro, fora nos lados. O 9 só decide o lado; **não** é origem.

- `t < 0` → infla (cabelo para fora da linha). Coroa sobe; lados sobem/abrem. Linha parada.
- `t > 0` → desincha (cabelo volta até à linha)
- `t = 0` → campo nulo

`q` e o peso ao longo de L vêm de [RidgeWeight.project](../../lib/features/editor/beauty_engine/warp/v2/ridge_weight.dart) (média na medial axis, como o peso dos outros Fields). A rampa de bordo é [BoundaryFeather](../../lib/features/editor/beauty_engine/warp/v2/boundary_feather.dart). **Não** é `max` de gaussianas. **Não** é `at` com σ transversal — isso matava o cap.

O runtime cacheia `unitDx` / `unitDy` (`w · (p − q)`). O slider só reescala.

Isto **não** é Temple: o Δx nos lados é a componente do leque no cabelo, acima da linha.

---

## 3. Linha e banda

| Peça | IDs | Pesos |
|---|---|---|
| Linha L | 21 → 103 → 67 → 109 → 10 → 338 → 297 → 332 → 251 | 0.15 → 0.55 → 0.75 → 0.92 → 1.00 → 0.92 → 0.75 → 0.55 → 0.15 |

L **não se move**. O domínio é a **banda** do cabelo: o mesmo arco + o arco levantado `crownExtend` (103/67/109/10/338/297/332). Pad `0.10 × faceWidth`. Sem 9/151 no hull. Sem disco no 10.

| Constante | Valor |
|---|---|
| Escala | `0.10` |
| Rampa de bordo | `0.16 × faceWidth` |
| Hull pad | `0.10 × faceWidth` |
| Crown extend | `0.70 × faceWidth` (limitado pelo topo da imagem; só a banda, não a crista) |
| ridgeBlend | `0.012 × faceWidth` |
| 9 / 151 | lado da testa (porta); não origem |
| 10 / 103 / 67 / 109 e espelhos | **parados** (estão em L) |
| 21 / 162 / 127 / 251 / 389 / 356 | cauda / métrica (têmpora) |
| 123 / 352 | hard-zero (maçã) |
| olhos / brows / nariz / boca / orelhas / mento | hard-zero |

---

## 4. Pipeline e menu

Cadeia (primeiro):

```
hairline → jaw → jaw_angle → chin → v_chin → v_shape → cheekbone
```

Painel Rosto: **último** ícone. Slider bipolar «Linha do cabelo», sem L/R. Preview e export usam o mesmo `applyFaceWarpChain`. Aprovado.

---

## 5. O que não entra

- Alterar Jaw / Chin Length / V Chin / V Shape / Cheekbones H / Jaw Angle
- Temple, Width, Lift, Double Chin
- Reutilizar a key `forehead`
- Disco binário nas têmporas
- Reabrir o Field sem calibração pedida por escrito
- Voltar ao Δy-only (rejeitado: o contorno do cabelo não mexia)
