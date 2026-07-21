# Sprint 27 — Sign-off

**Data:** 2026-07-21  
**Escopo:** Release Beauty Engine em produção

## Entregas

- Feature flag `beauty_engine_enabled` + rollout `beauty_engine_rollout_percent` via `app_settings`
- `BeautyEngineRollout` — bucket estável FNV-1a 0–99 por user/anon id
- `beautyEngineEnabledProvider` — Riverpod (debug sempre on)
- `BeautyEngineGate` — bloqueia rotas fora do rollout
- Menu público: Home card **Retoque beauty** + Perfil **RETOQUE & PRESETS**
- Rotas production: `/beauty-editor`, `/beauty-preset-creator`, `/beauty-preset-marketplace`
- Dev-only: `/dev/face-filters` (kDebugMode)
- `BeautyEngineErrorReporter` + tabela `beauty_engine_error_logs`
- Migration `20260721120000_beauty_engine_release.sql` + `20260721130000_beauty_engine_release_pt.sql`
- `beauty_marketplace_publish_admin_only` — só admin publica quando `enable` (RLS + UI)
- `BeautyEngineLabels` — UI PT-BR nos menus beauty
- Preview fixo no Criador de Presets (compact 16:9, max 220px)
- Presets bundled renomeados em PT (Beleza, Casamento, Estúdio, etc.)
- Release notes: [sprint-27-release-notes.md](./sprint-27-release-notes.md)

## Rollout inicial

| Setting | Valor |
|---------|-------|
| `beauty_engine_enabled` | `enable` |
| `beauty_engine_rollout_percent` | `100` |
| `beauty_marketplace_publish_admin_only` | `enable` |

## Critérios de aceite

- [x] Feature flag + rollout gradual implementados
- [x] Menu público (Home + Perfil) condicionado ao flag
- [x] Release notes App Store / Play Store
- [x] Telemetria de erros (`beauty_engine_error_logs`)
- [x] Rollout 100% aplicado via Supabase MCP
- [x] Marketplace publish admin-only (RLS + Flutter)
- [x] UI PT-BR + preview fixo no creator
- [ ] Crash-free rate ≥ 99.5% por 7 dias (monitorar SQL/dashboard)

## Monitoramento (7 dias)

```sql
-- Erros por dia
SELECT date_trunc('day', created_at) AS day, count(*)
FROM beauty_engine_error_logs
GROUP BY 1 ORDER BY 1 DESC;

-- Contextos mais frequentes
SELECT context, count(*) FROM beauty_engine_error_logs
GROUP BY 1 ORDER BY 2 DESC;
```

## Próximo

Iteração pós-release: TPS/ARAP warp, multi-face.
