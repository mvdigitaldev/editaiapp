CREATE TABLE IF NOT EXISTS public.credit_packs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  credits integer NOT NULL,
  price numeric(10, 2) NOT NULL,
  is_popular boolean NOT NULL DEFAULT false,
  has_savings boolean NOT NULL DEFAULT false,
  link_payment text NULL,
  sort_order integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.credit_packs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "credit_packs_select_public" ON public.credit_packs
  FOR SELECT USING (true);

INSERT INTO public.credit_packs (name, credits, price, is_popular, has_savings, link_payment, sort_order) VALUES
  ('Pacote Inicial', 10, 9.90, false, false, 'https://example.com/checkout/pacote-inicial', 1),
  ('Pacote Pro', 50, 39.90, true, false, 'https://example.com/checkout/pacote-pro', 2),
  ('Pacote Studio', 150, 99.90, false, true, 'https://example.com/checkout/pacote-studio', 3)
ON CONFLICT DO NOTHING;
