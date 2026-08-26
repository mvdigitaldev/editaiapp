# Chin Length bipolar — tamanho do queixo

Calibração de produto do slider `chin` já aprovado (D/E). **Não** é Sprint A–E nova. **Não** é V Chin nem Double Chin.

Data: 2026-08-26.  
Aprovação: Leonardo reabriu o Chin **só neste âmbito**. Jaw e Cheekbones H não se mexem.

Módulo: `lib/features/editor/beauty_engine/warp/v2/chin/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

---

## 1. Papel

Este slider é **Chin Length** (Meitu): eixo vertical da ponta do queixo, com a curva do oval até **próximo da mandíbula**.

| Peça | Vigente |
|---|---|
| Key | `chin` (não muda) |
| Label | **Tamanho do queixo** |
| Slider | Bipolar Meitu: centro = 0 (identidade), sem %. Sem flag L/R |
| Convenção | **Esquerda = aumenta** (queixo mais comprido, `dy > 0` no 152). **Direita = reduz** (encurta, `dy < 0`) |
| Field | Só Δy. `dx = 0`. Crista no oval mento→172/397. Gônios **fora** da crista (só vestígio) |
| Amplitude | `0.07 × faceWidth` |

Menus futuros (V Chin, Double Chin) = **keys novas**, não este slider.

---

## 2. Equação

```
t ∈ [-1, 1]
identidade se |t| ≤ 1e-6

weight = w_crista(s) · exp(−d² / (2 σ⊥²)) · rampa_borda
dy = −sign(t) · |t| · 0.07 · faceWidth · weight
dx = 0
```

`d` = distância à polilinha do oval. `w_crista` interpola ao longo do segmento.  
**Não** é `max` de gaussianas no mento: isso deixava a curva a morrer antes da mandíbula.

- `t > 0` → curva sobe / encurta.
- `t < 0` → curva desce / alonga.
- `t = 0` → campo nulo.

---

## 3. Crista (calibração vigente)

| Lado (MediaPipe) | IDs (mento → perto da mandíbula) | Pesos |
|---|---|---|
| Esquerdo | 152 → 148 → 176 → 149 → 150 → 136 → **172** | 1.00 → 0.90 → 0.78 → 0.60 → 0.40 → 0.22 → **0.08** |
| Direito | 152 → 377 → 400 → 378 → 379 → 365 → **397** | idem |

Pontos médios entre âncoras, como nas maçãs. **Não** inclui 58/288 (gônio) nem 132/361 (entalhe / Cheekbones H).

| Constante | Valor |
|---|---|
| Amplitude | `0.07 × faceWidth` |
| σ transversal | `0.08 × faceWidth` |
| Rampa de bordo | `0.12 × faceWidth` |
| Hull pad | `0.07 × faceWidth` |
| 132 / 361 | hard-zero (entalhe oval) |
| 58 / 288 | fora da crista e do hull. Vestígio só se o pad chegar lá. Não substitui Jaw |

---

## 4. O que não entra

- V Chin (ponta aguda) — key futura
- Double Chin (papada / pescoço) — key futura, bloqueada sem pescoço
- Pescoço como efeito próprio
- Δx no gônio (isso é o Jaw)
- Flag Geral / Esquerda / Direita
- Alterar Jaw
- Alterar Cheekbones H
