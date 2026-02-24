class FaqItemModel {
  final String id;
  final String question;
  final String answer;
  final int sortOrder;

  const FaqItemModel({
    required this.id,
    required this.question,
    required this.answer,
    required this.sortOrder,
  });

  factory FaqItemModel.fromJson(Map<String, dynamic> json) {
    return FaqItemModel(
      id: json['id'] as String,
      question: json['question'] as String,
      answer: json['answer'] as String,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}
