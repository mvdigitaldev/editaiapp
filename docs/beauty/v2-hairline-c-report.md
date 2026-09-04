# Hairline Sprint C — aprovação visual

Data: 2026-09-03.  
Quem assina: Leonardo.  
Field vigente: radial + crista no cap (`docs/beauty/v2-hairline.md`). A B Δy-only **não** entra nesta C.

A Sprint C **não tem código**. É o veredicto humano.

## Pedido

Depois de A/B (radial) e D no aparelho, Leonardo: «implemente a sprint c».

Isto fecha C do Field vigente. Não reabre A. Não altera amplitude, crista nem cadeia.

## O que foi visto

- Lab `v2Raw` em `.cursor/facial-warp-v2/hairline/B/` (p01 / p05 / p12 × t=−50/−25/0/25/50).
- Preview no editor: key `hairline`, «Linha do cabelo», slider bipolar.

Convenção aceite: esquerda infla (dentro → fora); direita desincha (fora → dentro). Cara, olhos e têmporas fora do efeito.

## Veredicto

**Aprovado.** Hairline vivo no produto (`hairline`). A–E deste efeito estão fechadas: D e E já estavam no disco (painel + `applyFaceWarpChain` partilhado).

Não alterar o Field salvo calibração pedida por escrito.

## Isolamento

Zero mudanças em `lib/` nesta sprint. Jaw, Chin, V Chin, V Shape, Cheekbones H e Jaw Angle intactos.
