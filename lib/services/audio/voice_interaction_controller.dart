import 'dart:async';
import 'package:flutter/foundation.dart';
import 'audio_message_manager.dart';
import 'eleven_labs_voice_provider.dart';
import 'speech_output_provider.dart';

/// Controller utama untuk seluruh interaksi audio Kogo.
/// Mengelola antrean suara (AudioQueue), pemutaran human prerecorded audio,
/// pengucapan kata dinamis, pencegahan overlap, dan penghentian otomatis saat navigasi.
class VoiceInteractionController {
  VoiceInteractionController._internal();

  static final VoiceInteractionController instance = VoiceInteractionController._internal();

  SpeechOutputProvider? _provider;
  SpeechOutputProvider get provider => _provider ??= ElevenLabsVoiceProvider();

  final AudioMessageManager _messageManager = AudioMessageManager.instance;

  // Queue pemutaran audio berurutan
  Completer<void>? _currentAudioCompleter;
  int _currentOperationId = 0;

  /// Memperbolehkan dependency injection untuk testing
  void setProviderForTesting(SpeechOutputProvider testProvider) {
    _provider = testProvider;
  }

  /// Memainkan feedback hasil evaluasi jawaban anak (Benar, Hampir Benar, Salah, Streak, Selesai)
  Future<void> playEvaluationFeedback(AudioContextInfo context) async {
    final audioItem = _messageManager.selectFeedbackAudio(context);
    await _enqueuePlay(() => provider.playHuman(audioItem.assetPath));
  }

  /// Memainkan feedback hasil evaluasi menggunakan VoiceMessageContext yang lebih kaya
  Future<void> playEvaluationFeedbackWithVoiceContext(dynamic voiceContext) async {
    if (voiceContext is AudioContextInfo) {
      return playEvaluationFeedback(voiceContext);
    }
    // Jika VoiceMessageContext
    final audioContext = AudioContextInfo(
      targetWord: voiceContext.targetWord,
      attemptNumber: voiceContext.attemptNumber,
      isCorrect: voiceContext.isCorrect,
      similarityPercent: voiceContext.similarity,
      streak: voiceContext.streak,
      isCompleted: voiceContext.isCompleted,
      isEmptyRecognition: voiceContext.isEmptyRecognition,
    );
    await playEvaluationFeedback(audioContext);
  }

  /// Memainkan ajakan berbicara lengkap:
  /// Human phrase ("Sekarang, coba ucapkan") + jeda natural (250ms) + target word audio ("Kucing")
  Future<void> playSpeechPrompt(String targetWord) async {
    final invitation = _messageManager.selectInvitationAudio();
    final wordAsset = _messageManager.getWordAssetPath(targetWord);

    await _enqueuePlay(() => provider.playPhraseAndWord(
      phraseAsset: invitation.assetPath,
      word: targetWord,
      wordAsset: wordAsset,
      pauseDuration: const Duration(milliseconds: 250),
    ));
  }

  /// Memainkan contoh pengucapan kata target langsung (saat ikon dengarkan ditekan)
  Future<void> playWordExample(String targetWord) async {
    final wordAsset = _messageManager.getWordAssetPath(targetWord);
    await _enqueuePlay(() async {
      if (wordAsset != null) {
        await provider.playHuman(wordAsset);
      } else {
        await provider.speakDynamicText(targetWord);
      }
    });
  }

  /// Memainkan instruksi awal ramah anak
  Future<void> playInstruction() async {
    final instruction = _messageManager.selectInstructionAudio();
    await _enqueuePlay(() => provider.playHuman(instruction.assetPath));
  }

  /// Memainkan intro khusus permainan anak (Find Object, Matching, Listen Carefully, Missing Letter, Listen & Repeat)
  Future<void> playGameIntro(String gameType) async {
    final introItem = _messageManager.selectGameIntro(gameType);
    await _enqueuePlay(() => provider.playHuman(introItem.assetPath));
  }

  /// Memainkan transisi saat berpindah ke soal berikutnya
  Future<void> playTransition() async {
    final transItem = _messageManager.selectTransitionAudio();
    await _enqueuePlay(() => provider.playHuman(transItem.assetPath));
  }

  /// Memainkan dorongan semangat selama anak mengamati atau berpikir
  Future<void> playEncouragement() async {
    final encItem = _messageManager.selectEncouragementAudio();
    await _enqueuePlay(() => provider.playHuman(encItem.assetPath));
  }

  /// Memainkan selebrasi selesai aktivitas
  Future<void> playCompletion() async {
    final completeItem = _messageManager.selectCompletionAudio();
    await _enqueuePlay(() => provider.playHuman(completeItem.assetPath));
  }

  /// Memutar file human audio langsung
  Future<void> playHumanAudio(String assetPath) async {
    await _enqueuePlay(() => provider.playHuman(assetPath));
  }

  /// Memutar teks dinamis
  Future<void> speakDynamic(String text) async {
    await _enqueuePlay(() => provider.speakDynamicText(text));
  }

  /// ID operasi audio aktif saat ini untuk concurrency control
  int get currentOperationId => _currentOperationId;

  /// Menghentikan seluruh pemutaran audio saat ini dan membatalkan antrean.
  /// Jika operationId disertakan, hanya membatalkan jika ID tersebut cocok
  /// dengan operasi aktif (mencegah operasi lama membatalkan audio operasi baru).
  Future<void> stop([int? operationId]) async {
    if (operationId != null && operationId != _currentOperationId) {
      return;
    }
    _currentOperationId++;
    try {
      await provider.stop();
    } catch (e) {
      debugPrint('[VoiceInteractionController] stop error: $e');
    }
    if (!(_currentAudioCompleter?.isCompleted ?? true)) {
      _currentAudioCompleter?.complete();
    }
  }

  /// Helper untuk memastikan antrean serial tanpa tabrakan audio
  Future<void> _enqueuePlay(Future<void> Function() action) async {
    final opId = ++_currentOperationId;

    // Hentikan pemutaran sebelumnya jika masih berjalan
    await provider.stop();

    if (opId != _currentOperationId) return;

    final completer = Completer<void>();
    _currentAudioCompleter = completer;

    try {
      await action();
    } catch (e) {
      debugPrint('[VoiceInteractionController] play error: $e');
    } finally {
      if (opId == _currentOperationId) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    }
  }

  /// Membersihkan controller
  Future<void> dispose() async {
    await stop();
    await _provider?.dispose();
  }
}
