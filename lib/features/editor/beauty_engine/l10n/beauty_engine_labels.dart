/// Rótulos em português para UI do Beauty Engine (Sprint 27).
/// Keys internas (`face_slim`, etc.) permanecem inalteradas.
abstract final class BeautyEngineLabels {
  static const parameterLabelPt = <String, String>{
    'face_slim': 'Afinar rosto',
    'narrow_face': 'Estreitar rosto',
    'v_face': 'Rosto em V',
    'nose_slim': 'Afinar nariz',
    'nose_length': 'Comprimento do nariz',
    'nose_height': 'Altura do nariz',
    'nose_tip': 'Ponta do nariz',
    'nose_bridge': 'Ponte nasal',
    'eye_scale': 'Tamanho dos olhos',
    'eye_distance': 'Distância dos olhos',
    'eye_height': 'Altura dos olhos',
    'eye_rotation': 'Rotação dos olhos',
    'double_eyelid': 'Pálpebra dupla',
    'jaw': 'Mandíbula',
    'chin': 'Queixo',
    'head_size': 'Tamanho da cabeça',
    'cheekbone': 'Maçãs do rosto',
    'forehead': 'Testa',
    'temple': 'Têmporas',
    'mouth_width': 'Largura da boca',
    'lip_thickness': 'Espessura dos lábios',
    'smile': 'Sorriso',
    'skin_smooth': 'Suavizar pele',
    'skin_whitening': 'Clarear pele',
    'remove_acne': 'Remover acne',
    'remove_wrinkles': 'Remover rugas',
    'remove_dark_circles': 'Olheiras',
    'teeth_whitening': 'Clarear dentes',
    'blush': 'Blush',
    'contour': 'Contorno',
    'eyebrows': 'Sobrancelhas',
    'eyelashes': 'Cílios',
    'waist_slim': 'Afinar cintura',
    'hip': 'Quadril',
    'body_slim': 'Afinar corpo',
    'leg_length': 'Alongar pernas',
    'leg_slim': 'Afinar pernas',
    'arm_slim': 'Afinar braços',
    'neck_slim': 'Afinar pescoço',
    'shoulder_width': 'Largura dos ombros',
  };

  static String parameterLabel(String key) =>
      parameterLabelPt[key] ?? key;

  static const lutOptionsPt = {
    'Nenhum': null,
    'Natural': 'assets/filters/lut/natural.png',
    'Cinema': 'assets/filters/lut/cinema_teal_orange.png',
  };

  static const sectionLut = 'Filtro de cor';
  static const sectionLight = 'Luz';
  static const sectionColor = 'Cor';
  static const sectionEffect = 'Efeito';
  static const sectionTune = 'Cor / Ajustes';
  static const sectionFace = 'Rosto';
  static const sectionSkin = 'Pele';
  static const sectionBody = 'Corpo';

  static const beautyEditorTitle = 'Retoque beauty';
  static const beautyEditorEmptyHint =
      'Selecione uma foto e use os ajustes abaixo para afinar rosto, nariz, corpo e pele.';
  static const faceNotDetectedHint =
      'Rosto não detectado nesta foto. Use uma foto com rosto visível de frente.';
  static const faceFiltersDevTitle = 'Filtros faciais (dev)';
  static const linkEyesTitle = 'Olhos vinculados (simetria L/R)';

  static const filterCreatorTitle = 'Criar filtro custom';
  static const filterCreatorPersonalUseBanner =
      'Seu filtro fica disponível em Editar manualmente → Filtros (uso pessoal).';
  static const filterCreatorPublishAdminNote =
      'Apenas administradores podem publicar filtros no marketplace.';
  static const filterMarketplaceTitle = 'Marketplace de filtros';
  static const manualEditorMarketplaceHint =
      'Baixe mais filtros no Marketplace';
  static const filterInstalledHint =
      'Filtro instalado. Disponível em Editar manualmente → Filtros.';
  static const filterInstallAction = 'Instalar no editor manual';

  static const marketplacePublishTitle = 'Publicar no marketplace';
  static const marketplacePublishSubtitleAll =
      'Outros usuários logados poderão instalar uma cópia deste filtro no editor manual.';
  static const marketplacePublishSubtitleAdminOnly =
      'Somente administradores podem publicar filtros no marketplace.';
  static const marketplacePublishDenied =
      'Apenas administradores podem publicar filtros no marketplace.';
}
