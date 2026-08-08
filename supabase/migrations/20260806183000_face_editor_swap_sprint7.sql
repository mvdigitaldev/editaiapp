-- Sprint 7: swap Banuba → editor nativo + telemetria de sessão.

insert into public.app_settings (setting_key, setting_value)
values
  ('face_editor_native_swap_enabled', 'disable'),
  ('face_editor_native_rollout_percent', '0'),
  ('module_face_lab_enabled', 'true')
on conflict (setting_key) do nothing;

create table if not exists public.beauty_editor_session_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete set null,
  event text not null,
  editor text not null default 'native',
  metadata jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_beauty_editor_session_events_created
  on public.beauty_editor_session_events (created_at desc);

alter table public.beauty_editor_session_events enable row level security;

drop policy if exists "beauty_editor_session_insert_own"
  on public.beauty_editor_session_events;
create policy "beauty_editor_session_insert_own"
  on public.beauty_editor_session_events
  for insert
  to authenticated
  with check (auth.uid() = user_id or user_id is null);

drop policy if exists "beauty_editor_session_insert_anon"
  on public.beauty_editor_session_events;
create policy "beauty_editor_session_insert_anon"
  on public.beauty_editor_session_events
  for insert
  to anon
  with check (user_id is null);

drop policy if exists "beauty_editor_session_no_select"
  on public.beauty_editor_session_events;
create policy "beauty_editor_session_no_select"
  on public.beauty_editor_session_events
  for select
  to authenticated, anon
  using (false);

comment on table public.beauty_editor_session_events is
  'Eventos de sessão do editor facial nativo (Sprint 7 rollout vs Banuba).';
