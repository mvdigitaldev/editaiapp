/// Categoria de modelos de edição (carros, moda, comida, etc.).
class CategoriaModel {
  final String id;
  final String nome;
  final String slug;
  final int ordem;
  final bool ativo;
  final String? coverImageUrl;

  const CategoriaModel({
    required this.id,
    required this.nome,
    required this.slug,
    this.ordem = 0,
    this.ativo = true,
    this.coverImageUrl,
  });

  factory CategoriaModel.fromJson(Map<String, dynamic> json) {
    final url = json['cover_image_url'] as String?;
    return CategoriaModel(
      id: json['id'] as String,
      nome: json['nome'] as String,
      slug: json['slug'] as String,
      ordem: json['ordem'] as int? ?? 0,
      ativo: json['ativo'] as bool? ?? true,
      coverImageUrl: url != null && url.trim().isNotEmpty ? url.trim() : null,
    );
  }
}
