import 'body_reshape_labels.dart';

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
    'hairline': 'Linha do cabelo',
    'jaw': 'Mandíbula',
    'jaw_angle': 'Ângulo da mandíbula',
    'chin': 'Tamanho do queixo',
    'v_chin': 'V do queixo',
    'v_shape': 'Formato V',
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
    'skin_shine': 'Reduzir brilho',
    'teeth_whitening': 'Clarear dentes',
    'blush': 'Blush',
    'contour': 'Contorno',
    'eyebrows': 'Sobrancelhas',
    'eyelashes': 'Cílios',
    'iris_enhance': 'Realce de íris',
    'brightness': 'Brilho',
    'contrast': 'Contraste',
    'saturation': 'Saturação',
    'exposure': 'Exposição',
    'temperature': 'Temperatura',
    'tint': 'Matiz',
    'vibrance': 'Vibração',
    'hue': 'Matiz global',
    'highlights': 'Realces',
    'shadows': 'Sombras',
    'whites': 'Brancos',
    'blacks': 'Pretos',
    'fade': 'Desbotado',
    'sharpness': 'Nitidez',
    'luminance': 'Luminosidade',
    'vignette': 'Vinheta',
    'gamma': 'Gama',
    ...BodyReshapeLabels.parameterLabelPt,
  };

  static String parameterLabel(String key) =>
      parameterLabelPt[key] ??
      BodyReshapeLabels.parameterLabelPt[key] ??
      key;

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
  static String multiFaceSelectHint(int count) =>
      '$count rostos detectados — toque no rosto que deseja editar';
  static const faceFiltersDevTitle = 'Filtros faciais (dev)';
  static const linkEyesTitle = 'Olhos vinculados (simetria L/R)';
  static const cheekboneSideBoth = 'Geral';
  static const cheekboneSideLeft = 'Esquerda';
  static const cheekboneSideRight = 'Direita';

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

  /// Hints de gating (Sprint 3 — cap. 19).
  static const gateHintPt = <String, String>{
    'gate_no_face': 'Rosto não detectado — ferramenta indisponível',
    'gate_face_small': 'Rosto pequeno na foto — intensidade limitada',
    'gate_face_too_small_acne': 'Rosto muito pequeno para remover manchas',
    'gate_blur_high': 'Foto borrada — suavização limitada para evitar efeito plástico',
    'gate_noise_high': 'Ruído alto — efeito reduzido',
    'gate_yaw_high': 'Rosto em perfil — ajuste limitado',
    'gate_pose_limited': 'Pose ou enquadramento — intensidade levemente reduzida',
    'gate_hard_shadow': 'Luz lateral forte — olheiras parcialmente corrigíveis',
    'gate_low_light': 'Pouca luz — resultado parcial',
    'gate_skin_unavailable': 'Máscara de pele indisponível',
    'gate_partial_occlusion': 'Rosto parcialmente coberto — resultado pode ficar desigual',
    'gate_exposure_blown': 'Exposição estourada — brilho parcialmente recuperável',
    'gate_compression_high': 'Foto muito comprimida — manchas difíceis de distinguir',
    'gate_eyes_occluded': 'Olhos cobertos — ferramenta indisponível',
    'gate_mouth_occluded': 'Boca coberta — dentes indisponível',
    'gate_mouth_closed': 'Boca fechada — clarear dentes indisponível',
  };

  static String? gateHint(String? key) =>
      key == null ? null : gateHintPt[key];

  static const adaptivePresetsSection = 'Presets adaptativos';

  static const marketplacePublishTitle = 'Publicar no marketplace';
  static const marketplacePublishSubtitleAll =
      'Outros usuários logados poderão instalar uma cópia deste filtro no editor manual.';
  static const marketplacePublishSubtitleAdminOnly =
      'Somente administradores podem publicar filtros no marketplace.';
  static const marketplacePublishDenied =
      'Apenas administradores podem publicar filtros no marketplace.';
}
