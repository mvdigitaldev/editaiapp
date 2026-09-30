# Nose Lift — elevação do nariz

Efeito novo. **Não** é `nose_size`. **Não** é Tip, Ala, Root nem Bridge.

No Meitu, **Lift** é o segundo ícone do tab Nariz. O slider à direita sobe a ponta e a base. À esquerda desce. A raiz entre os olhos fica. Um slider só. Sem Geral / L / R.

Data: 2026-09-30.  
Estado: no editor para aprovação visual. Sem B escrita. Sem C assinada. Sem E. Tamanho e os Fields vivos **não se mexem**. Root, Bridge e Tip ainda não existem.

Módulo: `lib/features/editor/beauty_engine/warp/v2/nose_lift/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

---

## 1. Papel

O nariz roda em volta da raiz: a ponta e as asas sobem ou descem. Os olhos, a boca, as sobrancelhas e a linha do cabelo ficam.

| Peça | Vigente |
|---|---|
| Key | `nose_lift` |
| Label | **Elevação** (tab Nariz) |
| Slider | Bipolar. Um só, o nariz inteiro |
| Convenção | **Esquerda = desce** (`t < 0`). **Direita = sobe** (`t > 0`) |
| Field | Só Δy |
| Ganho | `0.048 × faceWidth` na ponta |
| Params | `nose_lift` |

---

## 2. Equação

```
t ∈ [-1, 1]
identidade se |t| ≤ 1e-6

u = projecção de (p − nasion) em (ponta − nasion)
perfil = 0 se u ≤ 0.08
         1 se u ≥ 0.48
         smoothstep no vão

dy = −t · 0.045 · faceWidth · w · perfil
dx = 0
```

`nasion` é o landmark **168**. `ponta` é o **1**. O perfil vale 1 na ponta, nas asas (98/327) e na columela. Vale 0 na raiz.

```
w = planalto(hull do nariz) × BoundaryFeather × porta(olhos) × porta(boca) × porta(sobrancelha)
```

A porta é smoothstep da distância à máscara. Sem disco binário. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Tamanho, Head nem os outros Fields.

O runtime cacheia `w · perfil`. O slider só entra em `−t · amplitude`. `w` **não** depende de `t`.

---

## 3. Domínio

Hull de `V2RegionCatalog.nose`, dilatado `0.040 × faceWidth`. Olhos, boca e sobrancelha não são buraco no hull: o Field corta-os com a distância.

| Constante | Valor |
|---|---|
| Amplitude | `0.045 × faceWidth` |
| Hull pad | `0.090 × faceWidth` |
| Rampa de bordo | `0.105 × faceWidth` |
| Porta olhos / sobrancelha | `0.045 × faceWidth` |
| Porta boca | `0.100 × faceWidth` |
| Perfil | 0 até `u = 0.08`, 1 a partir de `u = 0.48` |
| 1, 98, 327 | **andam** em y |
| 168 | **fica** |
| 468 / 473 / 13 / 105 / 10 | **ficam** |

---

## 4. Pipeline e menu

```
… → nose_size → nose_lift → nose_ala → nose_bridge → jaw → …
```

Tab **Nariz**, ícone Elevação à direita de Tamanho. Preview e export partilham `applyFaceWarpChain`.
