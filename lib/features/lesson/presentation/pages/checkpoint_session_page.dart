import 'package:flutter/material.dart';

import '../../../../data/models/lesson_model.dart';
import '../../../../data/models/question_model.dart';
import '../../../../data/repositories/checkpoint_repository.dart';
import '../../../../data/repositories/progress_repository.dart';
import '../../../../services/audio/kogo_voice_manager.dart';
import '../../../../services/audio/voice_message_context.dart';
import '../../../../services/auth/session_manager.dart';
import '../../../activity/presentation/pages/find_object_page.dart';
import '../../../activity/presentation/pages/listen_carefully_page.dart';
import '../../../activity/presentation/pages/matching_page.dart';
import '../../../activity/presentation/pages/question_page.dart';
import '../../../activity/presentation/pages/word_assembly_page.dart';
import '../widgets/checkpoint_reward_dialog.dart';

enum CheckpointGameType {
  listenRepeat1,    // Listen & Repeat Part 1 (Kata 1..3)
  matching,         // Matching Object (6 gambar vs 6 kata)
  listenRepeat2,    // Listen & Repeat Part 2 (Kata 4..6)
  listenCarefully1, // Listen Carefully Part 1 (Kata 1..3)
  wordAssembly,     // Susun Kata (Menyusun kata acak, tile ID unik)
  listenCarefully2, // Listen Carefully Part 2 (Kata 4..6)
  stage1FindObject, // Khusus Stage 1: Tebak Gambar Huruf Awal
}

/// Halaman Orkestrasi Sesi Pembelajaran Checkpoint
/// Untuk Stage 2-4 (Kata): Komposisi tepat 6 aktivitas per checkpoint:
/// 1. Listen & Repeat (3 kata pertama)
/// 2. Matching Object (6 gambar vs 6 kata)
/// 3. Listen & Repeat (3 kata kedua)
/// 4. Listen Carefully (3 kata pertama)
/// 5. Susun Kata (6 kata disusun satu per satu)
/// 6. Listen Carefully (3 kata kedua)
///
/// Untuk Stage 1 (Huruf):
/// 1. Listen & Repeat (Mengenal & melafalkan huruf)
/// 2. Tebak Gambar Huruf Awal (Pilih gambar yang berawalan huruf tersebut dari 4 pilihan)
class CheckpointSessionPage extends StatefulWidget {
  final int stageId;
  final int checkpointNumber;
  final String stageTitle;
  final String checkpointTitle;
  final VoidCallback? onCheckpointCompleted;

  const CheckpointSessionPage({
    super.key,
    required this.stageId,
    required this.checkpointNumber,
    required this.stageTitle,
    required this.checkpointTitle,
    this.onCheckpointCompleted,
  });

  @override
  State<CheckpointSessionPage> createState() => _CheckpointSessionPageState();
}

class _CheckpointSessionPageState extends State<CheckpointSessionPage> {
  final CheckpointRepository _checkpointRepository = CheckpointRepository();
  final ProgressRepository _progressRepository = ProgressRepository();
  final SessionManager _sessionManager = SessionManager.instance;

  late Future<List<CheckpointWord>> _wordsFuture;
  List<CheckpointWord> _words = [];
  int _currentGameStep = 0;

  late final List<CheckpointGameType> _gameOrder;

  @override
  void initState() {
    super.initState();
    if (widget.stageId == 1) {
      // Stage 1 khusus huruf: 2 aktivitas (Lafalkan huruf + Tebak gambar huruf awal)
      _gameOrder = const [
        CheckpointGameType.listenRepeat1,
        CheckpointGameType.stage1FindObject,
      ];
    } else {
      // Stage 2-4: Tepat 6 aktivitas per checkpoint
      _gameOrder = const [
        CheckpointGameType.listenRepeat1,
        CheckpointGameType.matching,
        CheckpointGameType.listenRepeat2,
        CheckpointGameType.listenCarefully1,
        CheckpointGameType.wordAssembly,
        CheckpointGameType.listenCarefully2,
      ];
    }

    _wordsFuture = _checkpointRepository.getWordsForCheckpoint(
      stageId: widget.stageId,
      checkpointNumber: widget.checkpointNumber,
    ).then((words) {
      _words = words;
      return words;
    });
  }

  LessonModel _createSyntheticLesson({
    required String lessonType,
    required String title,
  }) {
    return LessonModel(
      id: (widget.stageId * 100) + widget.checkpointNumber,
      stageId: widget.stageId,
      title: '${widget.checkpointTitle} - $title',
      description: 'Sesi permainan $title untuk ${widget.checkpointTitle}',
      lessonType: lessonType,
      orderIndex: _currentGameStep + 1,
      isActive: true,
    );
  }

  /// Membagi kata untuk aktivitas tertentu (misal part 1: kata 1-3, part 2: kata 4-6)
  List<QuestionModel> _buildQuestionsForStep(CheckpointGameType gameType) {
    List<CheckpointWord> selectedWords;

    if (widget.stageId == 1) {
      selectedWords = _words;
    } else {
      switch (gameType) {
        case CheckpointGameType.listenRepeat1:
        case CheckpointGameType.listenCarefully1:
          selectedWords = _words.take(3).toList();
          break;
        case CheckpointGameType.listenRepeat2:
        case CheckpointGameType.listenCarefully2:
          selectedWords = _words.skip(3).take(3).toList();
          if (selectedWords.isEmpty) {
            selectedWords = _words;
          }
          break;
        case CheckpointGameType.matching:
        case CheckpointGameType.wordAssembly:
        default:
          selectedWords = _words;
          break;
      }
    }

    return selectedWords.asMap().entries.map((entry) {
      final index = entry.key;
      final word = entry.value;
      return word.toQuestionModel(
        lessonId: (widget.stageId * 100) + widget.checkpointNumber,
        orderIndex: index + 1,
      );
    }).toList();
  }

