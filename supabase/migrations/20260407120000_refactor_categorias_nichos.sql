-- =============================================================================
-- Refatorar categorias e modelos: novos nichos de negócio + prompts FLUX otimizados
-- Prompts seguem Subject + Action + Style + Context (BFL FLUX.2 prompting guide)
-- =============================================================================

-- 1) Limpar dados atuais
DELETE FROM public.modelos;
DELETE FROM public.categorias;

-- 2) Inserir 11 novas categorias
INSERT INTO public.categorias (nome, slug, ordem) VALUES
  ('Alimentação', 'alimentacao', 10),
  ('Moda e produtos', 'moda-produtos', 20),
  ('Beleza e estética', 'beleza-estetica', 30),
  ('Casa, decoração e arquitetura', 'casa-decoracao', 40),
  ('Automotivo', 'automotivo', 50),
  ('Pets', 'pets', 60),
  ('Imóveis', 'imoveis', 70),
  ('Profissionais autônomos', 'profissionais-autonomos', 80),
  ('Pequenos empreendedores', 'pequenos-empreendedores', 90),
  ('Marketing e conteúdo', 'marketing-conteudo', 100),
  ('Eventos', 'eventos', 110);

-- 3) Inserir modelos com prompt_padrao otimizados (BFL best practices)
INSERT INTO public.modelos (nome, descricao, categoria_id, prompt_padrao, ordem) VALUES

-- ALIMENTAÇÃO
(
  'Bolos e doces para Instagram',
  'Melhorar fotos de bolos e doces para vender no Instagram',
  (SELECT id FROM public.categorias WHERE slug = 'alimentacao' LIMIT 1),
  'Keep the cake or dessert from the image exactly as shown—same colors, frosting, and proportions. Enhance lighting with soft diffused light for an appetizing glow. Professional confectionery photography for Instagram. Warm natural tones, sharp focus on textures. Shot on Canon 5D Mark IV, 85mm f/2.8, shallow depth of field. High-end pastry photography style.',
  10
),
(
  'Cardápio e delivery',
  'Criar fotos melhores para post, cardápio e delivery',
  (SELECT id FROM public.categorias WHERE slug = 'alimentacao' LIMIT 1),
  'Keep the dish or food item from the image exactly as shown—same plating, colors, and portions. Replace the background with a seamless neutral studio backdrop, soft gray or warm white. Professional restaurant menu photography. Soft diffused lighting, natural appetizing tones. Shot on Sony A7IV, 85mm f/2.8. E-commerce and delivery catalog quality.',
  20
),
(
  'Mesas e buffets',
  'Mostrar mesas e eventos com aparência mais profissional',
  (SELECT id FROM public.categorias WHERE slug = 'alimentacao' LIMIT 1),
  'Keep the table setting, buffet layout, and food displays from the image exactly as shown. Enhance ambient lighting to look more professional and elegant. Event and catering photography style. Warm ambient light, refined presentation. Shot on Fujifilm X-T5, 35mm f/1.4. Wedding and corporate event quality.',
  30
),

-- MODA E PRODUTOS
(
  'Roupas para vendas online',
  'Melhorar fotos de peças para vendas online',
  (SELECT id FROM public.categorias WHERE slug = 'moda-produtos' LIMIT 1),
  'Keep the garment or clothing item from the image exactly as shown—same folds, colors, and fabric texture. Replace the background with a seamless white or light gray studio backdrop. Professional fashion e-commerce photography. Soft diffused lighting, sharp fabric details. Shot on Canon 5D Mark IV, 85mm f/2.8. Instagram and online store ready.',
  40
),
(
  'Acessórios e joias',
  'Valorizar produtos e destacar brilho e detalhes das peças',
  (SELECT id FROM public.categorias WHERE slug = 'moda-produtos' LIMIT 1),
  'Keep the jewelry or accessory from the image exactly as shown—same piece, stones, and metal. Place on a clean neutral or dark velvet backdrop. Professional jewelry photography. Enhance sparkle and fine details with controlled lighting. Shot on Sony A7IV, 100mm macro, soft diffused light. Luxury product photography.',
  50
),
(
  'Cosméticos e óculos',
  'Melhorar fotos de produtos de beleza e óculos',
  (SELECT id FROM public.categorias WHERE slug = 'moda-produtos' LIMIT 1),
  'Keep the product from the image exactly as shown—same bottle, packaging, or eyewear. Place on a clean white or marble surface with minimal shadows. Professional beauty and eyewear product photography. Soft overhead lighting, true-to-life colors. Shot on Canon 5D Mark IV, 50mm f/2.8. E-commerce and Instagram ready.',
  60
),

