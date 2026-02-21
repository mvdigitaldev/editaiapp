-- =============================================================================
-- EDITAI - Modelagem completa do banco de dados (PostgreSQL / Supabase)
-- SaaS mobile: edição de imagens com IA, planos, créditos, afiliados
-- =============================================================================
-- Regras: UUID PK, created_at/updated_at, soft delete onde aplicável,
-- créditos auditáveis via credit_transactions, constraint saldo não negativo.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. ENUMS
-- -----------------------------------------------------------------------------

CREATE TYPE user_role AS ENUM ('user', 'admin');

CREATE TYPE subscription_status_enum AS ENUM (
  'active',
  'canceled',
  'expired',
  'trialing',
  'trial'
);

CREATE TYPE payment_status_enum AS ENUM (
  'paid',
  'pending',
  'failed',
  'refunded'
);

CREATE TYPE credit_transaction_type AS ENUM (
  'subscription_credit',  -- créditos vindos da assinatura
  'extra_purchase',      -- compra avulsa de créditos
  'usage',               -- consumo em uma edição (valor negativo)
  'bonus',                -- bônus promocional
  'referral_bonus'        -- bônus de indicação
);

CREATE TYPE image_status_enum AS ENUM (
  'uploaded',
  'processing',
  'completed',
  'failed'
);

CREATE TYPE edit_category_enum AS ENUM (
  'food',
  'person',
  'landscape',
  'product',
  'other'
);

CREATE TYPE edit_goal_enum AS ENUM (
  'improve_colors',
  'change_background',
  'remove_objects',
  'enhance_details',
  'adjust_lighting'
);

CREATE TYPE desired_style_enum AS ENUM (
  'natural',
  'professional',
  'artistic',
  'realistic'
);

CREATE TYPE edit_status_enum AS ENUM (
  'queued',
  'processing',
  'completed',
  'failed'
);

CREATE TYPE referral_reward_status_enum AS ENUM (
  'pending',
  'paid'
);

-- -----------------------------------------------------------------------------
-- 2. FUNÇÃO AUXILIAR: updated_at
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION set_updated_at() IS 'Trigger genérico para atualizar updated_at em qualquer tabela.';

-- -----------------------------------------------------------------------------
-- 3. TABELAS (ordem de dependência)
-- -----------------------------------------------------------------------------

