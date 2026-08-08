# Sprint 7 — Swap Banuba e multi-rosto

## Objetivo

Substituir gradualmente o Banuba pelo editor facial nativo, com suporte a
**múltiplos rostos** na mesma foto e telemetria para comparar rollout vs
editor legado.

## Entregas

### Multi-rosto (cap. 16)

- MediaPipe `numFaces = 5` nos bridges Android/iOS
- `detectFaces` no plugin + `FaceMeshDetector.detectAll()`
- `MultiFaceDetection` — maior rosto primário + hit test
- **`FaceSelectionOverlay`** — toque para escolher qual rosto editar
- Hint na UI: *"N rostos detectados — toque no rosto que deseja editar"*

### Swap via feature flag

Chaves em `app_settings`:

| Chave | Default | Descrição |
|-------|---------|-----------|
| `face_editor_native_swap_enabled` | `disable` | Master switch do swap |
| `face_editor_native_rollout_percent` | `0` | Rollout 0–100 por bucket de usuário |

- **`FaceRetouchEntryPage`** — rota `/face-retouch` escolhe Banuba ou nativo
- **`faceEditorNativeSwapProvider`** — mesmo algoritmo de bucket do Beauty Engine
- Hub: quando swap ativo, um único card aponta para o editor nativo; beta lab some

Rollout gradual:

```sql
update app_settings set setting_value = 'enable'
  where setting_key = 'face_editor_native_swap_enabled';
update app_settings set setting_value = '25'
  where setting_key = 'face_editor_native_rollout_percent';
-- 50 → 100 conforme métricas
```

### Telemetria de sessão

Tabela `beauty_editor_session_events`:

- `editor_open` — abertura do editor nativo
- `preview_apply` — metadata: `face_count`, `apply_ms`
- `export_save` — export/salvar concluído

Consulta comparativa:

```sql
select event, count(*)
from beauty_editor_session_events
where created_at > now() - interval '7 days'
group by event;
```

## Arquivos principais

- `lib/features/editor/beauty_engine/models/multi_face_detection.dart`
- `lib/features/editor/beauty_engine/presentation/widgets/face_selection_overlay.dart`
- `lib/features/editor/beauty_engine/presentation/face_retouch_entry_page.dart`
- `lib/features/editor/beauty_engine/config/face_editor_rollout.dart`
- `lib/features/editor/beauty_engine/di/face_editor_rollout_provider.dart`
- `lib/features/editor/beauty_engine/diagnostics/beauty_editor_session_reporter.dart`
- `supabase/migrations/20260806183000_face_editor_swap_sprint7.sql`

## Testes

```bash
flutter test test/beauty_engine/models/multi_face_detection_test.dart
```

## Critério de saída

- [ ] Multi-rosto funcional em foto com 2+ pessoas
- [ ] Flag a 100% sem regressão de crashes/reclamações
- [ ] Métricas nativo vs Banuba comparáveis por 7 dias
- [ ] Remoção do Banuba do build (passo final pós-validação — não automatizado neste sprint)

## Próximo

Remover dependência Banuba (`pe_sdk_flutter`, pods, token) quando rollout estiver
estável; tuning A/B final vs fichas cap. 19.
