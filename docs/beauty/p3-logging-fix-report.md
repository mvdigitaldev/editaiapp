# P3 — correção de logging/telemetria

Não houve promoção de `semanticReleasedFill` nem P4. O RGBA do pipeline A/P3 não mudou.

## Bug

`ExtendedRoiP0Dump.write` corria **antes** de `_logRender`. O `log.txt` gravava `ExtendedRoiDebug.lastLog` do **frame anterior**. Daí:

- frameAudit do p05 correto, `total_ms` com hashes/métricas do p01;
- frameAudit do p12 correto, `total_ms` com hashes/métricas do p05;
- o mesmo em `50_off`.

Além disso, `lastInputHash` / `lastOutputHash` / fill stats sobreviviam quando o frame seguinte não republicava hashes (auditoria off ou identidade).

## Correção (só telemetria)

1. `render` começa com `resetRenderTelemetry`, reset de `ContourBandFill` / Telea / `SemanticReleasedFill`, e `FrameAudit.beginFrame()` (frameId lógico deste processamento).
2. `capture` já **não** incrementa um segundo frameId; usa o id do `beginFrame`.
3. `_logRender` inclui `fixture`, `scenario`, `intensity`, `dir` e os hashes **deste** frame.
4. `log.txt` é escrito **depois** do `total_ms`, com as duas linhas do mesmo processamento.
5. Nomes de artefacto: `dir/stem_fixture/intensity.ext`  
   exemplo: `p01/jaw/50/newFaceContourOverlay_p01/50.png`  
   exemplo: `p01/jaw/50_off/newFaceContourOverlay_p01/50_off.png`

Não foram alterados morph, warp, fill, flags, limiares nem `amplitudeScale`.

## Testes

`extended_roi_p3_semantic_fill_test.dart`: flag off (hashes P0), alinhamento sequencial p01→p05→p12 on/off, dump matrix on. **Passed.**

Jaw 50% hashes (inalterados):

| | off | on |
|---|---|---|
| p01 | `5580e606c837f9e2` | `0754b4a37dbb6b95` |
| p05 | `2d26e8a3dc1d7807` | `6be67c7b271676fe` |
| p12 | `5a74ce412270b2df` | `5a74ce412270b2df` |

Logs corrigidos em `.cursor/extended-roi/p3/<fixture>/jaw/50/` e `50_off/`, ficheiro `log_<fixture>/<intensity>.txt`. Em cada um, `frameAudit` e `total_ms` partilham `frameId`, `fixture`, `intensity`, `inputHash`, `outputHash` e `dir`.

## Encerramento

A flag continua `false`. P4 não começou. Aguardar aprovação se quiseres avançar.
