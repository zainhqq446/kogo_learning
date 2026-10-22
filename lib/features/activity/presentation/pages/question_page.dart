import 'dart:async';
import 'package:flutter/material.dart';

import '../../../../data/models/lesson_model.dart';
import '../../../../data/models/question_model.dart';
import '../../../../data/repositories/answer_log_repository.dart';
import '../../../../data/repositories/progress_repository.dart';
import '../../../../data/repositories/question_repository.dart';
import '../../../../services/audio/bgm_manager.dart';
import '../../../../services/audio/kogo_voice_manager.dart';
import '../../../../services/audio/voice_message_context.dart';
import '../../../../services/auth/session_manager.dart';
import '../../../../services/speech/eleven_labs_speech_recognition_provider.dart';
import '../../../../services/speech/speech_evaluator.dart';
import '../../../../services/speech/speech_recognition_provider.dart';
import '../../../../services/sync/sync_service.dart';
import 'icebreaking_dialog.dart';


enum AudioCaptureState {
  idle,
  recording,
  processing,
  result,
}

class QuestionPage extends StatefulWidget {
  final LessonModel lesson;
  final SpeechRecognitionProvider? speechProvider;

  const QuestionPage({
    super.key,
    required this.lesson,
    this.speechProvider,
  });

  @override
  State<QuestionPage> createState() => _QuestionPageState();
}

class _QuestionPageState extends State<QuestionPage> with WidgetsBindingObserver {
  final QuestionRepository _repository = QuestionRepository();
  final AnswerLogRepository _answerLogRepository = AnswerLogRepository();
  final ProgressRepository _progressRepository = ProgressRepository();
  final SessionManager _sessionManager = SessionManager.instance;
  final SpeechEvaluator _speechEvaluator = const SpeechEvaluator();

  late final SpeechRecognitionProvider _speechProvider;

  late Future<List<QuestionModel>> _questionsFuture;

  int _currentIndex = 0;
  int _attemptCount = 0;
  int _consecutiveCorrectStreak = 0;
  AudioCaptureState _captureState = AudioCaptureState.idle;

  bool _speechInitialized = false;
  String _recognizedText = '';
  String? _feedback;
  bool? _isCorrect;
  double? _similarityPercent;
  String? _speechError;

