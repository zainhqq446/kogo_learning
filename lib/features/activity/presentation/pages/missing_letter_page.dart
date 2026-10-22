import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import '../../../../data/models/lesson_model.dart';
import '../../../../data/models/question_model.dart';
import '../../../../data/repositories/answer_log_repository.dart';
import '../../../../data/repositories/question_repository.dart';
import '../../../../services/audio/kogo_voice_manager.dart';
import '../../../../services/audio/voice_message_context.dart';
import '../../../../services/auth/session_manager.dart';

/// Halaman Game "Missing Letter" (Mengisi Huruf yang Kurang)
/// Mengadopsi desain prototipe Figma MissingLetterActivity.tsx dengan animasi ramah anak dan suara interaktif.
class MissingLetterPage extends StatefulWidget {
  final LessonModel lesson;

  const MissingLetterPage({
    super.key,
    required this.lesson,
  });

  @override
  State<MissingLetterPage> createState() => _MissingLetterPageState();
}

class _MissingLetterPageState extends State<MissingLetterPage> with SingleTickerProviderStateMixin {
  final QuestionRepository _questionRepository = QuestionRepository();
  final AnswerLogRepository _answerLogRepository = AnswerLogRepository();
  final SessionManager _sessionManager = SessionManager.instance;

  late Future<List<QuestionModel>> _questionsFuture;
  int _currentIndex = 0;

  String? _selectedLetter;
  bool? _isCorrect;
  bool _isAnswered = false;

  int _missingCharIndex = 1;
  String _correctLetter = '';
  List<String> _letterOptions = [];

  late final AnimationController _bounceController;

  Timer? _promptTimer;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    // Jalankan animasi hanya jika ada ticker normal
    _bounceController.forward();

