import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import '../../../../data/models/lesson_model.dart';
import '../../../../data/models/question_model.dart';
import '../../../../data/repositories/answer_log_repository.dart';
import '../../../../data/repositories/question_repository.dart';
import '../../../../services/audio/bgm_manager.dart';
import '../../../../services/audio/kogo_voice_manager.dart';
import '../../../../services/audio/voice_message_context.dart';
import '../../../../services/auth/session_manager.dart';

/// Model representasi tile huruf dengan ID unik agar huruf duplikat tidak bentrok
class AssemblyTile {
  final String id;
  final String char;

  const AssemblyTile({
    required this.id,
    required this.char,
  });
}

/// Halaman Game Susun Kata (Word Assembly)
/// Anak menyusun huruf-huruf atau token kata acak ke dalam slot jawaban kosong.
/// Mendukung kata berulang/tanda hubung seperti 'lumba-lumba', 'kupu-kupu'.
class WordAssemblyPage extends StatefulWidget {
  final LessonModel lesson;
  final List<QuestionModel>? questionsOverride;
  final VoidCallback? onCompleted;

  const WordAssemblyPage({
    super.key,
    required this.lesson,
    this.questionsOverride,
    this.onCompleted,
  });

  @override
  State<WordAssemblyPage> createState() => _WordAssemblyPageState();
}

class _WordAssemblyPageState extends State<WordAssemblyPage> {
  final QuestionRepository _questionRepository = QuestionRepository();
  final AnswerLogRepository _answerLogRepository = AnswerLogRepository();
  final SessionManager _sessionManager = SessionManager.instance;

  late Future<List<QuestionModel>> _questionsFuture;
  int _currentIndex = 0;

  // State untuk kata saat ini
  List<AssemblyTile> _targetTiles = [];
  List<AssemblyTile> _availableTiles = [];
  List<AssemblyTile> _placedTiles = [];

  bool? _isCorrect;
  bool _isAnswered = false;
  bool _isAdvancing = false; // anti double-tap
  Timer? _introTimer;

  @override
  void initState() {
    super.initState();
    final questionsSource = widget.questionsOverride != null
        ? Future.value(widget.questionsOverride!)
        : _questionRepository.getByLessonId(widget.lesson.id!);

    _questionsFuture = questionsSource.then((questions) {
      if (questions.isNotEmpty) {
        _introTimer = Timer(const Duration(milliseconds: 300), () {
          if (mounted && _currentIndex == 0) {
            KogoVoiceManager.instance.playGameIntro('word_assembly');
          }
        });
      }
      return questions;
    });
  }

  @override
  void dispose() {
    _introTimer?.cancel();
    KogoVoiceManager.instance.stop();
    super.dispose();
  }

  /// Tokenisasi kata target menjadi list AssemblyTile dengan id unik.
  /// Mempertahankan huruf ejaan dan tanda hubung '-' jika ada.
  void _prepareTiles(QuestionModel question) {
    if (_targetTiles.isNotEmpty) return;

    final rawTarget = question.targetText.trim();
    final List<AssemblyTile> tiles = [];

    // Jika kata berulang dengan tanda hubung seperti lumba-lumba
    // Kita pecah menjadi huruf-huruf individual dan tile tanda hubung
    for (int i = 0; i < rawTarget.length; i++) {
      final ch = rawTarget[i];
      tiles.add(AssemblyTile(id: 'tile_${i}_$ch', char: ch));
    }

    _targetTiles = tiles;

    // Acak kepingan huruf (pastikan tidak sama dengan urutan awal jika panjang > 1)
    final shuffled = List<AssemblyTile>.from(tiles);
    if (shuffled.length > 1) {
      final random = Random(question.id ?? (question.orderIndex + 77));
      for (int i = 0; i < 10; i++) {
        shuffled.shuffle(random);
        final currentString = shuffled.map((t) => t.char).join();
        if (currentString != rawTarget) {
          break;
        }
      }
    }

    _availableTiles = shuffled;
    _placedTiles = [];
  }

