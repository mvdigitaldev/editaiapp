# Eyebrow End Sprint C — aprovação visual

Data: 2026-09-04.  
Quem assina: Leonardo.  
Field vigente: `dx = t_lado · 0.010 · faceWidth · w · band · s_inner · away`, `dy = 0` (`docs/beauty/v2-eyebrow-end.md`).

A Sprint C **não tem código**. É o veredicto humano dos `v2Raw` do lab B.

## Pedido

Depois da B, Leonardo: «implemente a proxima».

Isto fecha C do Field vigente. Não reabre A. Não altera amplitude, `s_inner` nem o `lidGate`. A UI (ícone Ponta, cadeia) é D.

## O que foi visto

Lab `v2Raw` em `.cursor/facial-warp-v2/eyebrow_end/B/` (p01 / p05 / p12 × −100/−50/0/50/100/L100/R100).

Convenção aceite: esquerda junta (`t < 0`); direita separa (`t > 0`). Geral / L / R = lados da **foto**. Só as pontas internas (336/107). Cauda, arco, olhos, dobra externa e landmark 10 parados. Amplitude leve (~2,3 px nas pontas em p01) — é o tecto de produto, não um Field morto.

Smear / ghost no `v2Raw` é esperado. Sem fill. `invalidCount = 0` nas 21. `hairline.p95Abs = 0` (o terço interno não chega aos discos 21/251).

## Veredicto por foto / intensidade

| Foto | run | Veredicto | Nota |
|---|---|---|---|
| p01 | −100 | aceite | junta; olhos e cauda ficam; fundo parado |
| p01 | −50 | aceite | o mesmo, mais leve |
| p01 | 0 | aceite | identidade |
| p01 | 50 | aceite | leve separação |
| p01 | 100 | aceite | o mesmo no extremo (~2,3 px nas pontas) |
| p01 | L100 | aceite | só foto esquerda (107); direita parada |
| p01 | R100 | aceite | só foto direita (336); esquerda parada |
| p05 | −100 | aceite | junta; olhos ficam |
| p05 | −50 | aceite | o mesmo, mais leve |
| p05 | 0 | aceite | identidade |
| p05 | 50 | aceite | leve separação |
| p05 | 100 | aceite | o mesmo no extremo |
| p05 | L100 | aceite | um lado só |
| p05 | R100 | aceite | um lado só |
| p12 | −100 | aceite | junta; olhos ficam |
| p12 | −50 | aceite | o mesmo, mais leve |
| p12 | 0 | aceite | identidade |
| p12 | 50 | aceite | leve separação |
| p12 | 100 | aceite | o mesmo no extremo |
| p12 | L100 | aceite | um lado só |
| p12 | R100 | aceite | um lado só |

**Aprovado.** Field intacto. Sem UI. Sem cadeia.

Não alterar o Field salvo calibração pedida por escrito. D feita 2026-09-04 ([`v2-eyebrow-end-d-report.md`](./v2-eyebrow-end-d-report.md)).

## Isolamento

Zero mudanças em `lib/` nesta sprint. Altura, Largura e os Fields vivos intactos.
