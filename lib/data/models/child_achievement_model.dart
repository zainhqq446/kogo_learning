class ChildAchievementModel {
  final int? id;
  final int childId;
  final int achievementId;
  final String earnedAt;

  // Joined fields
  final String? achievementCode;
  final String? achievementTitle;
  final String? achievementDescription;

  const ChildAchievementModel({
    this.id,
    required this.childId,
    required this.achievementId,
    required this.earnedAt,
    this.achievementCode,
    this.achievementTitle,
    this.achievementDescription,
  });

  factory ChildAchievementModel.fromMap(Map<String, dynamic> map) {
    return ChildAchievementModel(
      id: map['id'] as int?,
      childId: map['child_id'] as int,
      achievementId: map['achievement_id'] as int,
      earnedAt: map['earned_at'] as String,
      achievementCode: map['achievement_code'] as String? ?? map['code'] as String?,
      achievementTitle: map['achievement_title'] as String? ?? map['title'] as String?,
      achievementDescription: map['achievement_description'] as String? ?? map['description'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'child_id': childId,
      'achievement_id': achievementId,
      'earned_at': earnedAt,
    };
  }
}
