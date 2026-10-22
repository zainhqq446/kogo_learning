import 'dart:math' as math;
import 'text_normalizer.dart';

/// Model hasil evaluasi pengucapan (Pronunciation Evaluation Result).
/// Murni data model independen tanpa ketergantungan pada Widget atau UI.
class SpeechEvaluationResult {
  /// Teks target yang seharusnya diucapkan.
  final String targetText;

  /// Teks mentah hasil pengenalan ucapan (ASR/Whisper).
  final String recognizedText;

  /// Teks target yang telah dinormalisasi.
  final String normalizedTarget;

  /// Teks hasil pengenalan yang telah dinormalisasi.
  /// (Teks recognized ASLI dipertahankan, TIDAK diubah paksa menjadi target).
  final String normalizedRecognized;

  /// Jarak Levenshtein / Edit Distance antara target dan recognized.
  final int editDistance;

  /// Skor kesamaan berbasis edit distance (rentang 0.0 - 1.0).
  /// Dihitung independen dari ASR confidence score.
  final double similarityScore;

  /// Persentase kesamaan (rentang 0.0 - 100.0%).
  final double similarityPercent;

  /// Tingkat keyakinan / confidence opsional dari engine ASR (0.0 - 1.0).
  final double? confidence;

  /// Status kebenaran pengucapan (evaluasi terpisah dari sekadar kemiripan).
  final bool isCorrect;

  /// Umpan balik pedagogis atau penjelasan hasil evaluasi untuk anak/guru.
  final String feedback;

  /// Durasi pengenalan atau proses evaluasi suara.
  final Duration duration;

  const SpeechEvaluationResult({
    required this.targetText,
    required this.recognizedText,
    required this.normalizedTarget,
    required this.normalizedRecognized,
    required this.editDistance,
    required this.similarityScore,
    required this.similarityPercent,
    this.confidence,
    required this.isCorrect,
    required this.feedback,
    required this.duration,
  });

  Map<String, dynamic> toMap() {
    return {
      'target_text': targetText,
      'recognized_text': recognizedText,
      'normalized_target': normalizedTarget,
      'normalized_recognized': normalizedRecognized,
      'edit_distance': editDistance,
      'similarity_score': similarityScore,
      'similarity_percent': similarityPercent,
      'confidence': confidence,
      'is_correct': isCorrect ? 1 : 0,
      'feedback': feedback,
      'duration_ms': duration.inMilliseconds,
    };
  }

  @override
  String toString() {
    return 'SpeechEvaluationResult(target: "$targetText", recognized: "$recognizedText", dist: $editDistance, sim: ${(similarityPercent).toStringAsFixed(1)}%, correct: $isCorrect)';
  }
}

/// Evaluator pengucapan kata dan fonem untuk pembelajaran anak usia dini.
/// Terpisah sepenuhnya dari engine Whisper maupun framework Widget Flutter.
class SpeechEvaluator {
  /// Ambang batas persentase kesamaan default untuk dianggap benar jika non-exact.
  /// Default 1.0 (exact match) untuk pengucapan kata/huruf dasar.
  final double correctnessThreshold;

  const SpeechEvaluator({
    this.correctnessThreshold = 1.0,
  });

  /// Mengevaluasi pengucapan anak terhadap target kata yang diharapkan.
  ///
  /// Prinsip inti:
  /// 1. Teks hasil pengenalan [recognizedText] TIDAK PERNAH diubah menjadi [targetText] secara paksa.
  /// 2. [confidence] berbeda dari [similarityScore].
  /// 3. [similarityScore] berbeda dari [isCorrect].
  /// 4. Jawaban salah tetap valid sebagai data log dan penelitian.
  /// 5. Kata yang berbeda seperti "KOPER" vs "KOPEL" harus menghasilkan perbedaan edit distance.
  SpeechEvaluationResult evaluate({
    required String targetText,
    required String recognizedText,
    double? confidence,
    Duration duration = Duration.zero,
  }) {
    final normalizedTarget = TextNormalizer.normalize(targetText);
    final normalizedRecognized = TextNormalizer.normalize(recognizedText);

    // Hitung jarak Levenshtein (Edit Distance)
    final editDist = computeEditDistance(normalizedTarget, normalizedRecognized);

    // Hitung similarityScore (0.0 sampai 1.0)
    final maxLen = math.max(normalizedTarget.length, normalizedRecognized.length);
    final double similarityScore;
    if (maxLen == 0) {
      similarityScore = (normalizedTarget.isEmpty && normalizedRecognized.isEmpty) ? 1.0 : 0.0;
    } else {
      similarityScore = (1.0 - (editDist / maxLen)).clamp(0.0, 1.0);
    }

    final similarityPercent = double.parse((similarityScore * 100.0).toStringAsFixed(2));

    // Evaluasi kebenaran
    final bool isCorrect;
    if (normalizedTarget.isEmpty) {
      isCorrect = normalizedRecognized.isEmpty;
    } else if (normalizedTarget == normalizedRecognized) {
      // Exact match selalu benar
      isCorrect = true;
    } else {
      // Jika tidak exact match, bandingkan dengan correctnessThreshold
      isCorrect = similarityScore >= correctnessThreshold && normalizedRecognized.isNotEmpty;
    }

    // Bangun umpan balik pedagogis
    final String feedback = _generateFeedback(
      normalizedTarget: normalizedTarget,
      normalizedRecognized: normalizedRecognized,
      editDistance: editDist,
      isCorrect: isCorrect,
    );

    return SpeechEvaluationResult(
      targetText: targetText,
      recognizedText: recognizedText,
      normalizedTarget: normalizedTarget,
      normalizedRecognized: normalizedRecognized,
      editDistance: editDist,
      similarityScore: similarityScore,
      similarityPercent: similarityPercent,
      confidence: confidence,
      isCorrect: isCorrect,
      feedback: feedback,
      duration: duration,
    );
  }

  /// Menghitung jarak Levenshtein standar (insertions, deletions, substitutions bernilai bobot 1).
  static int computeEditDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    final len1 = s1.length;
    final len2 = s2.length;

    List<int> previousRow = List<int>.generate(len2 + 1, (i) => i);
    List<int> currentRow = List<int>.filled(len2 + 1, 0);

    for (int i = 0; i < len1; i++) {
      currentRow[0] = i + 1;
      final char1 = s1.codeUnitAt(i);

      for (int j = 0; j < len2; j++) {
        final char2 = s2.codeUnitAt(j);
        final cost = (char1 == char2) ? 0 : 1;

        currentRow[j + 1] = math.min(
          currentRow[j] + 1, // Insertion
          math.min(
            previousRow[j + 1] + 1, // Deletion
            previousRow[j] + cost, // Substitution
          ),
        );
      }

      final temp = previousRow;
      previousRow = currentRow;
      currentRow = temp;
    }

    return previousRow[len2];
  }

  String _generateFeedback({
    required String normalizedTarget,
    required String normalizedRecognized,
    required int editDistance,
    required bool isCorrect,
  }) {
    if (normalizedRecognized.isEmpty) {
      return 'Suara belum terdengar. Coba ucapkan lagi lebih jelas ya.';
    }

    if (isCorrect) {
      return 'Hebat! Pengucapan sudah tepat. 🎉';
    }

    if (editDistance == 1) {
      return 'Hampir tepat! Perhatikan kembali bunyi pengucapannya.';
    }

    return 'Belum tepat. Ayo coba ucapkan sekali lagi.';
  }
}