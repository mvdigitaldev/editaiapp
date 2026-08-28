# V Shape — silhueta externa do queixo

Efeito novo. **Não** é V Chin. **Não** é Jaw. **Não** é Sprint C assinada.

Data: 2026-08-26.  
Aprovação: Leonardo pediu o Formato V (bordo de fora, sopro na curva da mandíbula, L/R). V Chin, Jaw, `chin` e Cheekbones H não se mexem.

Módulo: `lib/features/editor/beauty_engine/warp/v2/v_shape/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

---

## 1. Papel

Meitu V Shape: contorno **externo** (setas na linha da cara). O `v_chin` continua a ser a ponta **interna**.

| Peça | Vigente |
|---|---|
| Key | `v_shape` (**não** `v_face`) |
| Label | **Formato V** |
| Slider | Bipolar Meitu: centro = 0, sem %. Flag Geral / Esquerda / Direita = lados da **foto** |
| Convenção | **Direita = V** (bordo para a midline). **Esquerda = quadrado** (bordo para fora) |
| Field | Só Δx. `dy = 0`. Interior 148/176/149 hard-zero. 152 hard-zero |
| Amplitude | `0.055 × faceWidth` |
| Params | `v_shape`, `v_shape_left`, `v_shape_right`, `v_shape_side` |

Inspecção no editor. C/D/E **não** assinadas.

---

## 2. Equação

```
t ∈ [-1, 1] por lado da foto
identidade se |tPhotoLeft| e |tPhotoRight| ≤ 1e-6

dx = sign(midlineX − x) · t_lado · 0.055 · faceWidth · w
dy = 0
```

Foto esquerda = cadeia MediaPipe direita (397). Foto direita = cadeia MediaPipe esquerda (172).

- `t > 0` → bordo para a midline / V visível (direita Meitu)
- `t < 0` → bordo para fora / mais quadrado
- `t = 0` → campo nulo

`w` = distância à polilinha do oval **58→172→136** / **288→397→365** (com pontos médios) × rampa de bordo × rampa midline × entalhe suave no pad interno/152. A crista **não** é `max` de gaussianas. Sem ilha no 152. Sem segmento que volte atrás (172→136→58 cortava a silhueta).

---

## 3. Crista

| Lado (MediaPipe) | IDs | Pesos |
|---|---|---|
| Esquerdo | 58 → 172 → 136 (ordem do oval) | 0.20 → 1.00 → 0.62 |
| Direito | 288 → 397 → 365 | idem |

Não entra no pad interno (148/176/149). Não sobe a 132/361. Não substitui Jaw.

| Constante | Valor |
|---|---|
| Amplitude | `0.055 × faceWidth` |
| σ transversal | `0.13 × faceWidth` |
| Rampa de bordo | `0.16 × faceWidth` |
| Hull pad | `0.09 × faceWidth` |
| Midline | rampa `0.10 × faceWidth` (fixa) |
| 148 / 176 / 149 / 377 / 400 / 378 / 152 | hard-zero (V Chin / Chin Length) |
| 132 / 361 | hard-zero |
| 58 / 288 | sopro na polilinha (~0.20), não disco duro |

---

## 4. Calibração do corte seco (p05 / p12)

No máximo, o pico isolado em 172/397 dentava a silhueta e o pescoço não acompanhava (degrau). A polilinha segue o oval **sem voltar atrás**; σ e rampa de bordo um pouco mais largas para o pescoço seguir o maxilar.

---

## 5. O que não entra

- Alterar V Chin / Jaw / Chin Length / Cheekbones H
- Arco maçã→mandíbula (Face Slim)
- Reutilizar a key `v_face`
- Assinar Sprint C
