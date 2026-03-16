-- Habilita Realtime nas tabelas edits e flux_tasks.
-- Sem isso, o cliente inscreve-se mas nunca recebe updates.
-- Ver: https://supabase.com/docs/guides/realtime/postgres-changes
ALTER PUBLICATION supabase_realtime ADD TABLE edits;
ALTER PUBLICATION supabase_realtime ADD TABLE flux_tasks;
