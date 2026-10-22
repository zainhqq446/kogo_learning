import '../models/achievement_model.dart';
import '../models/child_achievement_model.dart';

class ChildProgressSummaryModel {
  final int childId;
  final int totalStages;
  final int completedStages;
  final int totalLessons;
  final int completedLessons;
  final int totalQuestions;
  final int completedQuestions;
  final int totalAttempts;
  final int correctAttempts;
  final double accuracyPercent;
  final List<StageProgressModel> stageProgressList;
  final List<ChildAchievementModel> earnedAchievements;
  final List<AchievementModel> allAchievements;

  const ChildProgressSummaryModel({
    required this.childId,
    required this.totalStages,
    required this.completedStages,
    required this.totalLessons,
    required this.completedLessons,
    required this.totalQuestions,
    required this.completedQuestions,
    required this.totalAttempts,
    required this.correctAttempts,
    required this.accuracyPercent,
    required this.stageProgressList,
    required this.earnedAchievements,
    required this.allAchievements,
  });
}

class StageProgressModel {
  final int stageId;
  final String title;
  final int orderIndex;
  final int totalQuestions;
  final int completedQuestions;
  final int totalLessons;
  final int completedLessons;
  final bool isCompleted;
  final double progressPercent;
  final List<LessonProgressModel> lessonProgressList;

  const StageProgressModel({
    required this.stageId,
    required this.title,
    required this.orderIndex,
    required this.totalQuestions,
    required this.completedQuestions,
    required this.totalLessons,
    required this.completedLessons,
    required this.isCompleted,
    required this.progressPercent,
    required this.lessonProgressList,
  });
}

class LessonProgressModel {
  final int lessonId;
  final String title;
  final String lessonType;
  final int totalQuestions;
  final int completedQuestions;
  final bool isCompleted;
  final double progressPercent;

  const LessonProgressModel({
    required this.lessonId,
    required this.title,
    required this.lessonType,
    required this.totalQuestions,
    required this.completedQuestions,
    required this.isCompleted,
    required this.progressPercent,
  });
}
