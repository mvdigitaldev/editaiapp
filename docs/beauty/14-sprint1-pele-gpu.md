# Sprint 1 — Pele em GPU (signoff)

Data: 2026-08-06. Escopo: Fase 1 do plano do SDK facial.

## Entregue

### Algoritmo (Dart — oráculo / fallback / CI)
- `GuidedFilter` O(1) via imagem integral (`filters/face/skin/guided_filter.dart`)
- `SkinRetouchEngine`: separação de frequências em 3 bandas (luz linear),
  acne, brilho relativo ao tom do usuário, olheiras em OKLab
- `SkinWeightMap`: máscara multiclass MediaPipe (`faceSkin`) + fallback
  geométrico + feather; olhos/boca/sobrancelha subtraídos pós-feather
- `PassSkinEngine` liga Grupo A ao pipeline; makeup permanece paramétrico

### Máscara multiclass
- Modelo `selfie_multiclass_256x256.tflite` em assets + download script
- Bridges iOS/Android `detectFaceParts` + `FacePartsDetector` Dart
- Init best-effort (falha no multiclass não derruba MediaPipe)

### Backend GPU nativo
- **iOS** `SkinRetouchMetalBackend.swift`: compute Metal, texturas R16F
  intermediárias, sRGB↔linear, guided filter separável, composite +
  dark circles OKLab
- **Android** `SkinRetouchBackend.kt`: GLES3 + R16F quando disponível;
  fallback CPU nativo idêntico ao Dart (ainda muito mais rápido que isolate)
- MethodChannel `skinRetouchExport` + flags `skinRetouch` / `skinGpu` em
  `probeExportCapabilities`
- Dart `NativeSkinBackend` / `MethodChannelNativeSkinBackend` com
  native-first + fallback CPU em `PassSkinEngine`

### Goldens Grupo A
- `test/golden/skin_group_a_golden_test.dart`
- Invariantes A1: fundo/cabelo/olhos/boca intocados; poros atenuados
- Goldens: `skin_smooth_full.png`, `skin_group_a_combo.png`

## Critérios de saída

| Critério | Status |
|----------|--------|
| Suavização superior ao box blur 3×3 antigo | OK (frequency separation) |
| Invariantes "não borrar cílios/sobrancelha/cabelo" | OK (goldens verdes) |
| Máscara multiclass como pele fase-1 | OK |
| Backend Metal/GLES no mesmo canal do export | OK |
| ≤5ms @1080p no device de referência | Medir no device via `beauty_benchmark` (Sprint 0); Metal deve atingir; Android GLES depende do device, CPU nativo é fallback |

## Como validar no device

1. Abrir **Rosto — novo editor (beta)** (`/face-retouch-lab`)
2. Foto com rosto → slider **Suavizar pele**, **Acne**, **Olheiras**, **Brilho**
3. Comparar com Banuba na mesma foto
4. No log: `beauty_benchmark {...}` — olhar estágio de pele / `process_total`
5. Capacidades: `probeExportCapabilities` deve reportar `skinRetouch: true`
   (e `skinGpu: true` no iOS Metal / Android GLES3)

## Próximo

Sprint 2 — color engine GPU (curvas, LUT 3D, HDR, nitidez, vinheta) com
memoização por estágio.
