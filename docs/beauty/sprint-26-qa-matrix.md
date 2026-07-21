# Sprint 26 — Matriz de QA (iOS + Android)

**Objetivo:** Validar face + body + presets + sync em dispositivos móveis reais.  
**Plataformas:** iOS + Android apenas (sem Web/Desktop).

## Como usar

1. Rode a suite automatizada antes do teste manual:
   ```bash
   flutter test test/beauty_engine/regression/
   flutter test test/beauty_engine/
   ```
2. Para cada dispositivo abaixo, marque ✅ / ❌ / N/A.
3. Registre bugs P0/P1 em [sprint-26-signoff.md](./sprint-26-signoff.md).

---

## Matriz de dispositivos (20+)

| # | Plataforma | Dispositivo | SoC / API | Resolução câmera | Tester | Status |
|---|------------|-------------|-----------|------------------|--------|--------|
| 1 | Android | Pixel 8 | Tensor G3 / API 34 | 50MP | | ☐ |
| 2 | Android | Pixel 7a | Tensor G2 / API 34 | 64MP | | ☐ |
| 3 | Android | Samsung Galaxy S24 | Exynos 2400 / API 34 | 50MP | | ☐ |
| 4 | Android | Samsung Galaxy A54 | Exynos 1380 / API 33 | 50MP | | ☐ |
| 5 | Android | Xiaomi Redmi Note 13 | Helio G99 / API 33 | 108MP | | ☐ |
| 6 | Android | Motorola Edge 40 | Dimensity 8020 / API 33 | 50MP | | ☐ |
| 7 | Android | OnePlus 12 | SD 8 Gen 3 / API 34 | 50MP | | ☐ |
| 8 | Android | Samsung Galaxy Tab S9 | SD 8 Gen 2 / API 34 | 13MP | | ☐ |
| 9 | Android | Emulador ARM64 (AVD) | API 34 | — | | ☐ |
| 10 | Android | Emulador ARM64 (AVD) | API 30 | — | | ☐ |
| 11 | iOS | iPhone 15 Pro | A17 Pro / iOS 17 | 48MP | | ☐ |
| 12 | iOS | iPhone 14 | A15 / iOS 17 | 12MP | | ☐ |
| 13 | iOS | iPhone SE (3ª gen) | A15 / iOS 16 | 12MP | | ☐ |
| 14 | iOS | iPhone 13 mini | A15 / iOS 17 | 12MP | | ☐ |
| 15 | iOS | iPad Air (M1) | M1 / iPadOS 17 | 12MP | | ☐ |
| 16 | iOS | Simulador iPhone 15 | iOS 17 | — | | ☐ |
| 17 | iOS | Simulador iPhone SE | iOS 16 | — | | ☐ |
| 18 | Android | Dispositivo entry (2GB RAM) | API 28–30 | 12MP | | ☐ |
| 19 | Android | Dispositivo entry (3GB RAM) | API 31–32 | 48MP | | ☐ |
| 20 | iOS | iPhone 12 | A14 / iOS 16 | 12MP | | ☐ |
| 21 | Android | Realme / Poco (G-series) | MediaTek / API 31 | 64MP | | ☐ |
| 22 | iOS | iPhone 11 | A13 / iOS 15 | 12MP | | ☐ |

---

## Checklist funcional (por dispositivo)

### Beauty Editor
- [ ] Selecionar foto da galeria
- [ ] Aplicar preset Natural (< 500ms preview 1080p)
- [ ] Aplicar preset Cinema (LUT carrega)
- [ ] Toggle original / editada
- [ ] Foto 12MP+ exporta sem OOM (tiled export)

### Filtros (dev `/dev/face-filters`)
- [ ] Face slim 0 → 1 visível
- [ ] Nose + eyes combinados
- [ ] Body waist + leg (foto corpo inteiro)
- [ ] Skin smooth + blush
- [ ] Sliders anunciam valor (TalkBack / VoiceOver)

### Presets
- [ ] Criar preset custom (Preset Creator)
- [ ] Sliders acessíveis no creator
- [ ] Export/import JSON
- [ ] Sync login → pull presets remotos
- [ ] Marketplace → instalar preset público

### Manual Editor (regressão cruzada)
- [ ] Home → Editar manualmente
- [ ] Filtros LUT + crop
- [ ] Salvar → comparação galeria

### Performance
- [ ] Preview selfie ≤ 720p long edge
- [ ] Preview foto 4MP ≤ 1080p long edge
- [ ] Sem crash ao alternar presets rapidamente
- [ ] Shader prewarm não bloqueia UI

### Acessibilidade
- [ ] Sliders com rótulo + valor percentual visível
- [ ] TalkBack/VoiceOver lê nome do slider e valor
- [ ] Área de toque slider ≥ 48dp (overlay 24px radius)

---

## Severidade de bugs

| Nível | Definição | Meta Sprint 26 |
|-------|-----------|----------------|
| **P0** | Crash, perda de dados, impossível usar feature | **0** |
| **P1** | Degradação grave (warp errado, sync falha silenciosa) | **≤ 3 documentados** |
| P2 | Visual menor, workaround existe | Backlog |

---

## Suite automatizada (CI)

| Suite | Comando | Cobertura |
|-------|---------|-----------|
| Regressão Sprint 26 | `flutter test test/beauty_engine/regression/` | Face + body + skin + presets + sync + perf |
| Beauty Engine completo | `flutter test test/beauty_engine/` | Unit + integration |
| Manual Editor | `flutter test test/manual_editor/` | Export pipeline |
| Acessibilidade sliders | `flutter test test/beauty_engine/presentation/beauty_accessible_slider_test.dart` | Semântica |
