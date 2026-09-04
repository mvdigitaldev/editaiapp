# Eyebrow Width Sprint C — aprovação visual

Data: 2026-09-04.  
Quem assina: Leonardo.  
Field vigente: `dy = t_lado · 0.008 · faceWidth · w · s`, `s = tanh((y − y_eixo) / halfBand)`, `dx = 0` (`docs/beauty/v2-eyebrow-width.md`).

A Sprint C **não tem código**. É o veredicto humano dos `v2Raw` do lab B.

## Pedido

Depois da B, Leonardo: «implemente a proxima», com `p01/0/original.png` do lab Width aberto.

Isto fecha C do Field vigente. Não reabre A. Não altera amplitude nem o `lidGate`. A UI (ícone Largura, cadeia) é D.

## O que foi visto

Lab `v2Raw` em `.cursor/facial-warp-v2/eyebrow_width/B/` (p01 / p05 / p12 × −100/−50/0/50/100/L100/R100).

Convenção aceite: esquerda afina (`t < 0`); direita engrossa (`t > 0`). Geral / L / R = lados da **foto**. Arco sobe e base desce ao engrossar. Olhos, dobra externa e landmark 10 parados. Amplitude leve (~2 px no arco em p01) — é o tecto de produto, não um Field morto.

Smear / ghost no `v2Raw` é esperado. Sem fill. `invalidCount = 0` nas 21.

Limitação aceite: os discos métricos em 21/251 (têmpora) sobrepõem o pad do hull. Mesma sobreposição da Altura. Não se fura L no campo.

## Veredicto por foto / intensidade

| Foto | run | Veredicto | Nota |
|---|---|---|---|
| p01 | −100 | aceite | afina; olhos e dobra ficam; fundo parado |
| p01 | −50 | aceite | o mesmo, mais leve |
| p01 | 0 | aceite | identidade (cara que Leonardo tinha aberta) |
| p01 | 50 | aceite | leve engrossada |
| p01 | 100 | aceite | o mesmo no extremo (~2 px no arco) |
| p01 | L100 | aceite | só foto esquerda (105/52); direita parada |
| p01 | R100 | aceite | só foto direita (334/282); esquerda parada |
| p05 | −100 | aceite | afina; olhos ficam |
| p05 | −50 | aceite | o mesmo, mais leve |
| p05 | 0 | aceite | identidade |
| p05 | 50 | aceite | leve engrossada |
| p05 | 100 | aceite | o mesmo no extremo |
| p05 | L100 | aceite | um lado só |
| p05 | R100 | aceite | um lado só |
| p12 | −100 | aceite | afina; olhos ficam |
| p12 | −50 | aceite | o mesmo, mais leve |
| p12 | 0 | aceite | identidade |
| p12 | 50 | aceite | leve engrossada |
| p12 | 100 | aceite | o mesmo no extremo |
| p12 | L100 | aceite | um lado só |
| p12 | R100 | aceite | um lado só |

**Aprovado.** Field intacto.

Não alterar o Field salvo calibração pedida por escrito.

## Isolamento

Zero mudanças em `lib/` nesta sprint. Altura e os Fields vivos intactos.