    _questionsFuture = _questionRepository.getByLessonId(widget.lesson.id!).then((questions) {
      if (questions.isNotEmpty) {
        _promptTimer = Timer(const Duration(milliseconds: 300), () {
          if (mounted && _currentIndex == 0) {
            KogoVoiceManager.instance.playGameIntro('missing_letter');
          }
        });
      }
      return questions;
    });
  }

  @override
  void dispose() {
    _promptTimer?.cancel();
    _bounceController.dispose();
    KogoVoiceManager.instance.stop();
    super.dispose();
  }

  void _speakPrompt(QuestionModel question) {
    KogoVoiceManager.instance.playWordExample(question.targetText);
  }

  void _prepareMissingLetter(QuestionModel question) {
    if (_letterOptions.isNotEmpty) return;

    final word = question.targetText.toUpperCase();
    if (word.isEmpty) {
      _missingCharIndex = 0;
      _correctLetter = 'A';
      _letterOptions = ['A', 'B', 'C', 'D'];
      return;
    }

    // Pilih index yang dihilangkan secara deterministik (biasanya huruf vokal atau huruf tengah)
    final vowels = ['A', 'I', 'U', 'E', 'O'];
    int chosenIndex = -1;
    for (int i = 0; i < word.length; i++) {
      if (vowels.contains(word[i])) {
        chosenIndex = i;
        break;
      }
    }
    if (chosenIndex == -1) {
      chosenIndex = word.length > 1 ? 1 : 0;
    }

    _missingCharIndex = chosenIndex;
    _correctLetter = word[chosenIndex];

    // Opsi huruf pilihan (termasuk huruf yang benar)
    final optionsSet = <String>{_correctLetter};
    final random = Random(question.id ?? question.orderIndex);

    // Tambah huruf vokal/konsonan pengecoh
    final allAlphabet = ['A', 'B', 'E', 'I', 'K', 'L', 'M', 'N', 'O', 'P', 'R', 'S', 'T', 'U'];
    allAlphabet.shuffle(random);
    for (final char in allAlphabet) {
      if (optionsSet.length >= 4) break;
      optionsSet.add(char);
    }

    final list = optionsSet.toList();
    list.shuffle(random);
    _letterOptions = list;
  }

  String _getWordEmoji(String word) {
    final lower = word.toLowerCase();
    if (lower.contains('apel')) return '🍎';
    if (lower.contains('buku')) return '📖';
    if (lower.contains('bola')) return '⚽';
    if (lower.contains('meja')) return '🪑';
    if (lower.contains('sapi')) return '🐮';
    if (lower.contains('kaki')) return '🦶';
    if (lower.contains('sepatu')) return '👟';
    if (lower.contains('kereta')) return '🚂';
    if (lower.contains('kelinci')) return '🐰';
    if (lower.contains('kamera')) return '📷';
    if (lower.contains('matahari')) return '☀️';
    if (lower.contains('helikopter')) return '🚁';
    return '🌟';
  }

  int _streak = 0;

  Future<void> _selectLetter(String letter, QuestionModel question) async {
    if (_isAnswered) return;

    final isCorrect = letter.toUpperCase() == _correctLetter.toUpperCase();

    if (isCorrect) {
      _streak++;
    } else {
      _streak = 0;
    }

    setState(() {
      _selectedLetter = letter;
      _isCorrect = isCorrect;
      _isAnswered = true;
    });

    final voiceContext = VoiceMessageContext(
      stage: widget.lesson.stageId,
      lesson: widget.lesson.title,
      activity: widget.lesson.lessonType,
      questionIndex: _currentIndex,
      targetWord: question.targetText,
      attemptNumber: 1,
      isCorrect: isCorrect,
      similarity: isCorrect ? 100.0 : 0.0,
      streak: _streak,
      recognizedText: letter,
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
        questionId: question.id!,
        targetText: question.targetText,
        recognizedText: letter,
        normalizedTarget: _correctLetter.toLowerCase(),
        normalizedRecognized: letter.toLowerCase(),
        editDistance: isCorrect ? 0 : 1,
        similarityScore: isCorrect ? 1.0 : 0.0,
        similarityPercent: isCorrect ? 100.0 : 0.0,
        isCorrect: isCorrect,
        provider: 'missing_letter_choice',
        locale: 'id_ID',
      );
    } catch (e) {
      debugPrint('[MissingLetterPage] Log answer error: $e');
    }
  }

  void _nextQuestion(List<QuestionModel> questions) {
    if (_currentIndex < questions.length - 1) {
      KogoVoiceManager.instance.playTransition(VoiceMessageContext(
        stage: widget.lesson.stageId,
        lesson: widget.lesson.title,
        activity: widget.lesson.lessonType,
        questionIndex: _currentIndex,
        totalQuestions: questions.length,
        targetWord: questions[_currentIndex].targetText,
      ));
      setState(() {
        _currentIndex++;
        _selectedLetter = null;
        _isCorrect = null;
        _isAnswered = false;
        _letterOptions = [];
      });
      _speakPrompt(questions[_currentIndex]);
    } else {
      _showCompletionDialog();
    }
  }

  void _showCompletionDialog() {
    KogoVoiceManager.instance.playCompletion(VoiceMessageContext(
      stage: widget.lesson.stageId,
      lesson: widget.lesson.title,
      activity: widget.lesson.lessonType,
      isCompleted: true,
      targetWord: '',
    ));

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Luar Biasa! 🎉'),
          content: const Text('Kamu berhasil melengkapi semua huruf yang hilang!'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('Selesai', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lesson.title),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: const BackButton(color: Color(0xFF374151)),
      ),
      body: FutureBuilder<List<QuestionModel>>(
        future: _questionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Terjadi kesalahan:\n${snapshot.error}', textAlign: TextAlign.center),
              ),
            );
          }

          final questions = snapshot.data ?? [];
          if (questions.isEmpty) {
            return const Center(child: Text('Belum ada soal untuk aktivitas ini.'));
          }

          final question = questions[_currentIndex];
          _prepareMissingLetter(question);

          final word = question.targetText.toUpperCase();
          final emoji = _getWordEmoji(word);

          return Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFCE7F3), Color(0xFFFFEDD5)], // from-pink-100 to-orange-100
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                children: [
                  // Progress indicator
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: (_currentIndex + 1) / questions.length,
                      minHeight: 12,
                      backgroundColor: Colors.pink.withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFEC4899)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Soal ${_currentIndex + 1} dari ${questions.length}',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 24),

                  // Kartu Gambar / Emoji Target
                  ScaleTransition(
                    scale: Tween<double>(begin: 0.96, end: 1.04).animate(
                      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
                    ),
                    child: Container(
                      width: 140,
                      height: 140,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFEC4899).withValues(alpha: 0.25),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                        border: Border.all(color: const Color(0xFFFBCFE8), width: 2),
                      ),
                      alignment: Alignment.center,
                      child: question.resolvedImagePath != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.asset(
                                question.resolvedImagePath!,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => Text(emoji, style: const TextStyle(fontSize: 64)),
                              ),
                            )
                          : Text(emoji, style: const TextStyle(fontSize: 64)),
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Text(
                    'Isi huruf yang hilang:',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF374151)),
                  ),
                  const SizedBox(height: 18),

                  // Kotak Kata dengan Huruf Kosong (Responsif tanpa overflow untuk kata panjang)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      // ponytail: adaptive letter box sizing with a floor of 32px; wraps to next row if screen width < 320px
                      final availableWidth = constraints.maxWidth;
                      final marginHorizontal = word.length > 7 ? 3.0 : 5.0;
                      final boxWidth = ((availableWidth - (word.length * marginHorizontal * 2)) / word.length).clamp(32.0, 58.0);
                      final boxHeight = (boxWidth * 1.25).clamp(42.0, 72.0);
                      final fontSize = (boxWidth * 0.55).clamp(18.0, 32.0);

                      return Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: marginHorizontal * 2,
                        runSpacing: 10,
                        children: List.generate(word.length, (index) {
                          final isMissing = index == _missingCharIndex;
                          final letter = word[index];

                          return Container(
                            width: boxWidth,
                            height: boxHeight,
                            decoration: BoxDecoration(
                              color: isMissing ? const Color(0xFFFED7AA) : Colors.white,
                              borderRadius: BorderRadius.circular(boxWidth > 40 ? 16 : 10),
                              border: isMissing
                                  ? Border.all(color: const Color(0xFFEA580C), width: 3, style: BorderStyle.solid)
                                  : null,
                              boxShadow: const [
                                BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              isMissing ? (_selectedLetter ?? '?') : letter,
                              style: TextStyle(
                                fontSize: fontSize,
                                fontWeight: FontWeight.bold,
                                color: isMissing
                                    ? (_selectedLetter == null
                                        ? const Color(0xFFEA580C)
                                        : (_isCorrect == true ? const Color(0xFF16A34A) : const Color(0xFFDC2626)))
                                    : const Color(0xFF1F2937),
                              ),
                            ),
                          );
                        }),
                      );
                    },
                  ),

                  const SizedBox(height: 36),

                  // Pilihan Huruf
                  if (!_isAnswered) ...[
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      alignment: WrapAlignment.center,
                      children: _letterOptions.map((letter) {
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _selectLetter(letter, question),
                            borderRadius: BorderRadius.circular(20),
                            child: Ink(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFA855F7), Color(0xFFEC4899)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFEC4899).withValues(alpha: 0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  letter,
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ] else ...[
                    // Tampilan Feedback & Tombol Lanjut
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 14, offset: Offset(0, 6))],
                      ),
                      child: Column(
                        children: [
                          Text(_isCorrect == true ? '🎉' : '😊', style: const TextStyle(fontSize: 48)),
                          const SizedBox(height: 8),
                          Text(
                            _isCorrect == true ? 'Sempurna! Tepat Sekali' : 'Coba Sekali Lagi!',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: _isCorrect == true ? const Color(0xFF16A34A) : const Color(0xFFEA580C),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_isCorrect == true)
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              ),
                              onPressed: () => _nextQuestion(questions),
                              child: Text(
                                _currentIndex < questions.length - 1 ? 'Pertanyaan Berikutnya' : 'Selesai',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            )
                          else
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF3B82F6),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              ),
                              onPressed: () {
                                setState(() {
                                  _selectedLetter = null;
                                  _isCorrect = null;
                                  _isAnswered = false;
                                });
                              },
                              child: const Text('Ulangi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),
                  const Text('🐻', style: TextStyle(fontSize: 54)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
