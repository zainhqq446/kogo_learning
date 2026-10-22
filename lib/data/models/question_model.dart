import '../../core/constants/image_dataset_catalog.dart';

class QuestionModel {
  final int? id;
  final int lessonId;
  final String targetText;
  final String normalizedTarget;
  final String? imagePath;
  final String? audioPath;
  final String? hintText;
  final int orderIndex;
  final bool isActive;

  const QuestionModel({
    this.id,
    required this.lessonId,
    required this.targetText,
    required this.normalizedTarget,
    this.imagePath,
    this.audioPath,
    this.hintText,
    required this.orderIndex,
    required this.isActive,
  });

  /// Mengembalikan path gambar: jika di DB sudah tersimpan maka gunakan,
  /// jika null/kosong maka dicari otomatis melalui ImageDatasetCatalog.
  String? get resolvedImagePath {
    if (imagePath != null && imagePath!.isNotEmpty) {
      return imagePath;
    }
    return ImageDatasetCatalog.findAssetPath(targetText);
  }

  factory QuestionModel.fromMap(Map<String, dynamic> map) {
    return QuestionModel(
      id: map['id'] as int?,
      lessonId: map['lesson_id'] as int,
      targetText: map['target_text'] as String,
      normalizedTarget: map['normalized_target'] as String,
      imagePath: map['image_path'] as String?,
      audioPath: map['audio_path'] as String?,
      hintText: map['hint_text'] as String?,
      orderIndex: map['order_index'] as int,
      isActive: (map['is_active'] as int) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'lesson_id': lessonId,
      'target_text': targetText,
      'normalized_target': normalizedTarget,
      'image_path': imagePath,
      'audio_path': audioPath,
      'hint_text': hintText,
      'order_index': orderIndex,
      'is_active': isActive ? 1 : 0,
    };
  }
}