  Timer? _listenTimeoutTimer;
  Timer? _initialPromptTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _speechProvider = widget.speechProvider ?? ElevenLabsSpeechRecognitionProvider.instance;
    _questionsFuture = _loadQuestionsAndResumeIndex();
    _initializeSpeech();
    BgmManager.instance.startBgm();
  }

  Future<List<QuestionModel>> _loadQuestionsAndResumeIndex() async {
    final questions = await _repository.getByLessonId(widget.lesson.id!);
    if (questions.isNotEmpty) {
      final childId = _sessionManager.currentChild?.id ?? 1;
      final savedIndex = await _progressRepository.getActiveQuestionIndex(
        childId: childId,
        lessonId: widget.lesson.id!,
      );

      final safeIndex = (savedIndex >= 0 && savedIndex < questions.length) ? savedIndex : 0;
      if (mounted) {
        setState(() {
          _currentIndex = safeIndex;
        });
      }

      _initialPromptTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) {
          _speakQuestionPrompt(questions[_currentIndex]);
        }
      });
    }
    return questions;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_captureState == AudioCaptureState.recording) {
        _listenTimeoutTimer?.cancel();
        _speechProvider.cancelListening();
        BgmManager.instance.restoreAfterSpeech();
        if (mounted) {
          setState(() {
            _captureState = AudioCaptureState.idle;
          });
        }
      }
    }
  }

  Future<void> _initializeSpeech() async {
    try {
      final success = await _speechProvider.initialize(
        locale: 'id_ID',
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _captureState = AudioCaptureState.idle;
            _speechError = error.message;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _speechInitialized = success;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _speechInitialized = false;
        _speechError = 'Inisialisasi speech provider: $e';
      });
    }
  }

  Future<void> _startListening(QuestionModel question) async {
    _listenTimeoutTimer?.cancel();

    // Duck BGM agar mikrofon bersih menangkap suara anak
    await BgmManager.instance.duckForSpeech();

    setState(() {
      _captureState = AudioCaptureState.recording;
      _recognizedText = '';
      _feedback = null;
      _isCorrect = null;
      _similarityPercent = null;
      _speechError = null;
    });

    _listenTimeoutTimer = Timer(const Duration(seconds: 10), () async {
      if (_captureState == AudioCaptureState.recording) {
        await _stopListening(question);
      }
    });

    try {
      await _speechProvider.startListening(
        expectedVocabulary: [question.targetText],
        onResult: (result) async {
          _listenTimeoutTimer?.cancel();
          await BgmManager.instance.restoreAfterSpeech();
          await _handleSpeechResult(question, result.recognizedText, result.confidence, result.duration);
        },
      );
    } catch (e) {
      _listenTimeoutTimer?.cancel();
      await BgmManager.instance.restoreAfterSpeech();
      if (!mounted) return;
      setState(() {
        _captureState = AudioCaptureState.idle;
        _speechError = e.toString();
      });
    }
  }

  Future<void> _stopListening(QuestionModel question) async {
    _listenTimeoutTimer?.cancel();
    await BgmManager.instance.restoreAfterSpeech();

    if (_captureState != AudioCaptureState.recording) return;

    setState(() {
      _captureState = AudioCaptureState.processing;
    });

    try {
      await _speechProvider.stopListening();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _captureState = AudioCaptureState.idle;
        _speechError = 'Gagal memproses suara: $e';
      });
    }
  }

  Future<void> _handleSpeechResult(
    QuestionModel question,
    String recognizedText,
    double? confidence,
    Duration duration,
  ) async {
    _listenTimeoutTimer?.cancel();
    final evaluation = _speechEvaluator.evaluate(
      targetText: question.targetText,
      recognizedText: recognizedText,
      confidence: confidence,
      duration: duration,
    );

    // Dapatkan data session dan child aktif
    final childId = _sessionManager.currentChild?.id ?? 1;
    final deviceId = _sessionManager.currentDevice?.id ?? 1;
    final sessionId = _sessionManager.currentSession?.id ?? 1;

    // Simpan ke answer_logs dan speech_logs dengan nomor attempt berurutan
    try {
      await _answerLogRepository.logAnswer(
        childId: childId,
        deviceId: deviceId,
        sessionId: sessionId,
        questionId: question.id!,
        targetText: evaluation.targetText,
        recognizedText: evaluation.recognizedText,
        normalizedTarget: evaluation.normalizedTarget,
        normalizedRecognized: evaluation.normalizedRecognized,
        editDistance: evaluation.editDistance,
        similarityScore: evaluation.similarityScore,
        similarityPercent: evaluation.similarityPercent,
        isCorrect: evaluation.isCorrect,
        recognitionDurationMs: duration.inMilliseconds,
        confidence: confidence,
        provider: _speechProvider.providerName,
        locale: 'id_ID',
      );

      // Otomatis sinkronisasi ke PostgreSQL di latar belakang
      SyncService.instance.autoSyncInBackground();
    } catch (e) {
      debugPrint('[QuestionPage] Gagal menyimpan log jawaban: $e');
    }


    if (!mounted) return;

    _attemptCount++;
    if (evaluation.isCorrect) {
      _consecutiveCorrectStreak++;
    } else {
      _consecutiveCorrectStreak = 0;
    }

    setState(() {
      _captureState = AudioCaptureState.result;
      _recognizedText = evaluation.recognizedText;
      _isCorrect = evaluation.isCorrect;
      _similarityPercent = evaluation.similarityPercent;
      _feedback = evaluation.feedback;
      _speechError = null;
    });

    // Mainkan respon audio kontekstual (stage, lesson, attempt, streak, similarity)
    final voiceContext = VoiceMessageContext(
      stage: widget.lesson.stageId,
      lesson: widget.lesson.title,
      activity: widget.lesson.lessonType,
      questionIndex: _currentIndex,
      totalQuestions: 5,
      targetWord: question.targetText,
      attemptNumber: _attemptCount,
      isCorrect: evaluation.isCorrect,
      similarity: evaluation.similarityPercent,
      streak: _consecutiveCorrectStreak,
      isEmptyRecognition: recognizedText.trim().isEmpty,
      recognizedText: evaluation.recognizedText,
    );

    await KogoVoiceManager.instance.playEvaluationFeedback(voiceContext);
  }

  void _speakQuestionPrompt(QuestionModel question) {
    KogoVoiceManager.instance.playSpeechPrompt(question.targetText, attempt: _attemptCount);
  }

  void _nextQuestion(List<QuestionModel> questions) {
    _listenTimeoutTimer?.cancel();

    if (_captureState == AudioCaptureState.recording) {
      _speechProvider.cancelListening();
    }

    if (_currentIndex < questions.length - 1) {
      void proceedToNext() {
        if (!mounted) return;
        KogoVoiceManager.instance.playTransition(VoiceMessageContext(
          stage: widget.lesson.stageId,
          lesson: widget.lesson.title,
          activity: widget.lesson.lessonType,
          questionIndex: _currentIndex,
          totalQuestions: questions.length,
          targetWord: questions[_currentIndex].targetText,
        ));
        final newIndex = _currentIndex + 1;
        final childId = _sessionManager.currentChild?.id ?? 1;
        _progressRepository.saveActiveQuestionIndex(
          childId: childId,
          lessonId: widget.lesson.id!,
          activeIndex: newIndex,
          isCompleted: false,
        );

        setState(() {
          _currentIndex = newIndex;
          _attemptCount = 0;
          _captureState = AudioCaptureState.idle;
          _recognizedText = '';
          _feedback = null;
          _isCorrect = null;
          _similarityPercent = null;
          _speechError = null;
        });
        _speakQuestionPrompt(questions[_currentIndex]);
      }

      // Tampilkan icebreaking setiap kali anak menyelesaikan 5 soal (misal setelah soal index 4, 9, 14, dst.)
      if ((_currentIndex + 1) % 5 == 0) {
        IcebreakingDialog.show(
          context,
          onContinue: proceedToNext,
        );
      } else {
        proceedToNext();
      }
    } else {
      final childId = _sessionManager.currentChild?.id ?? 1;
      _progressRepository.saveActiveQuestionIndex(
        childId: childId,
        lessonId: widget.lesson.id!,
        activeIndex: _currentIndex,
        isCompleted: true,
      );

      // Jika soal terakhir yang diselesaikan adalah kelipatan 5 (misal lesson hanya memiliki 5 soal),
      // tampilkan icebreaking mini-game terlebih dahulu sebelum dialog selesai.
      if ((_currentIndex + 1) % 5 == 0) {
        IcebreakingDialog.show(
          context,
          onContinue: () {
            if (mounted) {
              _showCompletionDialog();
            }
          },
        );
      } else {
        _showCompletionDialog();
      }
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
          title: const Text('Hebat! 🎉'),
          content: const Text('Kamu sudah menyelesaikan semua pertanyaan.'),
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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _initialPromptTimer?.cancel();
    _listenTimeoutTimer?.cancel();
    _speechProvider.cancelListening();
    KogoVoiceManager.instance.stop();
    BgmManager.instance.stopBgm();
    super.dispose();
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
                child: Text(
                  'Terjadi kesalahan:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final questions = snapshot.data ?? [];

          if (questions.isEmpty) {
            return const Center(
              child: Text(
                'Belum ada pertanyaan untuk aktivitas ini.',
                textAlign: TextAlign.center,
              ),
            );
          }

          final question = questions[_currentIndex];

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              children: [
                // Progress indicator ramah anak
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: (_currentIndex + 1) / questions.length,
                    minHeight: 12,
                    backgroundColor: const Color(0xFFFFECE6),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF6B4A)),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Pertanyaan ${_currentIndex + 1} dari ${questions.length}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF718096),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Ucapkan:',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D3748),
                  ),
                ),
                const SizedBox(height: 16),

                // Kartu Target Word dan Gambar (jika tersedia)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    color: Colors.white,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 16,
                        offset: Offset(0, 6),
                      ),
                    ],
                    border: Border.all(
                      color: const Color(0xFFFFF0D6),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      if (question.resolvedImagePath != null && question.resolvedImagePath!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Image.asset(
                              question.resolvedImagePath!,
                              height: 140,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.image_rounded,
                                size: 64,
                                color: Color(0xFFFFB703),
                              ),
                            ),
                          ),
                        ),
                      Text(
                        question.targetText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 64,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFF6B4A),
                          letterSpacing: 2,
                        ),
                      ),
                      if (question.hintText != null && question.hintText!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7E6),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            question.hintText!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF975A16),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Tombol Mikrofon Besar & Status Interaksi
                _buildMicrophoneButton(question),

                const SizedBox(height: 20),

                // State Feedback & Result Display
                _buildStateFeedbackSection(),

                if (_speechError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF5F5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFFEB2B2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.info_outline, color: Color(0xFFE53E3E), size: 20),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              // Menyajikan pesan ramah tanpa error teknis mendalam
                              _speechError!.contains('Exception') || _speechError!.contains('MissingPlugin')
                                  ? 'Ayo coba bicara lagi dengan jelas ya!'
                                  : _speechError!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFC53030),
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 28),

                // Tombol Lanjut / Selesai
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B4A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      elevation: 4,
                    ),
                    onPressed: () => _nextQuestion(questions),
                    child: Text(
                      _currentIndex < questions.length - 1
                          ? 'Pertanyaan Berikutnya'
                          : 'Selesai',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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

  Widget _buildMicrophoneButton(QuestionModel question) {
    final isRecording = _captureState == AudioCaptureState.recording;
    final isProcessing = _captureState == AudioCaptureState.processing;

    final btnColor = isRecording
        ? const Color(0xFFE53E3E)
        : isProcessing
            ? const Color(0xFFFFB703)
            : const Color(0xFFFF6B4A);

    return Center(
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: btnColor.withValues(alpha: isRecording ? 0.45 : 0.25),
                  blurRadius: isRecording ? 24 : 12,
                  spreadRadius: isRecording ? 6 : 2,
                ),
              ],
            ),
            child: Material(
              elevation: isRecording ? 10 : 5,
              shape: const CircleBorder(),
              color: btnColor,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: (!_speechInitialized || isProcessing)
                    ? null
                    : () {
                        if (isRecording) {
                          _stopListening(question);
                        } else {
                          _startListening(question);
                        }
                      },
                child: Container(
                  width: 104,
                  height: 104,
                  alignment: Alignment.center,
                  child: isProcessing
                      ? const SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 4,
                          ),
                        )
                      : Icon(
                          isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                          size: 58,
                          color: Colors.white,
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: isRecording
                  ? const Color(0xFFFED7D7)
                  : isProcessing
                      ? const Color(0xFFFEFCBF)
                      : const Color(0xFFFFF0EB),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isRecording
                  ? 'Sedang Mendengarkan... (Tekan untuk berhenti)'
                  : isProcessing
                      ? 'Sedang Mengevaluasi Suara...'
                      : 'Tekan Mikrofon untuk Berbicara',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isRecording
                    ? const Color(0xFFC53030)
                    : isProcessing
                        ? const Color(0xFF975A16)
                        : const Color(0xFFDD6B20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateFeedbackSection() {
    if (_captureState == AudioCaptureState.result) {
      final isCorrect = _isCorrect ?? false;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isCorrect ? const Color(0xFFF0FFF4) : const Color(0xFFFFFDF5),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isCorrect ? const Color(0xFF9AE6B4) : const Color(0xFFFBD38D),
            width: 2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isCorrect ? Icons.stars_rounded : Icons.sentiment_satisfied_alt_rounded,
                  color: isCorrect ? const Color(0xFF38A169) : const Color(0xFFDD6B20),
                  size: 32,
                ),
                const SizedBox(width: 8),
                Text(
                  isCorrect ? 'Hebat! Tepat Sekali' : 'Coba Sekali Lagi',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isCorrect ? const Color(0xFF276749) : const Color(0xFFC05621),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Terdengar: "$_recognizedText"',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2D3748),
              ),
            ),
            if (_similarityPercent != null) ...[
              const SizedBox(height: 6),
              Text(
                'Kemiripan: ${_similarityPercent!.toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF718096),
                ),
              ),
            ],
            if (_feedback != null) ...[
              const SizedBox(height: 10),
              Text(
                _feedback!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF4A5568),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}