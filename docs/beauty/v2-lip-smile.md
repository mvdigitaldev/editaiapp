# Lip Smile — sorriso

Efeito novo. **Não** é `lip_size`, `lip_width`, `lip_height`, `lip_angle` nem `lip_plump`. **Não** é a key antiga `smile`. **Não** é Rotate, M-shaped nem Whiten.

No Meitu, **Smile** é o ícone com o canto da boca a subir. O slider à direita levanta os dois cantos. À esquerda baixa (carranca). Um slider só. Sem Geral / L / R.

Data: 2026-10-01.  
Estado: no editor para aprovação visual. Sem B escrita. Sem C assinada. Sem E. Tamanho, Largura, Altura, Ângulo, Volume e os Fields vivos **não se mexem**. Rotate / M-shaped / Whiten ainda não existem.

Módulo: `lib/features/editor/beauty_engine/warp/v2/lip_smile/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

---

## 1. Papel

Os cantos sobem (ou descem) e abrem um pouco para fora. O centro da boca, o nariz e o queixo ficam.

| Peça | Vigente |
|---|---|
| Key | `lip_smile` |
| Label | **Sorriso** (tab Lábios) |
| Slider | Bipolar. Um só, a boca inteira |
| Convenção | **Esquerda = carranca** (`t < 0`, cantos descem). **Direita = sorriso** (`t > 0`, cantos sobem) |
| Field | Δy nos cantos + Δx curto para fora |
| Ganho | `0.030 × faceWidth` em y; `0.010 × faceWidth` em x |
| Params | `lip_smile` |

---

## 2. Equação

Perfil em U ao longo de 61→291 (eixo da foto, menor x → maior x): 1 nos cantos, 0 no meio.

```
t ∈ [-1, 1]
identidade se |t| ≤ 1e-6

u = projecção no eixo foto-esquerda → foto-direita
perfil = (2u − 1)²
dx = t · 0.010 · faceWidth · w · perfil · (2u − 1)
dy = −t · 0.030 · faceWidth · w · perfil
```

```
w = planalto(hull dos lábios) × BoundaryFeather × porta(nariz) × porta(queixo) × porta(olhos) × porta(sobrancelha)
```

Sem disco binário. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Tamanho, Largura, Altura, Ângulo, Volume nem os outros Fields.

O runtime cacheia `w · perfil · (2u − 1)` e `w · perfil`. O slider só escala `dx` e `dy`.

---

## 3. Domínio

Hull de `V2RegionCatalog.lips`, dilatado `0.040 × faceWidth`.

| Constante | Valor |
|---|---|
| Ganho y | `0.030 × faceWidth` |
| Ganho x | `0.010 × faceWidth` |
| Hull pad | `0.040 × faceWidth` |
| Rampa de bordo | `0.055 × faceWidth` |
| Porta nariz / queixo / olhos / sobrancelha | `0.045 × faceWidth` |
| 61 / 291 | **andam** (sobe/desce; um pouco para fora) |
| 0 / 17 | **ficam** |
| 1 / 152 / 468 / 473 / 105 / 10 | **ficam** |

---

## 4. Pipeline e menu

```
… → lip_plump → lip_smile → jaw → …
```

Tab **Lábios**, ícone Sorriso à direita de Volume.
