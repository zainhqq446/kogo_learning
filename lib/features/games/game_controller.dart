import 'package:flutter/foundation.dart';

import '../../core/curriculum/curriculum.dart';
import '../../core/curriculum/vocabulary.dart';
import '../../data/progress_repository.dart';

/// ViewModel satu sesi permainan: mencatat setiap jawaban (AnswerLogs),
/// menghitung jawaban benar pada percobaan pertama, lalu menyimpan bintang
/// (Stars) dan hadiah (Rewards) ketika permainan selesai.
class GameController {
  GameController({required this.node, required this.learnerId, ProgressRepository? progress}) : _progress = progress ?? ProgressRepository();

  final LearningNode node;
  final int learnerId;
  final ProgressRepository _progress;

  int? _sessionId;
  Future<void>? _starting;
  final Map<int, int> _attempts = {};
  final Map<int, int> _tries = {};
  final Set<int> _solved = {};
  int _firstTryCorrect = 0;
  bool _finished = false;

  int get totalItems => node.unit.items.length;
  int get firstTryCorrect => _firstTryCorrect;
  int attemptsFor(int itemIndex) => _attempts[itemIndex] ?? 0;

  Future<void> start() => _starting ??= () async {
    try {
      _sessionId = await _progress.startSession(learnerId: learnerId, node: node);
    } catch (e) {
      debugPrint('[GameController] gagal memulai sesi: $e');
    }
  }();

  /// Mencatat satu jawaban. Mengembalikan nomor percobaan (log) untuk item itu.
  ///
  /// [countsAsTry] `false` untuk kejadian yang bukan kesalahan anak (tidak ada
  /// suara terdengar, gangguan layanan) — tetap dicatat untuk metrik System
  /// Error Rate, tetapi tidak mengurangi peluang bintang.
  Future<int> record({
    required int itemIndex,
    required VocabItem target,
    required String answer,
    required bool correct,
    double? similarity,
    int? responseMs,
    String? sttError,
    bool countsAsTry = true,
  }) async {
    final attempt = (_attempts[itemIndex] ?? 0) + 1;
    _attempts[itemIndex] = attempt;
    if (countsAsTry || correct) {
      final tries = (_tries[itemIndex] ?? 0) + 1;
      _tries[itemIndex] = tries;
      if (correct && !_solved.contains(itemIndex)) {
        _solved.add(itemIndex);
        if (tries == 1) _firstTryCorrect++;
      }
    }
    await start();
    final sessionId = _sessionId;
    if (sessionId != null) {
      try {
        await _progress.logAttempt(
          sessionId: sessionId,
          learnerId: learnerId,
          game: node.game,
          target: target.text,
          answer: answer,
          isCorrect: correct,
          attemptNumber: attempt,
          similarity: similarity,
          responseMs: responseMs,
          sttError: sttError,
        );
      } catch (e) {
        debugPrint('[GameController] gagal mencatat jawaban: $e');
      }
    }
    return attempt;
  }

  /// Menyelesaikan permainan; `null` bila penyimpanan gagal.
  Future<GameResult?> finish() async {
    if (_finished) return null;
    _finished = true;
    await start();
    final sessionId = _sessionId;
    if (sessionId == null) return null;
    try {
      return await _progress.completeSession(sessionId: sessionId, learnerId: learnerId, node: node, totalItems: totalItems, firstTryCorrect: _firstTryCorrect);
    } catch (e) {
      debugPrint('[GameController] gagal menyimpan hasil: $e');
      return null;
    }
  }

  Future<void> abandon() async {
    if (_finished) return;
    _finished = true;
    await start();
    final sessionId = _sessionId;
    if (sessionId == null) return;
    try {
      await _progress.abandonSession(sessionId);
    } catch (_) {}
  }
}
