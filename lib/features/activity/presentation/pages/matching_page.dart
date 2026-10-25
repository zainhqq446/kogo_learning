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

/// Model item gambar untuk kolom kiri
class MatchingImageItem {
  final int id;
  final String word;
  final String imagePath;

  const MatchingImageItem({
    required this.id,
    required this.word,
    required this.imagePath,
  });
}

/// Model item kata untuk kolom kanan
class MatchingWordItem {
  final int id;
  final String word;

  const MatchingWordItem({
    required this.id,
    required this.word,
  });
}

/// Halaman Game Matching Object Sejati (Mencocokkan Gambar dengan Kata)
/// Menampilkan 6 gambar pada kolom kiri dan 6 kata teracak pada kolom kanan.
/// Setiap gambar memiliki tepat 1 pasangan kata yang valid.
class MatchingPage extends StatefulWidget {
  final LessonModel lesson;
  final List<QuestionModel>? questionsOverride;
  final VoidCallback? onCompleted;

  const MatchingPage({
    super.key,
    required this.lesson,
    this.questionsOverride,
    this.onCompleted,
  });

  @override
  State<MatchingPage> createState() => _MatchingPageState();
}

class _MatchingPageState extends State<MatchingPage> {
  final QuestionRepository _questionRepository = QuestionRepository();
  final AnswerLogRepository _answerLogRepository = AnswerLogRepository();
  final SessionManager _sessionManager = SessionManager.instance;

  late Future<List<QuestionModel>> _questionsFuture;

  List<MatchingImageItem> _imageItems = [];
  List<MatchingWordItem> _shuffledWordItems = [];

  // Pilihan saat ini
  int? _selectedImageId;
  int? _selectedWordId;

  // Set ID pasangan yang sudah berhasil dicocokkan
  final Set<int> _matchedIds = {};

  bool _isEvaluating = false;
  bool? _lastMatchSuccess;
  int _streak = 0;
  Timer? _introTimer;

