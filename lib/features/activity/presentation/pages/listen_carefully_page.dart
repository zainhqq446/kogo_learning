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

class ListenCarefullyPage extends StatefulWidget {
  final LessonModel lesson;
  final List<QuestionModel>? questionsOverride;
  final VoidCallback? onCompleted;

  const ListenCarefullyPage({
    super.key,
    required this.lesson,
    this.questionsOverride,
    this.onCompleted,
  });

  @override
  State<ListenCarefullyPage> createState() => _ListenCarefullyPageState();
}

class _ListenCarefullyPageState extends State<ListenCarefullyPage> {
  final QuestionRepository _questionRepository = QuestionRepository();
  final AnswerLogRepository _answerLogRepository = AnswerLogRepository();
  final SessionManager _sessionManager = SessionManager.instance;

  late Future<List<QuestionModel>> _questionsFuture;
  int _currentIndex = 0;

  List<String> _currentOptions = [];
  String? _selectedOption;
  bool? _isCorrect;
  bool _isAnswered = false;
  bool _isPlayingAudio = false;

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
            KogoVoiceManager.instance.playGameIntro('listen_carefully');
          }
        });
      }
      return questions;
    });
  }


  void _prepareOptions(QuestionModel currentQuestion, List<QuestionModel> allQuestions) {
    if (_currentOptions.isNotEmpty) return;

    final optionsSet = <String>{currentQuestion.targetText};

    // 1. Ambil opsi pengecoh dari pertanyaan lain dalam lesson yang memiliki gambar valid
    for (final q in allQuestions) {
      if (optionsSet.length >= 4) break;
      if (q.targetText.toLowerCase() != currentQuestion.targetText.toLowerCase() &&
          ImageDatasetCatalog.hasImage(q.targetText)) {
        optionsSet.add(q.targetText);
      }
    }

    // 2. Jika belum cukup 4 pilihan, ambil dari katalog dataset gambar resmi yang valid
    final availableDatasetWords = ImageDatasetCatalog.allWords;
    final random = Random(currentQuestion.id ?? currentQuestion.orderIndex);
    final shuffledWords = List<String>.from(availableDatasetWords)..shuffle(random);

    for (final candidate in shuffledWords) {
      if (optionsSet.length >= 4) break; // Tepat 4 pilihan bergambar (1 target + 3 distraktor)
      if (candidate.toLowerCase() != currentQuestion.targetText.toLowerCase() &&
          ImageDatasetCatalog.hasImage(candidate)) {
        optionsSet.add(candidate);
      }
    }

    final list = optionsSet.toList();
    list.shuffle(random);
    _currentOptions = list;
  }

  Timer? _audioTimer;

  @override
  void dispose() {
    _introTimer?.cancel();
    _audioTimer?.cancel();
    KogoVoiceManager.instance.stop();
    super.dispose();
  }

  int _streak = 0;

  void _playAudioPrompt(QuestionModel question) {
    _audioTimer?.cancel();
    setState(() {
      _isPlayingAudio = true;
    });

    KogoVoiceManager.instance.playWordExample(question.targetText);

    _audioTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _isPlayingAudio = false;
        });
      }
    });
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
        provider: 'listen_carefully_choice',
        locale: 'id_ID',
      );
    } catch (e) {
      debugPrint('[ListenCarefullyPage] Log answer error: $e');
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
        _isPlayingAudio = false;
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

    if (widget.onCompleted != null) {
      widget.onCompleted!();
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Pendengaran Hebat! 🎧'),
          content: const Text('Kamu berhasil mendengarkan dan menjawab semua soal!'),
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
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Dengarkan Baik-baik:',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 16),
                      // Tombol Putar Suara Besar
                      Material(
                        elevation: _isPlayingAudio ? 8 : 4,
                        shape: const CircleBorder(),
                        color: _isPlayingAudio ? Colors.orange : Theme.of(context).colorScheme.primary,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _playAudioPrompt(question),
                          child: Container(
                            width: 90,
                            height: 90,
                            alignment: Alignment.center,
                            child: Icon(
                              _isPlayingAudio ? Icons.volume_up_rounded : Icons.play_arrow_rounded,
                              size: 52,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _isPlayingAudio ? 'Memutar Suara...' : 'Sentuh untuk Mendengar Suara',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _isPlayingAudio ? Colors.orange.shade900 : Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      if (question.hintText != null && question.hintText!.isNotEmpty) ...[
                        const SizedBox(height: 10),
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
                  'Pilih jawaban yang kamu dengar:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.1,
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
                            if (imgPath != null) ...[
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.asset(
                                    imgPath,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                            ],
                            Text(
                              opt,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
                          (_isCorrect ?? false) ? 'Tepat Sekali! 🎉' : 'Belum tepat, yuk dengarkan lagi!',
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
                      _playAudioPrompt(questions[_currentIndex]);
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text(
                      'Coba Dengarkan Lagi 🎧',
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
