-- Desabilitar agendamento antigo via pg_cron para cleanup_expired_edits
-- A limpeza automática passa a ser feita pela Edge Function cleanup-expired-edits.

SELECT cron.unschedule('cleanup-expired-edits');