  @override
  void initState() {
    super.initState();
    final questionsSource = widget.questionsOverride != null
        ? Future.value(widget.questionsOverride!)
        : _questionRepository.getByLessonId(widget.lesson.id!);

    _questionsFuture = questionsSource.then((questions) {
      if (questions.isNotEmpty) {
        _initMatchingItems(questions);
        _introTimer = Timer(const Duration(milliseconds: 300), () {
          if (mounted) {
            KogoVoiceManager.instance.playGameIntro('matching');
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

  void _initMatchingItems(List<QuestionModel> questions) {
    // Ambil maksimal 6 pertanyaan untuk dicocokkan
    final pool = questions.take(6).toList();

    _imageItems = pool.map((q) {
      return MatchingImageItem(
        id: q.id ?? pool.indexOf(q),
        word: q.targetText,
        imagePath: q.imagePath ?? '',
      );
    }).toList();

    final wordList = pool.map((q) {
      return MatchingWordItem(
        id: q.id ?? pool.indexOf(q),
        word: q.targetText,
      );
    }).toList();

    // Acak urutan kolom kanan secara deterministik atau acak
    final random = Random();
    for (int i = 0; i < 5; i++) {
      wordList.shuffle(random);
      // Pastikan urutan tidak persis sama dengan kolom gambar jika jumlah > 1
      if (wordList.length > 1 && wordList.first.id != _imageItems.first.id) {
        break;
      }
    }

    _shuffledWordItems = wordList;
    _matchedIds.clear();
    _selectedImageId = null;
    _selectedWordId = null;
  }

  void _onImageTapped(MatchingImageItem item) {
    if (_isEvaluating || _matchedIds.contains(item.id)) return;

    setState(() {
      _selectedImageId = item.id;
      _lastMatchSuccess = null;
    });

    if (_selectedWordId != null) {
      _checkMatch();
    }
  }

  void _onWordTapped(MatchingWordItem item) {
    if (_isEvaluating || _matchedIds.contains(item.id)) return;

    setState(() {
      _selectedWordId = item.id;
      _lastMatchSuccess = null;
    });

    if (_selectedImageId != null) {
      _checkMatch();
    }
  }

  Future<void> _checkMatch() async {
    if (_selectedImageId == null || _selectedWordId == null) return;

    final isCorrect = _selectedImageId == _selectedWordId;
    final matchedWord = _imageItems.firstWhere((img) => img.id == _selectedImageId).word;

    setState(() {
      _isEvaluating = true;
      _lastMatchSuccess = isCorrect;
    });

    if (isCorrect) {
      _streak++;
      _matchedIds.add(_selectedImageId!);
      BgmManager.instance.playSfx('correct/correct_01.mp3');

      final voiceContext = VoiceMessageContext(
        stage: widget.lesson.stageId,
        lesson: widget.lesson.title,
        activity: 'matching',
        questionIndex: _matchedIds.length - 1,
        targetWord: matchedWord,
        attemptNumber: 1,
        isCorrect: true,
        similarity: 100.0,
        streak: _streak,
        recognizedText: matchedWord,
      );
      KogoVoiceManager.instance.playEvaluationFeedback(voiceContext);

      // Simpan log jawaban ke SQLite
      _logAnswer(questionId: _selectedImageId!, word: matchedWord, isCorrect: true);
    } else {
      _streak = 0;
      BgmManager.instance.playSfx('incorrect/retry_01.mp3');

      final voiceContext = VoiceMessageContext(
        stage: widget.lesson.stageId,
        lesson: widget.lesson.title,
        activity: 'matching',
        targetWord: matchedWord,
        attemptNumber: 1,
        isCorrect: false,
        similarity: 0.0,
        streak: 0,
      );
      KogoVoiceManager.instance.playEvaluationFeedback(voiceContext);

      _logAnswer(questionId: _selectedImageId!, word: matchedWord, isCorrect: false);
    }

    await Future<void>.delayed(const Duration(milliseconds: 600));

    if (mounted) {
      setState(() {
        _selectedImageId = null;
        _selectedWordId = null;
        _isEvaluating = false;
        _lastMatchSuccess = null;
      });

      // Jika seluruh pasangan telah selesai
      if (_matchedIds.length == _imageItems.length && _imageItems.isNotEmpty) {
        _onAllMatchesCompleted();
      }
    }
  }

  Future<void> _logAnswer({
    required int questionId,
    required String word,
    required bool isCorrect,
  }) async {
    final childId = _sessionManager.currentChild?.id ?? 1;
    final deviceId = _sessionManager.currentDevice?.id ?? 1;
    final sessionId = _sessionManager.currentSession?.id ?? 1;

    try {
      await _answerLogRepository.logAnswer(
        childId: childId,
        deviceId: deviceId,
        sessionId: sessionId,
        questionId: questionId,
        targetText: word,
        recognizedText: word,
        normalizedTarget: word.toLowerCase().trim(),
        normalizedRecognized: word.toLowerCase().trim(),
        editDistance: isCorrect ? 0 : 1,
        similarityScore: isCorrect ? 1.0 : 0.0,
        similarityPercent: isCorrect ? 100.0 : 0.0,
        isCorrect: isCorrect,
        provider: 'matching_object',
        locale: 'id_ID',
      );
    } catch (e) {
      debugPrint('[MatchingPage] Log answer error: $e');
    }
  }

  void _onAllMatchesCompleted() {
    BgmManager.instance.playSfx('completion/complete_01.mp3');
    KogoVoiceManager.instance.playCompletion(VoiceMessageContext(
      stage: widget.lesson.stageId,
      lesson: widget.lesson.title,
      activity: 'matching',
      isCompleted: true,
      targetWord: '',
    ));
  }

  void _finishActivity() {
    if (widget.onCompleted != null) {
      widget.onCompleted!();
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Luar Biasa! 🧩'),
          content: const Text('Kamu berhasil mencocokkan semua gambar dengan katanya!'),
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
    final bool allDone = _imageItems.isNotEmpty && _matchedIds.length == _imageItems.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Cocokkan Gambar & Kata 🧩',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF6366F1),
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
                'Tidak ada data gambar untuk dicocokkan.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          return SafeArea(
            child: Column(
              children: [
                // Header progres pencocokan
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: Colors.white,
                  child: Row(
                    children: [
                      const Text(
                        'Tercocokkan:',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_matchedIds.length} / ${_imageItems.length}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4F46E5),
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      if (_lastMatchSuccess != null)
                        Text(
                          _lastMatchSuccess == true ? '🎉 Pasangan Benar!' : '❌ Belum Pas',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _lastMatchSuccess == true ? const Color(0xFF059669) : const Color(0xFFDC2626),
                          ),
                        ),
                    ],
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Sentuh gambar di kiri, lalu sentuh kata yang cocok di kanan!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                  ),
                ),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // KOLOM KIRI: 6 GAMBAR
                        Expanded(
                          child: ListView.separated(
                            itemCount: _imageItems.length,
                            separatorBuilder: (c, i) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final imgItem = _imageItems[index];
                              final isMatched = _matchedIds.contains(imgItem.id);
                              final isSelected = _selectedImageId == imgItem.id;

                              return InkWell(
                                onTap: () => _onImageTapped(imgItem),
                                borderRadius: BorderRadius.circular(12),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: isMatched
                                        ? const Color(0xFFDCFCE7)
                                        : (isSelected ? const Color(0xFFEEF2FF) : Colors.white),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isMatched
                                          ? const Color(0xFF10B981)
                                          : (isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0)),
                                      width: isSelected || isMatched ? 2.5 : 1.5,
                                    ),
                                    boxShadow: [
                                      if (isSelected)
                                        BoxShadow(
                                          color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.all(6),
                                  child: Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: SizedBox(
                                          width: 52,
                                          height: 52,
                                          child: imgItem.imagePath.isNotEmpty
                                              ? Image.asset(
                                                  imgItem.imagePath,
                                                  fit: BoxFit.contain,
                                                  errorBuilder: (ctx, err, stack) => const Icon(
                                                    Icons.image_rounded,
                                                    color: Colors.grey,
                                                  ),
                                                )
                                              : const Icon(Icons.image_rounded, color: Colors.grey),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (isMatched)
                                        const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 22)
                                      else if (isSelected)
                                        const Icon(Icons.touch_app_rounded, color: Color(0xFF4F46E5), size: 20),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        const SizedBox(width: 12),

                        // KOLOM KANAN: 6 KATA (TERACAK)
                        Expanded(
                          child: ListView.separated(
                            itemCount: _shuffledWordItems.length,
                            separatorBuilder: (c, i) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final wordItem = _shuffledWordItems[index];
                              final isMatched = _matchedIds.contains(wordItem.id);
                              final isSelected = _selectedWordId == wordItem.id;

                              return InkWell(
                                onTap: () => _onWordTapped(wordItem),
                                borderRadius: BorderRadius.circular(12),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: isMatched
                                        ? const Color(0xFFDCFCE7)
                                        : (isSelected ? const Color(0xFFEEF2FF) : Colors.white),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isMatched
                                          ? const Color(0xFF10B981)
                                          : (isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0)),
                                      width: isSelected || isMatched ? 2.5 : 1.5,
                                    ),
                                    boxShadow: [
                                      if (isSelected)
                                        BoxShadow(
                                          color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          wordItem.word,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: isMatched
                                                ? const Color(0xFF065F46)
                                                : (isSelected ? const Color(0xFF4338CA) : const Color(0xFF1E293B)),
                                          ),
                                        ),
                                      ),
                                      if (isMatched)
                                        const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 22)
                                      else if (isSelected)
                                        const Icon(Icons.touch_app_rounded, color: Color(0xFF4F46E5), size: 20),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // TOMBOL LANJUT KETIKA SEMUA TERCOCOKKAN
                if (allDone)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _finishActivity,
                        icon: const Icon(Icons.celebration_rounded),
                        label: const Text('Lanjut ke Aktivitas Berikutnya ⏩', style: TextStyle(fontSize: 16)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 4,
                        ),
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
