# Sprint 23 — Sign-off

**Data:** 2026-07-20  
**Escopo:** Sync Supabase de presets custom (last-write-wins)

## Entregas

- Migration `20260720200000_beauty_presets.sql` — tabela, RLS, bucket thumbnails, RPC install count, view marketplace
- `BeautyPresetRemoteDataSource` — CRUD + upload/download thumbnail
- `PresetSyncService` — merge last-write-wins por `updatedAt`
- `BeautyPresetRepositoryImpl` — push on save/delete, `syncWithRemote()`
- `PresetSyncBootstrap` — sync automático ao autenticar
- Campos sync em `BeautyPreset`: `remoteId`, `authorId`, `isPublic`, timestamps

## Critérios de aceite

- [x] Preset sync cross-device (pull/push por conta logada)
- [x] Conflict resolution: last-write-wins

## Próximo

Sprint 24 — Marketplace (entregue na mesma leva)
