class AchievementModel {
  final int? id;
  final String code;
  final String title;
  final String? description;

  const AchievementModel({
    this.id,
    required this.code,
    required this.title,
    this.description,
  });

  factory AchievementModel.fromMap(Map<String, dynamic> map) {
    return AchievementModel(
      id: map['id'] as int?,
      code: map['code'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'code': code,
      'title': title,
      'description': description,
    };
  }

  AchievementModel copyWith({
    int? id,
    String? code,
    String? title,
    String? description,
  }) {
    return AchievementModel(
      id: id ?? this.id,
      code: code ?? this.code,
      title: title ?? this.title,
      description: description ?? this.description,
    );
  }
}
