-- Ajusta o teto de fotos armazenadas por plano.
-- O limite só impede novos salvamentos (IA e manual); nada é apagado
-- automaticamente — o usuário libera espaço excluindo fotos na galeria.
-- Valores calibrados pelo uso real (p90/p99) para não bloquear a base atual.

update public.plans set max_stored_photos = 5  where name = 'Free';
update public.plans set max_stored_photos = 25 where name = 'Basic';
update public.plans set max_stored_photos = 40 where name = 'Especial';
update public.plans set max_stored_photos = 60 where name = 'PRO';
update public.plans set max_stored_photos = 100 where name = 'Anual';