  void _onTileSelected(AssemblyTile tile, QuestionModel question) {
    if (_isAnswered) return;

    setState(() {
      _availableTiles.removeWhere((t) => t.id == tile.id);
      _placedTiles.add(tile);
    });

    BgmManager.instance.playSfx('correct/correct_01.mp3');

    // Jika seluruh slot telah terisi, otomatis evaluasi
    if (_placedTiles.length == _targetTiles.length) {
      _evaluateAnswer(question);
    }
  }

  void _undoTile(int placedIndex) {
    if (_isAnswered) return;
    setState(() {
      final removed = _placedTiles.removeAt(placedIndex);
      _availableTiles.add(removed);
    });
  }

  void _resetSelection() {
    if (_isAnswered) return;
    setState(() {
      _availableTiles.addAll(_placedTiles);
      _placedTiles.clear();
    });
  }

  Future<void> _evaluateAnswer(QuestionModel question) async {
    final assembled = _placedTiles.map((t) => t.char).join();
    final target = question.targetText.trim();
    final isCorrect = assembled.toLowerCase() == target.toLowerCase();

    setState(() {
      _isCorrect = isCorrect;
      _isAnswered = true;
    });

    if (isCorrect) {
      BgmManager.instance.playSfx('correct/correct_02.mp3');
    } else {
      BgmManager.instance.playSfx('incorrect/retry_01.mp3');
    }

    final voiceContext = VoiceMessageContext(
      stage: widget.lesson.stageId,
      lesson: widget.lesson.title,
      activity: 'word_assembly',
      questionIndex: _currentIndex,
      targetWord: question.targetText,
      attemptNumber: 1,
      isCorrect: isCorrect,
      similarity: isCorrect ? 100.0 : 0.0,
      recognizedText: assembled,
    );
    KogoVoiceManager.instance.playEvaluationFeedback(voiceContext);

    final childId = _sessionManager.currentChild?.id ?? 1;
    final deviceId = _sessionManager.currentDevice?.id ?? 1;
    final sessionId = _sessionManager.currentSession?.id ?? 1;

    try {
      await _answerLogRepository.logAnswer(
        childId: childId,
        deviceId: deviceId,
        sessionId: sessionId,
        questionId: question.id ?? 1,
        targetText: question.targetText,
        recognizedText: assembled,
        normalizedTarget: question.normalizedTarget,
        normalizedRecognized: assembled.toLowerCase().trim(),
        editDistance: isCorrect ? 0 : 1,
        similarityScore: isCorrect ? 1.0 : 0.0,
        similarityPercent: isCorrect ? 100.0 : 0.0,
        isCorrect: isCorrect,
        provider: 'word_assembly',
        locale: 'id_ID',
      );
    } catch (e) {
      debugPrint('[WordAssemblyPage] Log answer error: $e');
    }
  }

  void _retryQuestion() {
    setState(() {
      _availableTiles.addAll(_placedTiles);
      _placedTiles.clear();
      _isCorrect = null;
      _isAnswered = false;
    });
  }

  void _nextQuestion(List<QuestionModel> questions) {
    if (_isAdvancing) return;
    _isAdvancing = true;

    if (_currentIndex < questions.length - 1) {
      KogoVoiceManager.instance.playTransition(VoiceMessageContext(
        stage: widget.lesson.stageId,
        lesson: widget.lesson.title,
        activity: 'word_assembly',
        questionIndex: _currentIndex,
        totalQuestions: questions.length,
        targetWord: questions[_currentIndex].targetText,
      ));
      setState(() {
        _currentIndex++;
        _targetTiles = [];
        _availableTiles = [];
        _placedTiles = [];
        _isCorrect = null;
        _isAnswered = false;
        _isAdvancing = false;
      });
    } else {
      _showCompletionDialog();
    }
  }

