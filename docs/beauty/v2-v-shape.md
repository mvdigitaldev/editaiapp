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

`w` = distância à polilinha do oval **93→132→58→172→136→150** / **323→361→288→397→365→379** (com pontos médios) × rampa de bordo × rampa midline × entalhe suave no pad interno/152. A crista **não** é `max` de gaussianas. Sem ilha no 152. Sem segmento que volte atrás (172→136→58 cortava a silhueta).

---

## 3. Crista

| Lado (MediaPipe) | IDs | Pesos |
|---|---|---|
| Esquerdo | 93 → 132 → 58 → 172 → 136 → 150 (ordem do oval) | 0.06 → 0.28 → 0.68 → 1.00 → 0.86 → 0.45 |
| Direito | 323 → 361 → 288 → 397 → 365 → 379 | idem |

Não entra no pad interno (148/176/149). Não substitui Jaw: o pico continua na
curva da mandíbula (172/397) e a lateral do rosto leva só 6% a 28%.

**Alargada em 2026-09-02** (ver secção 5). Era `58 → 172 → 136` com
`0.20 → 1.00 → 0.62`.

| Constante | Valor |
|---|---|
| Amplitude | `0.055 × faceWidth` |
| σ transversal | `0.13 × faceWidth` |
| Rampa de bordo | `0.16 × faceWidth` |
| Hull pad | `0.09 × faceWidth` |
| Midline | rampa `0.10 × faceWidth` (fixa) |
| 148 / 176 / 149 / 377 / 400 / 378 / 152 | hard-zero (V Chin / Chin Length) |
| 132 / 361 | cauda de peso `0.28` — **já não é hard-zero** (secção 5) |
| 93 / 323 / 150 / 379 | cauda, e no hull via `taperLandmarks` |
| 58 / 288 | sopro na polilinha (`0.68`), não disco duro |

---

## 4. Calibração do corte seco (p05 / p12)

No máximo, o pico isolado em 172/397 dentava a silhueta e o pescoço não acompanhava (degrau). A polilinha segue o oval **sem voltar atrás**; σ e rampa de bordo um pouco mais largas para o pescoço seguir o maxilar.

---

## 5. O bico na silhueta somado ao Jaw (2026-09-02)

Leonardo, com Mandíbula a 100% e Formato V a 100% à direita: «ainda existe essa
curva muito forte, não deve haver esses cortes secos; no final, se vai invadir a
outra área, deve mexer na outra área também com menos intensidade, é o que o
Meitu faz».

Medido o deslocamento total ao longo do oval, em p01:

| | 93 | 132 | 58 | 172 | 136 | 150 |
|---|---|---|---|---|---|---|
| Jaw | 2.0 | 8.5 | 9.6 | 8.9 | 6.1 | 1.4 |
| V Shape, antes | 0.0 | 0.0 | 1.9 | 11.6 | 6.9 | 3.5 |
| **Total, antes** | 2.2 | 10.3 | 14.1 | **23.5** | 14.2 | 4.9 |
| V Shape, agora | 0.6 | 3.3 | 8.0 | 11.6 | 9.9 | 5.0 |
| **Total, agora** | 2.8 | 14.1 | 22.1 | **24.2** | 17.5 | 6.7 |

O Jaw sozinho é um planalto na silhueta. O V Shape punha-lhe em cima um pico
isolado, e o total dava 23,5 px no 172 contra 14 px nos vizinhos — **1,66×**,
que é a concavidade abrupta que se via. Duas causas somadas:

1. **O peso caía a `0.20` no gónio**, logo o efeito vivia num arco de ~35 px.
2. **O disco binário de 132/361.** Raio `0.06 × faceWidth` (22 px), somado ao
   `protected`. Com a rampa de bordo de `0.16 × faceWidth` (60 px) por cima,
   apagava o efeito em toda a zona do gónio: o 58, a 40 px do disco, ficava com
   1,9 px, enquanto o 172, a 75 px, levava os 11,6 px plenos.

**Correcção.** Caudas na crista para os dois lados (`93/132` acima, `150`
abaixo), `taperLandmarks` no hull para lhes dar domínio, e o disco de 132/361
fora do `protected` — a máscara fica só como régua das métricas. Quem gradua a
cauda passou a ser o peso da crista, que é o controlo próprio para «menos
intensidade», em vez de um corte binário.

O total ficou em **1,10×**: planalto que sobe do 93 ao 172 e desce ao mento.
`minDetJ > 0` em `t = ±1` nas cinco faces, campo continua só Δx, e os
hard-zeros do pad interno, 152, olhos, boca e orelhas estão intactos.

**Consequência assumida:** o efeito ganhou alcance e o slider ao máximo afina
agora a mandíbula toda, não só a curva. Na zona do gónio o campo passou de 1,9 a
8,0 px. A amplitude de pico não mudou (`0.055 × faceWidth`), o pico continua no
172/397, e a cauda na zona do Jaw está limitada por teste a menos de 55% do
pico. Falta assinatura visual de Leonardo.

Travões novos: `Mandíbula e Formato V somam sem bico na silhueta` (razão entre
vizinhos abaixo de 1,35, e cauda no 132 acima de 35% do pico — rejeita tanto o
bico anterior como uma cauda que não chegue) e o tecto de curvatura no núcleo.

---

## 6. O que não entra

- Alterar V Chin / Jaw / Chin Length / Cheekbones H
- Arco maçã→mandíbula (Face Slim)
- Reutilizar a key `v_face`
- Assinar Sprint C
