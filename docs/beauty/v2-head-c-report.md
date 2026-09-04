# Head Sprint C — aprovação visual

Data: 2026-09-04.  
Quem assina: Leonardo.  
Field vigente: `D = w · (q − c) · (1 − 1/s) · min(1, R₊ / |q − c|)`, `k = 0.12` (`docs/beauty/v2-head.md`).

A Sprint C **não tem código**. É o veredicto humano dos `v2Raw` do lab B.

## Pedido

Depois da B, Leonardo: «implemente proxima sprint».

Isto fecha C do Field vigente. Não reabre A. Não altera `k`, o hull nem o renderer. **Não** liga slider nem cadeia (isso é D).

## O que foi visto

Lab `v2Raw` em `.cursor/facial-warp-v2/head/B/` (p01 / p05 / p12 × t=−50/−25/0/25/50).

Convenção aceite: esquerda cresce (`t < 0`); direita encolhe (`t > 0`). Cabeça inteira (cabelo + cara + queixo). Fundo longe parado. Não é zoom de câmara.

Limitação aceite: ao encolher, p01 e p05 pedem origem acima do crop — `invalidSource` no cap, **sem fill**. p12 tem margem e não fura o rect.

## Veredicto por foto / intensidade

| Foto | t | Veredicto | Nota |
|---|---|---|---|
| p01 | −50 | aceite | cabeça cresce no sítio; fundo parado |
| p01 | −25 | aceite | o mesmo, mais leve |
| p01 | 0 | aceite | identidade |
| p01 | 25 | aceite | encolhe; banda no cap = `invalidSource` do crop, sem fill |
| p01 | 50 | aceite | o mesmo, banda maior no cap |
| p05 | −50 | aceite | silhueta completa contra o cinzento; cresce |
| p05 | −25 | aceite | o mesmo, mais leve |
| p05 | 0 | aceite | identidade |
| p05 | 25 | aceite | encolhe; `invalidSource` no cap, sem fill |
| p05 | 50 | aceite | o mesmo |
| p12 | −50 | aceite | cresce; cap com margem |
| p12 | −25 | aceite | o mesmo, mais leve |
| p12 | 0 | aceite | identidade |
| p12 | 25 | aceite | encolhe sem furar o rect |
| p12 | 50 | aceite | o mesmo |

**Aprovado.** Field intacto. Sem UI. Sem cadeia.

Não alterar o Field salvo calibração pedida por escrito. D só depois desta C (tab Proporção, key `head`).

## Isolamento

Zero mudanças em `lib/` nesta sprint. Jaw, Chin, V Chin, V Shape, Cheekbones H, Jaw Angle e Hairline intactos.
