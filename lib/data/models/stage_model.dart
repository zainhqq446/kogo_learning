class StageModel {
  final int? id;
  final String title;
  final String? description;
  final int orderIndex;
  final bool isActive;

  const StageModel({
    this.id,
    required this.title,
    this.description,
    required this.orderIndex,
    required this.isActive,
  });

  factory StageModel.fromMap(Map<String, dynamic> map) {
    return StageModel(
      id: map['id'] as int?,
      title: map['title'] as String,
      description: map['description'] as String?,
      orderIndex: map['order_index'] as int,
      isActive: (map['is_active'] as int) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'order_index': orderIndex,
      'is_active': isActive ? 1 : 0,
    };
  }
}