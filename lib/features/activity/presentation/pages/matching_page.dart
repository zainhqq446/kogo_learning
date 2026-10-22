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

class MatchingPage extends StatefulWidget {
  final LessonModel lesson;

  const MatchingPage({
    super.key,
    required this.lesson,
  });

  @override
  State<MatchingPage> createState() => _MatchingPageState();
}

class _MatchingPageState extends State<MatchingPage> {
  final QuestionRepository _questionRepository = QuestionRepository();
  final AnswerLogRepository _answerLogRepository = AnswerLogRepository();
  final SessionManager _sessionManager = SessionManager.instance;

  late Future<List<QuestionModel>> _questionsFuture;
  int _currentIndex = 0;

  List<String> _targetSegments = [];
  List<String> _shuffledSegments = [];
  List<String> _selectedSegments = [];
  List<int> _usedSegmentIndices = [];

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
            KogoVoiceManager.instance.playGameIntro('matching');
          }
        });
      }
      return questions;
    });
  }

  void _prepareSegments(QuestionModel question) {
    if (_targetSegments.isNotEmpty) return;

    // Pisahkan target berdasarkan pemisah ' - ' atau '-'
    final rawSegments = question.targetText.split(RegExp(r'\s*-\s*')).map((s) => s.trim()).toList();
    _targetSegments = rawSegments;

    final shuffled = List<String>.from(rawSegments);
    // Shuffle dengan seed deterministik berbasis orderIndex jika lebih dari 1 segmen
    if (shuffled.length > 1) {
      final random = Random(question.id ?? question.orderIndex);
      // Pastikan urutan acak tidak sama persis dengan urutan target jika memungkinkan
      for (int i = 0; i < 5; i++) {
        shuffled.shuffle(random);
        if (shuffled.join(' - ') != _targetSegments.join(' - ')) {
          break;
        }
      }
    }

    _shuffledSegments = shuffled;
    _selectedSegments = [];
    _usedSegmentIndices = [];
  }

  void _onTileTapped(int index, String segment, QuestionModel question) {
    if (_isAnswered) return;
    if (_usedSegmentIndices.contains(index)) return;

    setState(() {
      _usedSegmentIndices.add(index);
      _selectedSegments.add(segment);
    });

    // Jika seluruh segmen sudah dipilih, periksa kecocokan
    if (_selectedSegments.length == _targetSegments.length) {
      _evaluateAnswer(question);
    }
  }

  void _removeSelectedSegment(int index) {
    if (_isAnswered) return;

    setState(() {
      final removed = _selectedSegments.removeAt(index);
      // Kembalikan status indeks yang digunakan
      final usedIdx = _usedSegmentIndices.firstWhere(
        (i) => _shuffledSegments[i] == removed,
        orElse: () => -1,
      );
      if (usedIdx != -1) {
        _usedSegmentIndices.remove(usedIdx);
      }
    });
  }

  void _resetSelection() {
    if (_isAnswered) return;
    setState(() {
      _selectedSegments.clear();
      _usedSegmentIndices.clear();
    });
  }

  int _streak = 0;

  @override
  void dispose() {
    _introTimer?.cancel();
    KogoVoiceManager.instance.stop();
    super.dispose();
  }

  Future<void> _evaluateAnswer(QuestionModel question) async {
    final assembledText = _selectedSegments.join(' - ');
    final isCorrect = assembledText.trim().toLowerCase() == question.targetText.trim().toLowerCase();

    if (isCorrect) {
      _streak++;
    } else {
      _streak = 0;
    }

    setState(() {
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
      recognizedText: assembledText,
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
        recognizedText: assembledText,
        normalizedTarget: question.normalizedTarget,
        normalizedRecognized: assembledText.trim().toLowerCase(),
        editDistance: isCorrect ? 0 : 1,
        similarityScore: isCorrect ? 1.0 : 0.0,
        similarityPercent: isCorrect ? 100.0 : 0.0,
        isCorrect: isCorrect,
        provider: 'matching_segment_assembly',
        locale: 'id_ID',
      );
    } catch (e) {
      debugPrint('[MatchingPage] Log answer error: $e');
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
        _targetSegments = [];
        _shuffledSegments = [];
        _selectedSegments = [];
        _usedSegmentIndices = [];
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
          title: const Text('Luar Biasa! 🧩'),
          content: const Text('Kamu berhasil mencocokkan semua kartu!'),
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
          _prepareSegments(question);

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
                      if (question.resolvedImagePath != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.asset(
                            question.resolvedImagePath!,
                            height: 120,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      const Text(
                        'Cocokkan & Susun:',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        question.targetText,
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Susunan Kartu Kamu:',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    if (!_isAnswered && _selectedSegments.isNotEmpty)
                      TextButton.icon(
                        onPressed: _resetSelection,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Ulangi'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const Duration(milliseconds: 100) > Duration.zero
                      ? const BoxConstraints(minHeight: 64)
                      : null,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade300, width: 1.5),
                  ),
                  child: _selectedSegments.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Sentuh potongan di bawah untuk menyusun',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: List.generate(_selectedSegments.length, (idx) {
                            final seg = _selectedSegments[idx];
                            return InputChip(
                              label: Text(
                                seg,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              onDeleted: _isAnswered ? null : () => _removeSelectedSegment(idx),
                              deleteIconColor: Colors.redAccent,
                            );
                          }),
                        ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Sentuh potongan kartu berikut sesuai urutan:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: List.generate(_shuffledSegments.length, (idx) {
                    final segment = _shuffledSegments[idx];
                    final isUsed = _usedSegmentIndices.contains(idx);

                    return SizedBox(
                      width: 140,
                      height: 58,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isUsed ? Colors.grey.shade200 : Theme.of(context).colorScheme.surface,
                          foregroundColor: isUsed ? Colors.grey.shade400 : Theme.of(context).colorScheme.onSurface,
                          elevation: isUsed ? 0 : 2,
                          side: BorderSide(
                            color: isUsed ? Colors.grey.shade300 : Theme.of(context).colorScheme.primary,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: isUsed ? null : () => _onTileTapped(idx, segment, question),
                        child: Text(
                          segment,
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }),
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
                          (_isCorrect ?? false) ? Icons.check_circle : Icons.info,
                          color: (_isCorrect ?? false) ? Colors.green : Colors.orange.shade800,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          (_isCorrect ?? false) ? 'Cocok! Hebat Sekali 🎉' : 'Urutan belum tepat, yuk coba lagi!',
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
                        _selectedSegments = [];
                        _usedSegmentIndices = [];
                        _isCorrect = null;
                        _isAnswered = false;
                      });
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text(
                      'Susun Ulang 🔄',
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