-- Plans não depende de users; users referencia plans.
CREATE TABLE plans (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name              text NOT NULL UNIQUE,
  description       text,
  monthly_price      numeric(10, 2) NOT NULL DEFAULT 0,
  yearly_price       numeric(10, 2) NOT NULL DEFAULT 0,
  monthly_credits    int NOT NULL DEFAULT 0 CHECK (monthly_credits >= 0),
  features           jsonb NOT NULL DEFAULT '[]',
  is_active          boolean NOT NULL DEFAULT true,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE plans IS 'Planos disponíveis (Free, Basic, Premium). Preços e créditos mensais.';

-- Users: em Supabase, id referencia auth.users(id). Senha fica em auth.users.
CREATE TABLE users (
  id                   uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name                 text,
  email                text NOT NULL,
  phone                text,
  avatar_url           text,
  role                 user_role NOT NULL DEFAULT 'user',
  referral_code         text NOT NULL UNIQUE,
  referred_by          uuid REFERENCES users(id) ON DELETE SET NULL,
  current_plan_id       uuid REFERENCES plans(id) ON DELETE SET NULL,
  credits_balance      int NOT NULL DEFAULT 0 CHECK (credits_balance >= 0),
  subscription_status  subscription_status_enum NOT NULL DEFAULT 'trial',
  trial_ends_at        timestamptz,
  last_login_at        timestamptz,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE users IS 'Perfil e dados de negócio do usuário. Auth em auth.users (Supabase). credits_balance é cache; fonte da verdade é credit_transactions.';
COMMENT ON COLUMN users.referral_code IS 'Código único para link de indicação.';
COMMENT ON COLUMN users.credits_balance IS 'Saldo em cache; atualizado por trigger a partir de credit_transactions. Nunca negativo (CHECK).';

CREATE TRIGGER plans_updated_at
  BEFORE UPDATE ON plans
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Subscriptions: histórico e assinatura ativa por usuário
CREATE TABLE subscriptions (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                 uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plan_id                  uuid NOT NULL REFERENCES plans(id) ON DELETE RESTRICT,
  status                  subscription_status_enum NOT NULL,
  started_at              timestamptz NOT NULL DEFAULT now(),
  ends_at                 timestamptz,
  canceled_at             timestamptz,
  external_subscription_id text,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE subscriptions IS 'Assinaturas ativas e histórico. external_subscription_id: Stripe ou outro gateway.';
COMMENT ON COLUMN subscriptions.external_subscription_id IS 'ID da assinatura no provedor (ex: Stripe subscription_xxx).';

CREATE TRIGGER subscriptions_updated_at
  BEFORE UPDATE ON subscriptions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Payments: histórico financeiro auditável
CREATE TABLE payments (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  subscription_id       uuid REFERENCES subscriptions(id) ON DELETE SET NULL,
  amount                numeric(12, 2) NOT NULL CHECK (amount >= 0),
  currency              char(3) NOT NULL DEFAULT 'BRL',
  payment_method        text NOT NULL,
  payment_status        payment_status_enum NOT NULL,
  payment_provider      text NOT NULL,
  external_payment_id    text,
  invoice_url            text,
  paid_at               timestamptz,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE payments IS 'Histórico de pagamentos. subscription_id NULL para compra avulsa de créditos.';

CREATE TRIGGER payments_updated_at
  BEFORE UPDATE ON payments
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Credit transactions: fonte da verdade para saldo (auditável)
CREATE TABLE credit_transactions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type        credit_transaction_type NOT NULL,
  amount      int NOT NULL,
  description text,
  reference_id uuid,
  created_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE credit_transactions IS 'Movimentação de créditos. Saldo real = SUM(amount) por user_id. amount negativo = uso.';
COMMENT ON COLUMN credit_transactions.reference_id IS 'ID da edição, pagamento ou entidade relacionada.';

-- Trigger: ao inserir em credit_transactions, atualizar users.credits_balance.
-- O CHECK (credits_balance >= 0) em users impede saldo negativo (rollback da transação).
CREATE OR REPLACE FUNCTION sync_credits_balance()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE users
  SET credits_balance = credits_balance + NEW.amount,
      updated_at = now()
  WHERE id = NEW.user_id;
  RETURN NEW;
END;
$$;

CREATE TRIGGER credit_transactions_sync_balance
  AFTER INSERT ON credit_transactions
  FOR EACH ROW EXECUTE FUNCTION sync_credits_balance();

-- Images: upload e resultado da IA (soft delete)
CREATE TABLE images (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  original_image_url   text NOT NULL,
  generated_image_url  text,
  thumbnail_url        text,
  file_size            bigint,
  mime_type            text,
  width                int,
  height               int,
  status               image_status_enum NOT NULL DEFAULT 'uploaded',
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  deleted_at           timestamptz
);

COMMENT ON TABLE images IS 'Imagens enviadas e geradas. deleted_at para soft delete.';

CREATE TRIGGER images_updated_at
  BEFORE UPDATE ON images
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Edits: uma edição por imagem (prompt, categoria, status, créditos usados)
CREATE TABLE edits (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  image_id            uuid NOT NULL REFERENCES images(id) ON DELETE CASCADE,
  prompt_text         text NOT NULL,
  edit_category       edit_category_enum NOT NULL,
  edit_goal           edit_goal_enum NOT NULL,
  desired_style       desired_style_enum NOT NULL,
  status              edit_status_enum NOT NULL DEFAULT 'queued',
  ai_processing_time_ms int,
  credits_used        int NOT NULL DEFAULT 0 CHECK (credits_used >= 0),
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE edits IS 'Uma edição de IA por imagem. credits_used deve gerar uma linha em credit_transactions (type=usage, amount negativo).';

CREATE TRIGGER edits_updated_at
  BEFORE UPDATE ON edits
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Edit logs: auditoria do fluxo da edição (opcional)
CREATE TABLE edit_logs (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  edit_id    uuid NOT NULL REFERENCES edits(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  metadata   jsonb DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE edit_logs IS 'Log de eventos por edição (queued, started, completed, failed) para auditoria.';

-- Referrals: afiliados (quem indicou, quem foi indicado, recompensa)
CREATE TABLE referrals (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_user_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  referred_user_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reward_credits    int NOT NULL DEFAULT 0 CHECK (reward_credits >= 0),
  reward_status    referral_reward_status_enum NOT NULL DEFAULT 'pending',
  created_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (referred_user_id)
);

COMMENT ON TABLE referrals IS 'Uma linha por usuário indicado. referred_user_id único (cada pessoa só pode ser indicada uma vez).';

-- User sessions (opcional; Supabase já gerencia auth.sessions)
CREATE TABLE user_sessions (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token      text NOT NULL,
  ip_address inet,
  user_agent text,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE user_sessions IS 'Sessões app-specific (opcional). Supabase gerencia auth.sessions para JWT.';

-- App settings: chave-valor global
CREATE TABLE app_settings (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key        text NOT NULL UNIQUE,
  value      jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER app_settings_updated_at
  BEFORE UPDATE ON app_settings
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -----------------------------------------------------------------------------
-- 4. TRIGGER: criar usuário em public.users ao inserir em auth.users (Supabase)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  free_plan_id uuid;
  new_referral_code text;
BEGIN
  -- Gerar código de indicação único (ex: primeiros 8 chars do uuid + random)
  new_referral_code := 'ref_' || substr(replace(NEW.id::text, '-', ''), 1, 10);
  -- Garantir unicidade (evitar colisão)
  WHILE EXISTS (SELECT 1 FROM users WHERE referral_code = new_referral_code) LOOP
    new_referral_code := 'ref_' || substr(md5(random()::text), 1, 10);
  END LOOP;

  SELECT id INTO free_plan_id FROM plans WHERE name ILIKE 'free' LIMIT 1;
  IF free_plan_id IS NULL THEN
    INSERT INTO plans (name, description, monthly_price, yearly_price, monthly_credits, features)
    VALUES ('Free', 'Plano gratuito com créditos limitados', 0, 0, 5, '[]')
    RETURNING id INTO free_plan_id;
  END IF;

  INSERT INTO public.users (id, email, name, role, referral_code, current_plan_id, subscription_status, trial_ends_at)
  VALUES (
    NEW.id,
    COALESCE(NEW.email, ''),
    COALESCE(NEW.raw_user_meta_data->>'name', NEW.raw_user_meta_data->>'full_name'),
    'user',
    new_referral_code,
    free_plan_id,
    'trial',
    now() + interval '7 days'
  )
  ON CONFLICT (id) DO UPDATE SET
    email = COALESCE(EXCLUDED.email, users.email),
    name = COALESCE(EXCLUDED.name, users.name),
    updated_at = now();

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'handle_new_user error: %', SQLERRM;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_new_user() IS 'Cria registro em public.users quando um usuário se cadastra via Supabase Auth.';

-- Só criar o trigger se existir auth.users (Supabase)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'auth' AND table_name = 'users') THEN
    DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
    CREATE TRIGGER on_auth_user_created
      AFTER INSERT ON auth.users
      FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
  END IF;
END
$$;

-- -----------------------------------------------------------------------------
-- 5. ÍNDICES (performance)
-- -----------------------------------------------------------------------------

CREATE UNIQUE INDEX idx_users_email ON users(email);
CREATE UNIQUE INDEX idx_users_referral_code ON users(referral_code);
CREATE INDEX idx_users_referred_by ON users(referred_by);
CREATE INDEX idx_users_current_plan_id ON users(current_plan_id);
CREATE INDEX idx_users_subscription_status ON users(subscription_status);

CREATE INDEX idx_subscriptions_user_id ON subscriptions(user_id);
CREATE INDEX idx_subscriptions_status ON subscriptions(status);
CREATE INDEX idx_subscriptions_ends_at ON subscriptions(ends_at);

CREATE INDEX idx_payments_user_id ON payments(user_id);
CREATE INDEX idx_payments_subscription_id ON payments(subscription_id);
CREATE INDEX idx_payments_payment_status ON payments(payment_status);
CREATE INDEX idx_payments_created_at ON payments(created_at);
CREATE INDEX idx_payments_external_payment_id ON payments(external_payment_id);

CREATE INDEX idx_credit_transactions_user_id ON credit_transactions(user_id);
CREATE INDEX idx_credit_transactions_created_at ON credit_transactions(created_at);
CREATE INDEX idx_credit_transactions_type ON credit_transactions(type);

CREATE INDEX idx_images_user_id ON images(user_id);
CREATE INDEX idx_images_status ON images(status);
CREATE INDEX idx_images_deleted_at ON images(deleted_at) WHERE deleted_at IS NULL;

CREATE INDEX idx_edits_user_id ON edits(user_id);
CREATE INDEX idx_edits_image_id ON edits(image_id);
CREATE INDEX idx_edits_status ON edits(status);
CREATE INDEX idx_edits_created_at ON edits(created_at);

CREATE INDEX idx_edit_logs_edit_id ON edit_logs(edit_id);
CREATE INDEX idx_edit_logs_created_at ON edit_logs(created_at);

CREATE INDEX idx_referrals_referrer ON referrals(referrer_user_id);
CREATE INDEX idx_referrals_referred ON referrals(referred_user_id);

CREATE INDEX idx_user_sessions_user_id ON user_sessions(user_id);
CREATE INDEX idx_user_sessions_expires_at ON user_sessions(expires_at);

CREATE UNIQUE INDEX idx_app_settings_key ON app_settings(key);

-- -----------------------------------------------------------------------------
-- 6. RLS (Row Level Security) - Supabase
-- -----------------------------------------------------------------------------

ALTER TABLE plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE credit_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE images ENABLE ROW LEVEL SECURITY;
ALTER TABLE edits ENABLE ROW LEVEL SECURITY;
ALTER TABLE edit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;

-- Plans: leitura pública (para exibir na loja)
CREATE POLICY "plans_select_all" ON plans FOR SELECT USING (true);

-- Users: cada um vê e atualiza só o próprio perfil; admin vê todos (via service role ou função)
CREATE POLICY "users_select_own" ON users FOR SELECT USING (auth.uid() = id);
CREATE POLICY "users_update_own" ON users FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "users_insert_own" ON users FOR INSERT WITH CHECK (auth.uid() = id);

-- Subscriptions: usuário vê apenas as próprias
CREATE POLICY "subscriptions_select_own" ON subscriptions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "subscriptions_insert_own" ON subscriptions FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Payments: usuário vê apenas os próprios
CREATE POLICY "payments_select_own" ON payments FOR SELECT USING (auth.uid() = user_id);

-- Credit transactions: usuário vê apenas as próprias; insert via service role ou função (para não burlar saldo)
CREATE POLICY "credit_transactions_select_own" ON credit_transactions FOR SELECT USING (auth.uid() = user_id);

-- Images: CRUD apenas do próprio usuário
CREATE POLICY "images_select_own" ON images FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "images_insert_own" ON images FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "images_update_own" ON images FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "images_delete_own" ON images FOR DELETE USING (auth.uid() = user_id);

-- Edits: CRUD apenas do próprio usuário
CREATE POLICY "edits_select_own" ON edits FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "edits_insert_own" ON edits FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "edits_update_own" ON edits FOR UPDATE USING (auth.uid() = user_id);

-- Edit logs: leitura apenas das edições do usuário
CREATE POLICY "edit_logs_select_via_edit" ON edit_logs FOR SELECT
  USING (EXISTS (SELECT 1 FROM edits e WHERE e.id = edit_logs.edit_id AND e.user_id = auth.uid()));

-- Referrals: referrer vê suas indicações; referred vê onde foi indicado
CREATE POLICY "referrals_select_referrer" ON referrals FOR SELECT USING (auth.uid() = referrer_user_id);
CREATE POLICY "referrals_select_referred" ON referrals FOR SELECT USING (auth.uid() = referred_user_id);

-- User sessions: próprio usuário
CREATE POLICY "user_sessions_select_own" ON user_sessions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "user_sessions_insert_own" ON user_sessions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "user_sessions_delete_own" ON user_sessions FOR DELETE USING (auth.uid() = user_id);

-- App settings: leitura pública (configurações do app)
CREATE POLICY "app_settings_select_all" ON app_settings FOR SELECT USING (true);

-- -----------------------------------------------------------------------------
-- 7. DADOS INICIAIS (planos)
-- -----------------------------------------------------------------------------

INSERT INTO plans (name, description, monthly_price, yearly_price, monthly_credits, features, is_active) VALUES
  ('Free', 'Plano gratuito com créditos limitados por mês', 0, 0, 5, '["5 créditos/mês", "Upload básico"]', true),
  ('Basic', 'Para quem edita com frequência', 19.90, 199.00, 50, '["50 créditos/mês", "Suporte por email", "Sem marca d''água"]', true),
  ('Premium', 'Créditos ilimitados e prioridade', 49.90, 499.00, 200, '["200 créditos/mês", "Processamento prioritário", "Suporte prioritário", "API access"]', true)
ON CONFLICT (name) DO NOTHING;

-- =============================================================================
-- 8. SUGESTÕES PARA ESCALAR NO FUTURO
-- =============================================================================
--
-- 1) Créditos: manter credit_transactions como fonte da verdade; para contas
--    com muitas transações, considerar materialized view ou job que recalcula
--    users.credits_balance periodicamente para evitar drift.
--
-- 2) Pagamentos: usar idempotency key (external_payment_id) para evitar
--    cobrança duplicada; considerar tabela payment_events para webhooks.
--
-- 3) Imagens/Storage: manter URLs no banco; arquivos no Supabase Storage ou
--    S3. Políticas de bucket por user_id. Para muitos TB, considerar lifecycle
--    e CDN.
--
-- 4) Edits: jobs de IA em fila (ex: pg_cron + worker ou Supabase Edge Functions).
--    edit_logs ajuda a debugar e medir tempo de processamento.
--
-- 5) Referrals: reward_status 'paid' pode disparar credit_transaction de
--    referral_bonus; centralizar em uma função que aplica bônus e marca paid.
--
-- 6) Índices: monitorar slow queries; adicionar índices compostos se necessário
--    (ex: credit_transactions(user_id, created_at)).
--
-- 7) Particionamento: no futuro, tabelas como payments e credit_transactions
--    podem ser particionadas por created_at (mensal/anual).
--
-- 8) Soft delete: images já tem deleted_at; para users, considerar deleted_at
--    e políticas RLS que filtram deleted_at IS NULL.
--
-- =============================================================================
