class LegalDocumentModel {
  final String id;
  final String slug;
  final String title;
  final String content;
  final DateTime updatedAt;

  const LegalDocumentModel({
    required this.id,
    required this.slug,
    required this.title,
    required this.content,
    required this.updatedAt,
  });

  factory LegalDocumentModel.fromJson(Map<String, dynamic> json) {
    return LegalDocumentModel(
      id: json['id'] as String,
      slug: json['slug'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
