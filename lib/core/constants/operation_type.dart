/// Enum para mapear valores técnicos de operation_type em labels amigáveis.
enum OperationType {
  textToImage('text_to_image', 'Texto para Imagem'),
  imageToImage('image_to_image', 'Imagem para Imagem'),
  editImage('edit_image', 'Editar Imagem'),
  removeBackground('remove_background', 'Remover Fundo'),
  multiImage('multi_image', 'Múltiplas Imagens'),
  editModel('edit_model', 'Editar com Modelo'),
  unknown('', '—');

  final String value;
  final String label;
  const OperationType(this.value, this.label);

  /// Converte o valor do banco para o enum e retorna o label amigável.
  static String labelFrom(String? raw) {
    if (raw == null || raw.isEmpty) return unknown.label;
    for (final e in OperationType.values) {
      if (e.value == raw) return e.label;
    }
    return unknown.label;
  }
}
