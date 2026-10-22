import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import '../../../../core/constants/image_dataset_catalog.dart';
import '../../../../data/models/lesson_model.dart';
import '../../../../data/models/question_model.dart';
import '../../../../data/repositories/answer_log_repository.dart';
import '../../../../data/repositories/question_repository.dart';
import '../../../../services/audio/kogo_voice_manager.dart';
import '../../../../services/audio/voice_message_context.dart';
import '../../../../services/auth/session_manager.dart';

class FindObjectPage extends StatefulWidget {
  final LessonModel lesson;

  const FindObjectPage({
    super.key,
    required this.lesson,
  });

  @override
  State<FindObjectPage> createState() => _FindObjectPageState();
}

class _FindObjectPageState extends State<FindObjectPage> {
  final QuestionRepository _questionRepository = QuestionRepository();
  final AnswerLogRepository _answerLogRepository = AnswerLogRepository();
  final SessionManager _sessionManager = SessionManager.instance;

  late Future<List<QuestionModel>> _questionsFuture;
  int _currentIndex = 0;

  List<String> _currentOptions = [];
  String? _selectedOption;
  bool? _isCorrect;
  bool _isAnswered = false;

  Timer? _introTimer;

  @override
  void initState() {
    super.initState();
    _questionsFuture = _questionRepository.getByLessonId(widget.lesson.id!).then((questions) {
      if (questions.isNotEmpty) {
        _introTimer = Timer(const Duration(milliseconds: 300), () {
          if (mounted && _currentIndex == 0) {
            KogoVoiceManager.instance.playGameIntro('find_object');
          }
        });
      }
      return questions;
    });
  }

  void _prepareOptions(QuestionModel currentQuestion, List<QuestionModel> allQuestions) {
    if (_currentOptions.isNotEmpty) return;

    final optionsSet = <String>{currentQuestion.targetText};

    // Ambil opsi pengecoh dari target pertanyaan lain
    for (final q in allQuestions) {
      if (q.targetText != currentQuestion.targetText) {
        optionsSet.add(q.targetText);
      }
    }

    // Pengecoh cadangan jika list pertanyaan sedikit
    final fallbackDistractors = ['Apel', 'Buku', 'Bola', 'Meja', 'Sepatu', 'Topi', 'Kucing', 'Pohon'];
    for (final distractor in fallbackDistractors) {
      if (optionsSet.length >= 4) break;
      if (distractor.toLowerCase() != currentQuestion.targetText.toLowerCase()) {
        optionsSet.add(distractor);
      }
    }

    final list = optionsSet.take(4).toList();
    list.shuffle(Random(currentQuestion.id ?? currentQuestion.orderIndex));
    _currentOptions = list;
  }

  int _streak = 0;

  @override
  void dispose() {
    _introTimer?.cancel();
    KogoVoiceManager.instance.stop();
    super.dispose();
  }

  Future<void> _selectOption(String option, QuestionModel question) async {
    if (_isAnswered) return;

    final isCorrect = option.trim().toLowerCase() == question.targetText.trim().toLowerCase();

    if (isCorrect) {
      _streak++;
    } else {
      _streak = 0;
    }

    setState(() {
      _selectedOption = option;
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
      recognizedText: option,
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
        recognizedText: option,
        normalizedTarget: question.normalizedTarget,
        normalizedRecognized: option.trim().toLowerCase(),
        editDistance: isCorrect ? 0 : 1,
        similarityScore: isCorrect ? 1.0 : 0.0,
        similarityPercent: isCorrect ? 100.0 : 0.0,
        isCorrect: isCorrect,
        provider: 'find_object_selection',
        locale: 'id_ID',
      );
    } catch (e) {
      debugPrint('[FindObjectPage] Log answer error: $e');
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
        _currentOptions = [];
        _selectedOption = null;
        _isCorrect = null;
        _isAnswered = false;
      });
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
          title: const Text('Bagus Sekali! 🌟'),
          content: const Text('Kamu berhasil menemukan semua objek!'),
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
      appBar: AppBar(
        title: Text(widget.lesson.title),
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
                child: Text('Terjadi kesalahan:\n${snapshot.error}'),
              ),
            );
          }

          final questions = snapshot.data ?? [];
          if (questions.isEmpty) {
            return const Center(child: Text('Belum ada pertanyaan.'));
          }

          final question = questions[_currentIndex];
          _prepareOptions(question, questions);

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(
                  value: (_currentIndex + 1) / questions.length,
                ),
                const SizedBox(height: 12),
                Text(
                  'Pertanyaan ${_currentIndex + 1} dari ${questions.length}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Temukan Objek:',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        question.targetText,
                        style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      if (question.hintText != null && question.hintText!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          question.hintText!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Pilih objek yang sesuai:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.05,
                  children: _currentOptions.map((opt) {
                    final isSelected = _selectedOption == opt;
                    final imgPath = ImageDatasetCatalog.findAssetPath(opt);
                    Color btnColor = Theme.of(context).colorScheme.surface;
                    Color borderColor = Colors.grey.shade300;

                    if (_isAnswered) {
                      if (opt.toLowerCase() == question.targetText.toLowerCase()) {
                        btnColor = Colors.green.shade50;
                        borderColor = Colors.green;
                      } else if (isSelected && !(_isCorrect ?? false)) {
                        btnColor = Colors.red.shade50;
                        borderColor = Colors.red;
                      }
                    }

                    return InkWell(
                      onTap: () => _selectOption(opt, question),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: btnColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Expanded(
                              child: imgPath != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.asset(
                                        imgPath,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, _, _) => const Icon(
                                          Icons.category_rounded,
                                          size: 40,
                                          color: Colors.blueAccent,
                                        ),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.category_rounded,
                                      size: 40,
                                      color: Colors.blueAccent,
                                    ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              opt,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (_isAnswered) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: (_isCorrect ?? false) ? Colors.green.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: (_isCorrect ?? false) ? Colors.green : Colors.orange,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          (_isCorrect ?? false) ? Icons.check_circle : Icons.replay_rounded,
                          color: (_isCorrect ?? false) ? Colors.green : Colors.orange.shade800,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          (_isCorrect ?? false) ? 'Jawaban Benar! 🎉' : 'Kurang tepat, yuk coba lagi!',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: (_isCorrect ?? false) ? Colors.green.shade900 : Colors.orange.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (_isAnswered && !(_isCorrect ?? false)) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedOption = null;
                        _isCorrect = null;
                        _isAnswered = false;
                      });
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text(
                      'Coba Lagi 💪',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ] else ...[
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: (_isAnswered && (_isCorrect ?? false))
                        ? () => _nextQuestion(questions)
                        : null,
                    child: Text(
                      _currentIndex < questions.length - 1 ? 'Pertanyaan Berikutnya' : 'Selesai',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
