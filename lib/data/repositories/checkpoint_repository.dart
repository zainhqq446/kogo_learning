import '../database/app_database.dart';
import '../models/question_model.dart';
import '../../core/constants/image_dataset_catalog.dart';

/// Model sederhana representasi data kata dalam sesi checkpoint
class CheckpointWord {
  final int id;
  final String targetText;
  final String? syllables;
  final String? imageAssetPath;
  final String? category;

  const CheckpointWord({
    required this.id,
    required this.targetText,
    this.syllables,
    this.imageAssetPath,
    this.category,
  });

  QuestionModel toQuestionModel({required int lessonId, required int orderIndex}) {
    final resolvedPath = imageAssetPath ?? ImageDatasetCatalog.findAssetPath(targetText);
    return QuestionModel(
      id: id,
      lessonId: lessonId,
      targetText: targetText,
      normalizedTarget: targetText.toLowerCase().trim(),
      imagePath: resolvedPath,
      audioPath: 'assets/audio/words/${targetText.toLowerCase()}.mp3',
      hintText: syllables != null ? 'Ucapkan kata $syllables' : 'Ucapkan kata $targetText',
      orderIndex: orderIndex,
      isActive: true,
    );
  }
}

/// Repository untuk mendistribusikan kata-kata dataset ke 25 checkpoint per stage
class CheckpointRepository {
  final AppDatabase _dbHelper;

  CheckpointRepository({AppDatabase? dbHelper})
      : _dbHelper = dbHelper ?? AppDatabase.instance;

  static const int totalCheckpointsPerWordStage = 25;
  static const int wordsPerCheckpoint = 6; // 25 * 6 = 150 kata

  /// Mengambil daftar kata untuk checkpoint ke-[checkpointNumber] (1-indexed) pada stage tertentu
  Future<List<CheckpointWord>> getWordsForCheckpoint({
    required int stageId,
    required int checkpointNumber,
  }) async {
    final db = await _dbHelper.database;

    // Untuk Stage 1 (Pengenalan Huruf: 5 checkpoint, masing-masing 5-6 huruf alfabet)
    if (stageId == 1) {
      final alphabet = [
        'A', 'B', 'C', 'D', 'E',
        'F', 'G', 'H', 'I', 'J',
        'K', 'L', 'M', 'N', 'O',
        'P', 'Q', 'R', 'S', 'T',
        'U', 'V', 'W', 'X', 'Y', 'Z'
      ];
      final startIndex = ((checkpointNumber - 1) * 5).clamp(0, alphabet.length);
      final endIndex = (checkpointNumber == 5 ? alphabet.length : startIndex + 5).clamp(0, alphabet.length);

      final letters = alphabet.sublist(startIndex, endIndex);
      return letters.asMap().entries.map((entry) {
        final letter = entry.value;
        return CheckpointWord(
          id: 1000 + (checkpointNumber * 10) + entry.key,
          targetText: letter,
          syllables: letter,
          imageAssetPath: ImageDatasetCatalog.findAssetPath(letter),
          category: 'huruf',
        );
      }).toList();
    }

    // Untuk Stage 2, 3, dan 4: Ambil 6 kata dari 150 kata di learning_words
    final offset = (checkpointNumber - 1) * wordsPerCheckpoint;
    final results = await db.query(
      'learning_words',
      where: 'stage_id = ? AND is_active = 1',
      whereArgs: [stageId],
      orderBy: 'question_order ASC, id ASC',
      limit: wordsPerCheckpoint,
      offset: offset,
    );


    if (results.isEmpty) {
      // Fallback jika database belum terisi penuh
      return [];
    }

    return results.map((row) {
      final target = row['target_text'] as String;
      final rawPath = row['image_asset_path'] as String?;
      final assetPath = rawPath ?? ImageDatasetCatalog.findAssetPath(target);

      return CheckpointWord(
        id: row['id'] as int,
        targetText: target,
        syllables: row['syllables'] as String?,
        imageAssetPath: assetPath,
        category: row['category'] as String?,
      );
    }).toList();
  }

  /// Mengambil distractor kata valid dari stage yang sama untuk opsi pilihan ganda
  Future<List<String>> getDistractorsForStage({
    required int stageId,
    required List<String> excludedWords,
    int count = 3,
  }) async {
    final db = await _dbHelper.database;
    if (stageId == 1) {
      const allLetters = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M'];
      return allLetters.where((l) => !excludedWords.contains(l)).take(count).toList();
    }

    final placeholders = List.filled(excludedWords.length, '?').join(',');
    final results = await db.query(
      'learning_words',
      columns: ['target_text'],
      where: 'stage_id = ? AND target_text NOT IN ($placeholders)',
      whereArgs: [stageId, ...excludedWords],
      orderBy: 'RANDOM()',
      limit: count,
    );

    return results.map((r) => r['target_text'] as String).toList();
  }
}
