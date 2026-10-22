/// Konteks lengkap pembelajaran anak per soal untuk pemilihan pesan suara (VoiceMessageContext).
/// Memuat seluruh metadata aktivitas, progres, attempt, kemiripan ucapan, dan status selebrasi.
class VoiceMessageContext {
  final dynamic stage;
  final String lesson;
  final String activity;
  final int questionIndex;
  final int totalQuestions;
  final String targetWord;
  final int attemptNumber;
  final double similarity;
  final bool? isCorrect;
  final int streak;
  final bool isCompleted;
  final bool isEmptyRecognition;
  final String? recognizedText;

  const VoiceMessageContext({
    this.stage = 1,
    this.lesson = '',
    this.activity = 'listen_repeat',
    this.questionIndex = 0,
    this.totalQuestions = 5,
    required this.targetWord,
    this.attemptNumber = 1,
    this.similarity = 0.0,
    this.isCorrect,
    this.streak = 0,
    this.isCompleted = false,
    this.isEmptyRecognition = false,
    this.recognizedText,
  });

  /// Progres dalam stage/lesson saat ini (0.0 sampai 1.0)
  double get progress {
    if (totalQuestions <= 0) return 0.0;
    return (questionIndex + 1) / totalQuestions;
  }

  /// Menandakan apakah ini adalah soal pertama
  bool get isFirstQuestion => questionIndex == 0;

  /// Menandakan apakah ini adalah soal terakhir dalam sesi
  bool get isLastQuestion => totalQuestions > 0 && questionIndex >= totalQuestions - 1;

  /// Menandakan apakah pertanyaan sudah di atas 50% perjalanan
  bool get isNearEnd => totalQuestions > 2 && (questionIndex + 1) >= (totalQuestions - 1);

  VoiceMessageContext copyWith({
    dynamic stage,
    String? lesson,
    String? activity,
    int? questionIndex,
    int? totalQuestions,
    String? targetWord,
    int? attemptNumber,
    double? similarity,
    bool? isCorrect,
    int? streak,
    bool? isCompleted,
    bool? isEmptyRecognition,
    String? recognizedText,
  }) {
    return VoiceMessageContext(
      stage: stage ?? this.stage,
      lesson: lesson ?? this.lesson,
      activity: activity ?? this.activity,
      questionIndex: questionIndex ?? this.questionIndex,
      totalQuestions: totalQuestions ?? this.totalQuestions,
      targetWord: targetWord ?? this.targetWord,
      attemptNumber: attemptNumber ?? this.attemptNumber,
      similarity: similarity ?? this.similarity,
      isCorrect: isCorrect ?? this.isCorrect,
      streak: streak ?? this.streak,
      isCompleted: isCompleted ?? this.isCompleted,
      isEmptyRecognition: isEmptyRecognition ?? this.isEmptyRecognition,
      recognizedText: recognizedText ?? this.recognizedText,
    );
  }
}