  void _onGameStepCompleted() {
    if (_currentGameStep < _gameOrder.length - 1) {
      setState(() {
        _currentGameStep++;
      });
      _showGameStepTransitionDialog(_gameOrder[_currentGameStep]);
    } else {
      _finishCheckpointSession();
    }
  }

  void _showGameStepTransitionDialog(CheckpointGameType nextGame) {
    String gameName;
    String gameIcon;
    switch (nextGame) {
      case CheckpointGameType.listenRepeat1:
      case CheckpointGameType.listenRepeat2:
        gameName = 'Ucapkan Bersama Kogo (Listen & Repeat)';
        gameIcon = '🎤';
        break;
      case CheckpointGameType.matching:
        gameName = 'Pasangkan Gambar & Kata (Matching Object)';
        gameIcon = '🧩';
        break;
      case CheckpointGameType.listenCarefully1:
      case CheckpointGameType.listenCarefully2:
        gameName = 'Dengarkan Baik-baik (Listen Carefully)';
        gameIcon = '🎧';
        break;
      case CheckpointGameType.wordAssembly:
        gameName = 'Susun Huruf Kata (Word Assembly)';
        gameIcon = '🔤';
        break;
      case CheckpointGameType.stage1FindObject:
        gameName = 'Tebak Gambar Huruf Awal';
        gameIcon = '🔍';
        break;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Text(gameIcon, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Lanjut ke Game Berikutnya!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: Text('Hebat! Sekarang kita mainkan $gameName.'),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B4A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Mulai! 🚀', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _finishCheckpointSession() async {
    final childId = _sessionManager.currentChild?.id ?? 1;

    // Simpan status checkpoint selesai
    await _progressRepository.completeCheckpoint(
      childId: childId,
      stageId: widget.stageId,
      checkpointNumber: widget.checkpointNumber,
    );

    if (!mounted) return;

    KogoVoiceManager.instance.playCompletion(VoiceMessageContext(
      stage: widget.stageId,
      lesson: widget.checkpointTitle,
      activity: 'checkpoint_completed',
      isCompleted: true,
      targetWord: '',
    ));

    await CheckpointRewardDialog.show(
      context: context,
      stageId: widget.stageId,
      checkpointNumber: widget.checkpointNumber,
      checkpointTitle: widget.checkpointTitle,
      onClaimed: () {
        widget.onCheckpointCompleted?.call();
        Navigator.pop(context, true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CheckpointWord>>(
      future: _wordsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.checkpointTitle)),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Data kata untuk checkpoint ini belum siap:\n${snapshot.error ?? "Tidak ada data kata"}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final currentGame = _gameOrder[_currentGameStep];
        final questions = _buildQuestionsForStep(currentGame);

        switch (currentGame) {
          case CheckpointGameType.listenRepeat1:
            return QuestionPage(
              key: ValueKey('step_${_currentGameStep}_${widget.checkpointNumber}'),
              lesson: _createSyntheticLesson(lessonType: 'listen_repeat', title: 'Listen & Repeat Bagian 1'),
              questionsOverride: questions,
              onCompleted: _onGameStepCompleted,
            );
          case CheckpointGameType.listenRepeat2:
            return QuestionPage(
              key: ValueKey('step_${_currentGameStep}_${widget.checkpointNumber}'),
              lesson: _createSyntheticLesson(lessonType: 'listen_repeat', title: 'Listen & Repeat Bagian 2'),
              questionsOverride: questions,
              onCompleted: _onGameStepCompleted,
            );
          case CheckpointGameType.matching:
            return MatchingPage(
              key: ValueKey('step_${_currentGameStep}_${widget.checkpointNumber}'),
              lesson: _createSyntheticLesson(lessonType: 'matching', title: 'Matching Object'),
              questionsOverride: questions,
              onCompleted: _onGameStepCompleted,
            );
          case CheckpointGameType.listenCarefully1:
            return ListenCarefullyPage(
              key: ValueKey('step_${_currentGameStep}_${widget.checkpointNumber}'),
              lesson: _createSyntheticLesson(lessonType: 'listen_carefully', title: 'Listen Carefully Bagian 1'),
              questionsOverride: questions,
              onCompleted: _onGameStepCompleted,
            );
          case CheckpointGameType.listenCarefully2:
            return ListenCarefullyPage(
              key: ValueKey('step_${_currentGameStep}_${widget.checkpointNumber}'),
              lesson: _createSyntheticLesson(lessonType: 'listen_carefully', title: 'Listen Carefully Bagian 2'),
              questionsOverride: questions,
              onCompleted: _onGameStepCompleted,
            );
          case CheckpointGameType.wordAssembly:
            return WordAssemblyPage(
              key: ValueKey('step_${_currentGameStep}_${widget.checkpointNumber}'),
              lesson: _createSyntheticLesson(lessonType: 'word_assembly', title: 'Susun Kata'),
              questionsOverride: questions,
              onCompleted: _onGameStepCompleted,
            );
          case CheckpointGameType.stage1FindObject:
            return FindObjectPage(
              key: ValueKey('step_${_currentGameStep}_${widget.checkpointNumber}'),
              lesson: _createSyntheticLesson(lessonType: 'find_object', title: 'Tebak Gambar Huruf Awal'),
              questionsOverride: questions,
              onCompleted: _onGameStepCompleted,
            );
        }
      },
    );
  }
}
