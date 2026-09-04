# Eyebrow Height Sprint C — aprovação visual

Data: 2026-09-04.  
Quem assina: Leonardo.  
Field vigente: `dy = −t_lado · 0.035 · faceWidth · w`, `dx = 0`, `w` = planalto × rampa × `lidGate` com dobra externa (`docs/beauty/v2-eyebrow-height.md`).

A Sprint C **não tem código**. É o veredicto humano dos `v2Raw` do lab B (refeitos após a calibração da dobra).

## Pedido

Depois da B e da calibração da pálpebra externa, Leonardo: «Pode seguir para a proxima sprint». Tinha `p01/100/v2Raw.png` aberto.

Isto fecha C do Field vigente. Não reabre A. Não altera amplitude, hull da brow nem o `lidGate`. **Não** liga slider nem cadeia (isso é D).

## O que foi visto

Lab `v2Raw` em `.cursor/facial-warp-v2/eyebrow_height/B/` (p01 / p05 / p12 × −100/−50/0/50/100/L100/R100).

Convenção aceite: esquerda baixa (`t < 0`, `dy > 0`); direita sobe (`t > 0`, `dy < 0`). Geral / L / R = lados da **foto**. Ilha em bloco. Olhos e landmark 10 parados. Dobra externa (vão cauda→canto) parada — é a zona que Leonardo marcou na B.

Ao subir, o vão brow–pálpebra **abre** porque a ilha anda e o olho não. Isso não é o puxão da dobra. Smear / ghost no `v2Raw` é esperado. Sem fill. `invalidCount = 0` nas 21.

Limitação aceite: os discos métricos em 21/251 (têmpora) sobrepõem o pad do hull. Landmark 10 e a linha L do Hairline não andam. Não se fura L no campo (Sprint A: invertia).

## Veredicto por foto / intensidade

| Foto | run | Veredicto | Nota |
|---|---|---|---|
| p01 | −100 | aceite | ilha baixa; olhos e dobra ficam; fundo parado |
| p01 | −50 | aceite | o mesmo, mais leve |
| p01 | 0 | aceite | identidade |
| p01 | 50 | aceite | ilha sobe; vão abre; dobra não vai com ela |
| p01 | 100 | aceite | o mesmo no extremo (cara que Leonardo marcou) |
| p01 | L100 | aceite | só foto esquerda (105); direita parada |
| p01 | R100 | aceite | só foto direita (334); esquerda parada |
| p05 | −100 | aceite | ilha baixa; olhos ficam |
| p05 | −50 | aceite | o mesmo, mais leve |
| p05 | 0 | aceite | identidade |
| p05 | 50 | aceite | ilha sobe |
| p05 | 100 | aceite | o mesmo no extremo |
| p05 | L100 | aceite | um lado só |
| p05 | R100 | aceite | um lado só |
| p12 | −100 | aceite | ilha baixa; olhos ficam |
| p12 | −50 | aceite | o mesmo, mais leve |
| p12 | 0 | aceite | identidade |
| p12 | 50 | aceite | ilha sobe |
| p12 | 100 | aceite | o mesmo no extremo |
| p12 | L100 | aceite | um lado só |
| p12 | R100 | aceite | um lado só |

**Aprovado.** Field intacto. Sem UI. Sem cadeia.

Não alterar o Field salvo calibração pedida por escrito. D feita 2026-09-04 ([`v2-eyebrow-height-d-report.md`](./v2-eyebrow-height-d-report.md)).

## Isolamento

Zero mudanças em `lib/` nesta sprint. Jaw, Chin, V Chin, V Shape, Cheekbones H, Jaw Angle, Hairline e Head intactos.
