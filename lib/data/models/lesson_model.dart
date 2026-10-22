class LessonModel {
  final int? id;
  final int stageId;
  final String title;
  final String? description;
  final String lessonType;
  final int orderIndex;
  final bool isActive;

  const LessonModel({
    this.id,
    required this.stageId,
    required this.title,
    this.description,
    required this.lessonType,
    required this.orderIndex,
    required this.isActive,
  });

  factory LessonModel.fromMap(Map<String, dynamic> map) {
    return LessonModel(
      id: map['id'] as int?,
      stageId: map['stage_id'] as int,
      title: map['title'] as String,
      description: map['description'] as String?,
      lessonType: map['lesson_type'] as String,
      orderIndex: map['order_index'] as int,
      isActive: (map['is_active'] as int) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'stage_id': stageId,
      'title': title,
      'description': description,
      'lesson_type': lessonType,
      'order_index': orderIndex,
      'is_active': isActive ? 1 : 0,
    };
  }
}