-- BELEZA E ESTÉTICA
(
  'Cabelos e penteados',
  'Fotos mais bonitas de cabelos e penteados',
  (SELECT id FROM public.categorias WHERE slug = 'beleza-estetica' LIMIT 1),
  'Keep the person, hair, and styling from the image exactly as shown. Enhance lighting and colors for a polished salon look. Professional hair salon photography. Natural skin tones, glossy hair highlights. Shot on Sony A7IV, 85mm f/2.8, soft window light. Editorial beauty style.',
  70
),
(
  'Barba e cortes masculinos',
  'Destacar barba e cortes masculinos',
  (SELECT id FROM public.categorias WHERE slug = 'beleza-estetica' LIMIT 1),
  'Keep the person and haircut or beard from the image exactly as shown. Enhance contrast and definition for a sharp barbershop look. Professional barber photography. Controlled lighting, crisp details on facial hair. Shot on Canon 5D Mark IV, 85mm f/2.8. Grooming portfolio quality.',
  80
),
(
  'Antes e depois de tratamentos',
  'Mostrar resultados de tratamentos de forma profissional',
  (SELECT id FROM public.categorias WHERE slug = 'beleza-estetica' LIMIT 1),
  'Keep both before and after subjects from the image exactly as shown—do not alter the actual results. Enhance lighting and clarity for a professional clinical presentation. Aesthetic clinic photography. Neutral background, even lighting. Shot on Sony A7IV, 50mm f/2.8. Medical and skincare documentation style.',
  90
),

-- CASA, DECORAÇÃO E ARQUITETURA
(
  'Projetos e ambientes',
  'Melhorar fotos de projetos e ambientes',
  (SELECT id FROM public.categorias WHERE slug = 'casa-decoracao' LIMIT 1),
  'Keep the room, furniture, and architecture from the image exactly as shown. Enhance natural lighting and colors for a refined interior look. Professional architecture and interior photography. Soft daylight, true-to-life materials. Shot on Canon 5D Mark IV, 24mm f/2.8. Architectural digest style.',
  100
),
(
  'Móveis e decoração',
  'Valorizar decoração e fotos de móveis',
  (SELECT id FROM public.categorias WHERE slug = 'casa-decoracao' LIMIT 1),
  'Keep the furniture or décor item from the image exactly as shown—same piece and finish. Place on a clean neutral background or in a minimal studio setting. Professional furniture catalog photography. Soft diffused lighting, accurate colors. Shot on Sony A7IV, 35mm f/2.8. E-commerce and portfolio quality.',
  110
),
(
  'Jardins e paisagismo',
  'Destacar jardins e projetos externos',
  (SELECT id FROM public.categorias WHERE slug = 'casa-decoracao' LIMIT 1),
  'Keep the garden, plants, and landscape from the image exactly as shown. Enhance natural light and greenery for a lush outdoor look. Professional landscaping photography. Golden hour feel, sharp foliage. Shot on Fujifilm X-T5, 24mm f/2.8. Landscape and garden design portfolio style.',
  120
),

-- AUTOMOTIVO
(
  'Carros para anúncios',
  'Melhorar fotos de carros para anúncios',
  (SELECT id FROM public.categorias WHERE slug = 'automotivo' LIMIT 1),
  'Keep the vehicle from the image exactly as shown—same make, model, color, and condition. Replace the background with a clean neutral studio floor or subtle gradient. Professional car dealership photography. Enhance reflections and paint finish. Shot on Canon 5D Mark IV, 35mm f/2.8. Premium automotive advertising style.',
  130
),
(
  'Antes e depois lavagem e detalhamento',
  'Mostrar resultado de lavagem e detalhamento automotivo',
  (SELECT id FROM public.categorias WHERE slug = 'automotivo' LIMIT 1),
  'Keep the vehicle from the image exactly as shown. Enhance the finish to highlight the after-detailing result—deeper shine, clearer reflections. Professional automotive detailing photography. Controlled lighting on paint and trim. Shot on Sony A7IV, 50mm f/2.8. Before-and-after showcase style.',
  140
),

-- PETS
(
  'Produtos e pets',
  'Fotos melhores de produtos e pets',
  (SELECT id FROM public.categorias WHERE slug = 'pets' LIMIT 1),
  'Keep the pet or product from the image exactly as shown. Enhance lighting and colors for a warm, appealing look. Professional pet photography. Natural tones, sharp focus on fur or product. Shot on Canon 5D Mark IV, 85mm f/2.8. Pet store and Instagram quality.',
  150
),
(
  'Resultado banho e tosa',
  'Mostrar resultado dos pets após banho e tosa',
  (SELECT id FROM public.categorias WHERE slug = 'pets' LIMIT 1),
  'Keep the pet from the image exactly as shown—same breed, pose, and grooming result. Enhance lighting for a polished salon look. Professional pet grooming photography. Soft diffused light, clean coat details. Shot on Sony A7IV, 85mm f/2.8. Grooming portfolio style.',
  160
),