  void _showCompletionDialog() {
    KogoVoiceManager.instance.playCompletion(VoiceMessageContext(
      stage: widget.lesson.stageId,
      lesson: widget.lesson.title,
      activity: 'word_assembly',
      isCompleted: true,
      targetWord: '',
    ));

    if (widget.onCompleted != null) {
      widget.onCompleted!();
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Luar Biasa! 🔤'),
          content: const Text('Kamu berhasil menyusun semua kata!'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('Selesai'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0FDF4),
      appBar: AppBar(
        title: const Text(
          'Susun Kata 🔤',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder<List<QuestionModel>>(
        future: _questionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                'Tidak ada data soal untuk permainan ini.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          final questions = snapshot.data!;
          final question = questions[_currentIndex];
          _prepareTiles(question);

          return SafeArea(
            child: Column(
              children: [
                // Indikator Progres
                LinearProgressIndicator(
                  value: (_currentIndex + 1) / questions.length,
                  backgroundColor: const Color(0xFFD1FAE5),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF059669)),
                  minHeight: 6,
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Kata ${_currentIndex + 1} dari ${questions.length}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF065F46),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.volume_up_rounded, color: Color(0xFF059669)),
                        tooltip: 'Dengar petunjuk suara',
                        onPressed: () {
                          KogoVoiceManager.instance.playWordExample(question.targetText);
                        },
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Gambar Kata Target (jika ada)
                        if (question.imagePath != null && question.imagePath!.isNotEmpty)
                          Container(
                            height: 140,
                            width: 140,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.asset(
                                question.imagePath!,
                                fit: BoxFit.contain,
                                errorBuilder: (ctx, err, stack) => const Icon(
                                  Icons.image_not_supported_rounded,
                                  size: 48,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ),

                        const Text(
                          'Ayo susun huruf-hurufnya menjadi kata yang benar!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // SLOT JAWABAN YANG SEDANG DISUSUN
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _isAnswered
                                  ? (_isCorrect == true ? const Color(0xFF10B981) : const Color(0xFFEF4444))
                                  : const Color(0xFFD1D5DB),
                              width: 2,
                            ),
                          ),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: List.generate(_targetTiles.length, (slotIdx) {
                              final hasTile = slotIdx < _placedTiles.length;
                              final tile = hasTile ? _placedTiles[slotIdx] : null;

                              return InkWell(
                                onTap: hasTile && !_isAnswered
                                    ? () => _undoTile(slotIdx)
                                    : null,
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  width: 44,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: hasTile ? const Color(0xFFECFDF5) : const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: hasTile
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFFCBD5E1),
                                      width: hasTile ? 2 : 1,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      hasTile ? tile!.char.toUpperCase() : '',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: tile?.char == '-'
                                            ? const Color(0xFF047857)
                                            : const Color(0xFF065F46),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Tombol Reset / Undo
                        if (_placedTiles.isNotEmpty && !_isAnswered)
                          TextButton.icon(
                            onPressed: _resetSelection,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Ulangi Susunan'),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFEF4444),
                            ),
                          ),

                        const SizedBox(height: 24),

                        // KEPINGAN HURUF PILIHAN ACAK
                        const Text(
                          'Pilih Huruf:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4B5563),
                          ),
                        ),
                        const SizedBox(height: 12),

                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          alignment: WrapAlignment.center,
                          children: _availableTiles.map((tile) {
                            return ElevatedButton(
                              onPressed: _isAnswered ? null : () => _onTileSelected(tile, question),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF34D399),
                                foregroundColor: Colors.white,
                                elevation: 3,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                minimumSize: const Size(48, 56),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              ),
                              child: Text(
                                tile.char.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 28),

                        // FEEDBACK DAN TOMBOL LANJUT
                        if (_isAnswered) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _isCorrect == true ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _isCorrect == true ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                  color: _isCorrect == true ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                  size: 32,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _isCorrect == true
                                        ? 'Hebat! Kata "${question.targetText}" tersusun dengan tepat!'
                                        : 'Belum tepat. Coba lagi yuk!',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: _isCorrect == true
                                          ? const Color(0xFF065F46)
                                          : const Color(0xFF991B1B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              if (_isCorrect != true)
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _retryQuestion,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFDC2626),
                                      side: const BorderSide(color: Color(0xFFDC2626)),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    child: const Text('Coba Lagi', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              if (_isCorrect != true) const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => _nextQuestion(questions),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: Text(
                                    _currentIndex < questions.length - 1 ? 'Lanjut ⏩' : 'Selesai 🎉',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
