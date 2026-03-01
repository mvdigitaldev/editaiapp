/// Modelo de edição pré-configurado (prompt no banco, editável sem deploy).
class ModeloModel {
  final String id;
  final String nome;
  final String? descricao;
  final String categoriaId;
  final String? thumbnailUrl;
  final String? promptPadrao;
  final bool ativo;
  final int ordem;

  const ModeloModel({
    required this.id,
    required this.nome,
    this.descricao,
    required this.categoriaId,
    this.thumbnailUrl,
    this.promptPadrao,
    required this.ativo,
    this.ordem = 0,
  });

  factory ModeloModel.fromJson(Map<String, dynamic> json) {
    return ModeloModel(
      id: json['id'] as String,
      nome: json['nome'] as String,
      descricao: json['descricao'] as String?,
      categoriaId: json['categoria_id'] as String,
      thumbnailUrl: json['thumbnail_url'] as String?,
      promptPadrao: json['prompt_padrao'] as String?,
      ativo: json['ativo'] as bool? ?? true,
      ordem: json['ordem'] as int? ?? 0,
    );
  }
}
