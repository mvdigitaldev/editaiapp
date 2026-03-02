-- =============================================================================
-- Policy para permitir usuário deletar seus próprios edits
-- =============================================================================

CREATE POLICY "edits_delete_own" ON edits FOR DELETE USING (auth.uid() = user_id);
