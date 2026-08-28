# V Chin — formato V do queixo

**Aprovado e encerrado** no editor (2026-08-26). Não reabrir.

**Não** é Chin Length. **Não** é V shape.

Módulo: `lib/features/editor/beauty_engine/warp/v2/v_chin/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

---

## 1. Papel

Meitu V Chin: forma da ponta do mento (ícone a tracejado). O slider `chin` continua a ser só length (Δy).

| Peça | Vigente |
|---|---|
| Key | `v_chin` (**não** `v_face`) |
| Label | **V do queixo** |
| Slider | Bipolar Meitu: centro = 0, sem %. Flag Geral / Esquerda / Direita = lados da **foto** |
| Convenção | **Esquerda = V** (lados para a midline, Meitu). **Direita = quadrado** (lados para fora) |
| Field | Só Δx. `dy = 0`. 152 ≈ 0 por simetria. Gônios hard-zero |
| Amplitude | `0.080 × faceWidth` |
| Params | `v_chin`, `v_chin_left`, `v_chin_right`, `v_chin_side` |
| Estado | Aprovado. Vivo em preview/export. Encerrado |

---

## 2. Equação

```
t ∈ [-1, 1] por lado da foto
identidade se |tPhotoLeft| e |tPhotoRight| ≤ 1e-6

dx = sign(midlineX − x) · (−t_lado) · 0.080 · faceWidth · w
dy = 0
```

`t_lado < 0` (esquerda) produz deslocamento para a midline. Foto esquerda = cadeia MediaPipe direita (377). Foto direita = cadeia MediaPipe esquerda (148).

- `t < 0` → para a midline / ponta mais em V (esquerda Meitu)
- `t > 0` → para fora / queixo mais quadrado
- `t = 0` → campo nulo

`w` = distância à polilinha do pad do mento (com pontos médios), rampa de bordo e rampa na midline. **Não** é `max` de gaussianas. Sem ilha no 152.

---

## 3. Crista

| Lado (MediaPipe) | IDs | Pesos |
|---|---|---|
| Esquerdo | 148 → 176 → 149 → 150 → 136 | 1.00 → 0.78 → 0.55 → 0.32 → 0.14 |
| Direito | 377 → 400 → 378 → 379 → 365 | idem |

Para **antes** de 172/58. Não sobe a 132/361.

| Constante | Valor |
|---|---|
| Amplitude | `0.080 × faceWidth` |
| σ transversal | `0.11 × faceWidth` |
| Rampa de bordo | `0.12 × faceWidth` |
| Hull pad | `0.06 × faceWidth` |
| Midline | rampa `0.11 × faceWidth` (fixa; não escala com A) |
| 152 | ≈ 0 por simetria ímpar (`dy = 0`; Chin Length fica com o Δy). Sem entalhe. |
| 58 / 288 / 132 / 361 | hard-zero |

---

## 4. O que não entra

- Alterar `ChinField` / Jaw / Cheekbones H / este Field
- V shape (arco maçã→mandíbula) — `v_face` continua fantasma
- Double Chin, pescoço
- Reutilizar a key `v_face`
