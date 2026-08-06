# Sprint 0 — Auditoria EXIF / orientação / resolução / ICC

Data: 2026-08-06. Escopo: caminho de entrada de fotos do Beauty Engine
(cap. 13 e 16 do plano do SDK facial).

## 1. EXIF / orientação — BUG CONFIRMADO E CORRIGIDO

**Problema encontrado**: `_pickImage` (beauty_editor_page, face_filters_demo,
preset_creator) montava o `ImageSource` com:

- dimensões vindas de `decodeImageFromList` (dart:ui/Skia) — que **aplica**
  a orientação EXIF;
- bytes originais encodados, que o pipeline decodifica depois com
  `img.decodeImage` (package:image) — que **não aplica** EXIF.

Consequência: em fotos de câmera com orientation ≠ 1 (praticamente toda foto
tirada em retrato), as dimensões vinham rotacionadas e os pixels não —
landmarks calculados sobre uma imagem, warp aplicado em outra → deformação
deslocada. O `ImageSource.rotation` sempre chegava 0 na UI (só era usado
pelos bridges nativos do MediaPipe).

**Correção**: `BeautyImageLoader` (`models/beauty_image_loader.dart`)
normaliza a foto 1× no load, em isolate (`compute`):

1. `img.bakeOrientation` aplica a orientação EXIF nos pixels;
2. teto de resolução de entrada (`AdaptivePreviewPolicy.inputMaxEdge = 4096`)
   — fotos de 50–200MP são reduzidas com interpolação cúbica antes de
   qualquer análise, eliminando OOM no load;
3. re-encode apenas quando algo mudou (JPEG q95; PNG preserva alpha).
   Foto já normalizada = bytes originais intactos, custo zero.

Coberto por `test/beauty_engine/models/beauty_image_loader_test.dart`
(orientação 6 → dims trocadas + pixels girados + tag limpa; teto 4096;
no-op idêntico; PNG preservado).

**Pendência consciente**: o decode/normalização é Dart puro (~1s para 12MP
com rotação). Aceitável 1× por foto no Sprint 0; a Fase 4 (FFI/nativo) pode
mover para nativo se o load virar gargalo percebido.

## 2. Teto de resolução — IMPLEMENTADO

Antes: nenhum limite no picker do beauty (fotos 100MP+ decodificadas
inteiras). Agora: `inputMaxEdge = 4096` (≈16MP máx) aplicado no
`BeautyImageLoader`. Preview continua com os caps existentes do
`AdaptivePreviewPolicy` (720/1080/1280); export tiled >8MP inalterado.

Nota: outros fluxos do app já tinham mitigação própria (`pickImage` com
maxWidth 2048 no admin; `resizeAndCompressForEdit` no upload de IA).

## 3. ICC / Display P3 — AUDITADO, AÇÃO NA FASE 1–2

Estado atual:

- `package:image` (pipeline CPU inteiro) **ignora ICC profile**: bytes P3 de
  fotos de iPhone são tratados como sRGB → leve dessaturação/shift de cor em
  fotos wide-gamut. Sem crash, sem artefato estrutural — erro colorimétrico
  sutil e consistente.
- `decodeImageFromList` (preview via `Image.memory`) faz color management
  pelo Skia/Impeller → o PREVIEW pode ficar levemente diferente do EXPORT
  em fotos P3 (preview correto, export dessaturado).
- Export (`img.encodeJpg`) **não embute profile** → leitores assumem sRGB,
  o que é coerente com o pipeline tratar tudo como sRGB (erro não se
  compõe: fica limitado à interpretação de entrada).

Decisão (cap. 13 do plano): tratar na escrita dos shaders GPU das Fases 1–2 —
conversão P3→sRGB (ou trabalho em linear com primárias corretas) no decode
nativo + profile sRGB embutido no export. Corrigir hoje no caminho CPU seria
retrabalho descartado na migração. Duas fotos P3 de iPhone devem entrar no
corpus golden para cravar o comportamento (ver
`test/golden/corpus/README.md`).

## 4. Infra criada neste sprint (referência rápida)

- `quality/image_quality_metrics.dart` — SSIM, PSNR, ΔE2000 (CIEDE2000)
- `test/golden/golden_test_utils.dart` — harness de golden + tolerâncias +
  corpus loader (`UPDATE_GOLDENS=1` para aprovar mudanças intencionais)
- `test/golden/beauty_baseline_golden_test.dart` — baseline do pipeline
  ATUAL (warp remap CPU, LUT) congelado antes da migração GPU
- `performance/beauty_benchmark_aggregator.dart` — p50/p95 por estágio,
  log JSON `beauty_benchmark {...}` a cada 20 frames no editor
- Rota `/face-retouch-lab` + card "Rosto — novo editor (beta)" no hub de
  retoque (flag remota `module_face_lab_enabled`) para comparação A/B com o
  Banuba usando a mesma foto
