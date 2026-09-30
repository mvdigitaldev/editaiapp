# Eye Puffy — olheiras

Efeito de cor. **Não** é warp. **Não** fecha o olho. **Não** é Distância (`eye_distance`).

Olheira, aqui, é a pele mais escura debaixo do olho. O slider clareia essa pele em direção ao tom da bochecha da própria pessoa. A pálpebra, a íris e os cílios ficam no lugar.

Data: 2026-09-29.  
Estado: no editor para aprovação visual. Sem B/C/E. Os Fields vivos **não se mexem**.

Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).  
Invariante: A3 em [`13-visual-quality-targets.md`](./13-visual-quality-targets.md).

---

## 1. Papel

| Peça | Vigente |
|---|---|
| Key | `eye_puffy` |
| Label | **Olheiras** (tab Olhos) |
| Slider | Unipolar, 0 → 1. Um só, os dois olhos |
| Efeito | Separação de frequências. A sombra (baixa) vai ao tom da pele vizinha, fora da máscara. O poro fica. a/b acompanham quando o vão é grande |
| Limite | Pele já nesse tom não se pinta. No máximo sobe 90% do vão |
| Fora | Interior do olho (íris, esclera, linha d'água), cílios, pálpebra de cima, resto da cara |

O tab Pele tem `remove_dark_circles`, com o mesmo rótulo e o mesmo passe. Os dois sliders usam o maior dos dois. Não se aplicam duas vezes.

---

## 2. Como

A máscara é o oval da pele debaixo da pestana (sulco), de canto a canto, com enviesamento para o nariz. O topo encosta na linha das pestanas. O interior do olho — íris, esclera, linha d'água — fica a zero. Não se multiplica pelo peso de pele.

A referência é a média local da pele logo à volta da máscara (anel), não uma bochecha distante nem a cara inteira. A sombra vive na baixa frequência; o poro na alta. Só sobe o que está mais escuro do que essa vizinhança. No máximo, 90% do vão.

Um slider. Os dois olhos recebem a mesma intensidade.

---

## 3. O que não entra

- Campo de deslocamento, pálpebra a subir, olho a fechar
- Clarear para um branco fixo
- Mexer nos Fields vivos
