/// Categoria de modelos de edição (carros, moda, comida, etc.).
class CategoriaModel {
  static const String editModeFixed = 'fixed';
  static const String editModeGuided = 'guided';

  final String id;
  final String nome;
  final String slug;
  final int ordem;
  final bool ativo;
  final String? coverImageUrl;
  /// `fixed` = edição em um passo com [ModeloModel.promptPadrao]; `guided` = sugestões IA + texto do usuário.
  final String editMode;
  final bool featured;

  const CategoriaModel({
    required this.id,
    required this.nome,
    required this.slug,
    this.ordem = 0,
    this.ativo = true,
    this.coverImageUrl,
    this.editMode = editModeGuided,
    this.featured = false,
  });

  bool get isFixedEdit => editMode == editModeFixed;
  bool get isGuidedEdit => editMode == editModeGuided;

  factory CategoriaModel.fromJson(Map<String, dynamic> json) {
    final url = json['cover_image_url'] as String?;
    final mode = json['edit_mode'] as String?;
    return CategoriaModel(
      id: json['id'] as String,
      nome: json['nome'] as String,
      slug: json['slug'] as String,
      ordem: json['ordem'] as int? ?? 0,
      ativo: json['ativo'] as bool? ?? true,
      coverImageUrl: url != null && url.trim().isNotEmpty ? url.trim() : null,
      editMode: (mode == editModeFixed || mode == editModeGuided)
          ? mode!
          : editModeGuided,
      featured: json['featured'] as bool? ?? false,
    );
  }
}
