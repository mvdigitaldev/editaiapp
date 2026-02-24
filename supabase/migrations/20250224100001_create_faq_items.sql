CREATE TABLE IF NOT EXISTS public.faq_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  question text NOT NULL,
  answer text NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.faq_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "faq_items_select_public" ON public.faq_items
  FOR SELECT USING (true);

INSERT INTO public.faq_items (question, answer, sort_order) VALUES
(
  'O que é o EditAI?',
  'O EditAI é um aplicativo de edição de fotos que utiliza inteligência artificial para aprimorar e transformar suas imagens. Com ele, você pode aplicar filtros avançados, remover fundos, retocar fotos e muito mais, tudo com poucos toques.',
  1
),
(
  'Como funcionam os créditos?',
  'Os créditos são utilizados para realizar edições com inteligência artificial. Cada edição consome uma quantidade de créditos dependendo da complexidade do processamento. Seus créditos são renovados mensalmente de acordo com o seu plano. Você também pode comprar créditos avulsos na loja de créditos.',
  2
),
(
  'Como faço para assinar um plano?',
  'Acesse a seção "Meu Plano" no seu perfil. Lá você poderá ver todos os planos disponíveis, filtrar por duração (mensal, trimestral ou semestral) e selecionar o que melhor atende às suas necessidades. Clique em "Assinar Agora" para ser direcionado à página de pagamento.',
  3
),
(
  'Como cancelo minha assinatura?',
  'Para cancelar sua assinatura, acesse a seção "Meu Plano" no perfil e siga as instruções de cancelamento. Após o cancelamento, você continuará tendo acesso ao plano até o final do período já pago. Depois disso, sua conta será revertida para o plano gratuito.',
  4
),
(
  'Quais formatos de imagem são suportados?',
  'O EditAI suporta os formatos de imagem mais comuns: JPEG, PNG e WebP. Recomendamos utilizar imagens com boa resolução para obter os melhores resultados nas edições com IA.',
  5
),
(
  'Minhas fotos estão seguras?',
  'Sim! Levamos a segurança dos seus dados muito a sério. Suas fotos são armazenadas em servidores protegidos com criptografia em trânsito e em repouso. Elas são utilizadas exclusivamente para o processamento das edições solicitadas e não são compartilhadas com terceiros. Você pode excluir suas fotos a qualquer momento.',
  6
),
(
  'O que acontece se meus créditos acabarem?',
  'Quando seus créditos acabam, você pode aguardar a renovação mensal automática (conforme seu plano) ou comprar créditos avulsos na loja de créditos para continuar editando imediatamente. Funcionalidades básicas do aplicativo continuam disponíveis mesmo sem créditos.',
  7
),
(
  'Como solicito reembolso?',
  'Solicitações de reembolso devem ser feitas dentro de 7 dias após a compra. Entre em contato com nosso suporte pelo WhatsApp ou e-mail informando o motivo da solicitação e os dados da sua conta. Analisaremos cada caso individualmente conforme nossa política de reembolso.',
  8
)
ON CONFLICT DO NOTHING;
