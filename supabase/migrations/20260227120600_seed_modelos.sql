-- =============================================================================
-- Seed inicial de modelos por nicho (carros, roupas, comida, joias, objetos)
-- Prompts em inglês para FLUX (Subject + Action + Style + Context)
-- =============================================================================

INSERT INTO public.modelos (nome, descricao, categoria, prompt_padrao, ordem) VALUES
(
  'Melhorar cores para loja de carros',
  'Ajuste automático de cores e contraste para fotos de veículos',
  'carros',
  'Professional car dealership photo. Enhance colors, contrast and lighting. Make the vehicle look premium and appealing for Instagram. Preserve the original scene and environment. High quality automotive photography style.',
  10
),
(
  'Fundo neutro para carros',
  'Deixe o carro em destaque com fundo limpo',
  'carros',
  'Professional car photo on neutral clean background. Remove distracting elements, enhance vehicle visibility. Premium automotive photography for Instagram. Preserve the car exactly as shown.',
  20
),
(
  'Melhorar cores para moda',
  'Fotos de roupas com cores vibrantes e iluminação profissional',
  'roupas',
  'Professional fashion and clothing photography. Enhance colors, lighting and fabric details. Instagram-ready style. Preserve the original garment and model. High-end e-commerce quality.',
  30
),
(
  'Fundo neutro para roupas',
  'Produto em destaque com fundo limpo',
  'roupas',
  'Professional clothing product photo on clean white or neutral background. Remove background distractions. E-commerce and Instagram ready. Preserve garment colors and details exactly.',
  40
),
(
  'Melhorar comida para Instagram',
  'Fotos de pratos com cores apetitosas e iluminação profissional',
  'comida',
  'Professional food photography for Instagram. Enhance colors, lighting and appetizing appearance. Restaurant and culinary style. Preserve the dish exactly. Mouth-watering food photo quality.',
  50
),
(
  'Fundo neutro para comida',
  'Prato em destaque com fundo limpo',
  'comida',
  'Professional food photo on clean neutral background. Remove distracting elements. Restaurant menu and Instagram quality. Preserve the dish presentation exactly.',
  60
),
(
  'Melhorar joias e bijuterias',
  'Fotos de joias com brilho e detalhes em destaque',
  'joias',
  'Professional jewelry and accessories photography. Enhance sparkle, clarity and fine details. E-commerce and Instagram ready. Preserve the original piece exactly. Luxury product photography style.',
  70
),
(
  'Fundo neutro para joias',
  'Joia em destaque com fundo limpo',
  'joias',
  'Professional jewelry photo on clean neutral background. Remove distractions, enhance sparkle and details. E-commerce product photography. Preserve the piece exactly.',
  80
),
(
  'Melhorar objetos em geral',
  'Fotos de produtos com cores e iluminação profissional',
  'objetos',
  'Professional product photography. Enhance colors, lighting and clarity. E-commerce and Instagram ready. Preserve the original product exactly. High quality commercial photography style.',
  90
),
(
  'Fundo neutro para objetos',
  'Produto em destaque com fundo limpo',
  'objetos',
  'Professional product photo on clean neutral background. Remove background distractions. E-commerce and Instagram ready. Preserve product colors and details exactly.',
  100
),
(
  'Ajuste geral para Instagram',
  'Melhorar qualquer foto para redes sociais',
  'outros',
  'Professional Instagram-ready photo. Enhance colors, contrast and lighting. Preserve the original scene. Social media optimized quality. Natural and appealing result.',
  110
);