-- IMÓVEIS
(
  'Casas e apartamentos',
  'Melhorar fotos de casas e apartamentos para anúncios',
  (SELECT id FROM public.categorias WHERE slug = 'imoveis' LIMIT 1),
  'Keep the property, rooms, and finishes from the image exactly as shown. Enhance natural light and colors for an attractive listing look. Professional real estate photography. Bright, inviting tones, sharp details. Shot on Canon 5D Mark IV, 16mm f/2.8. MLS and listing quality.',
  170
),

-- PROFISSIONAIS AUTÔNOMOS
(
  'Pratos e receitas',
  'Fotos de pratos e receitas para nutricionistas',
  (SELECT id FROM public.categorias WHERE slug = 'profissionais-autonomos' LIMIT 1),
  'Keep the dish or meal from the image exactly as shown—same ingredients and presentation. Enhance lighting for an appetizing, healthy look. Professional nutrition and culinary photography. Natural daylight, warm tones. Shot on Fujifilm X-T5, 35mm f/1.4. Recipe and dietitian portfolio style.',
  180
),
(
  'Consultório e resultados',
  'Fotos mais profissionais do consultório e resultados',
  (SELECT id FROM public.categorias WHERE slug = 'profissionais-autonomos' LIMIT 1),
  'Keep the person, treatment area, or result from the image exactly as shown. Enhance lighting for a clean, professional clinical look. Professional medical and dental photography. Neutral lighting, accurate skin tones. Shot on Sony A7IV, 50mm f/2.8. Practice marketing quality.',
  190
),

-- PEQUENOS EMPREENDEDORES
(
  'Produtos artesanais',
  'Melhorar fotos de produtos feitos à mão',
  (SELECT id FROM public.categorias WHERE slug = 'pequenos-empreendedores' LIMIT 1),
  'Keep the handmade product from the image exactly as shown—same materials, colors, and craftsmanship. Place on a neutral background with soft natural lighting. Professional artisan product photography. Warm tones, texture detail. Shot on Canon 5D Mark IV, 50mm f/2.8. E-commerce and craft fair quality.',
  200
),
(
  'Flores e arranjos',
  'Valorizar flores e arranjos',
  (SELECT id FROM public.categorias WHERE slug = 'pequenos-empreendedores' LIMIT 1),
  'Keep the flowers or arrangement from the image exactly as shown—same blooms and colors. Enhance lighting for fresh, vibrant tones. Professional floristry photography. Soft diffused light, petal detail. Shot on Sony A7IV, 85mm f/2.8. Floral catalog and Instagram quality.',
  210
),

-- MARKETING E CONTEÚDO
(
  'Fotos para redes sociais',
  'Melhorar fotos para Instagram e redes sociais',
  (SELECT id FROM public.categorias WHERE slug = 'marketing-conteudo' LIMIT 1),
  'Keep the subject from the image exactly as shown—same person, product, or scene. Enhance colors, contrast, and lighting for an Instagram-ready look. Professional social media photography. Natural appealing tones, sharp focus. Shot on Sony A7IV, 50mm f/2.8. Influencer and brand content style.',
  220
),
(
  'Edição rápida para clientes',
  'Editar fotos rapidamente para clientes',
  (SELECT id FROM public.categorias WHERE slug = 'marketing-conteudo' LIMIT 1),
  'Keep the subject from the image exactly as shown. Apply subtle professional enhancement—refined colors, balanced exposure, clean look. Social media manager and content creator style. Natural result, no heavy filters. Shot on Canon 5D Mark IV, 35mm f/2.8. Client delivery ready.',
  230
),

-- EVENTOS
(
  'Eventos realizados',
  'Mostrar eventos realizados com aparência profissional',
  (SELECT id FROM public.categorias WHERE slug = 'eventos' LIMIT 1),
  'Keep the event scene, décor, and people from the image exactly as shown. Enhance lighting and ambiance for a polished event look. Professional event photography. Warm ambient light, celebration feel. Shot on Sony A7IV, 35mm f/1.4. Wedding and corporate event portfolio style.',
  240
),
(
  'Decoração e cenários',
  'Destacar decoração e cenários de eventos',
  (SELECT id FROM public.categorias WHERE slug = 'eventos' LIMIT 1),
  'Keep the décor, props, and setting from the image exactly as shown. Enhance lighting to highlight the rental pieces and setup. Professional event decoration photography. Soft lighting, true-to-life colors. Shot on Canon 5D Mark IV, 24mm f/2.8. Rental and event company portfolio style.',
  250
);
