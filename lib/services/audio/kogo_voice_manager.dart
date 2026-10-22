import 'dart:async';
import 'audio_message_manager.dart';
import 'speech_output_provider.dart';
import 'voice_interaction_controller.dart';
import 'voice_message.dart';
import 'voice_message_context.dart';
import 'voice_message_selector.dart';

/// Facade & orchestrator tunggal untuk manajemen interaksi suara Kogo.
/// Mengintegrasikan VoiceMessageSelector, AudioMessageManager, dan SpeechOutputProvider.
/// Mencegah overlap, membatalkan suara lama saat pindah soal/layar, dan mengelola micro-reactions.
class KogoVoiceManager {
  KogoVoiceManager._internal();
  static final KogoVoiceManager instance = KogoVoiceManager._internal();

  final VoiceMessageSelector _selector = VoiceMessageSelector.instance;
  final VoiceInteractionController _controller = VoiceInteractionController.instance;
  final AudioMessageManager _audioManager = AudioMessageManager.instance;

  SpeechOutputProvider get provider => _controller.provider;

  /// Memainkan respon hasil evaluasi anak berbasis konteks lengkap
  Future<void> playEvaluationFeedback(VoiceMessageContext context) async {
    final voiceMessage = _selector.selectEvaluationMessage(context);
    await _playVoiceMessage(voiceMessage, targetWord: context.targetWord);
  }

  /// Memainkan intro permainan ramah anak
  Future<void> playGameIntro(String gameType) async {
    const dynamicIntroGames = {
      'listen_repeat',
      'find_object',
      'matching',
      'listen_carefully',
      'missing_letter',
    };
    if (!dynamicIntroGames.contains(gameType)) {
      final introAudio = _audioManager.gameIntroAudios[gameType];
      if (introAudio != null && introAudio.isNotEmpty) {
        await _controller.playGameIntro(gameType);
        return;
      }
    }

    final voiceMessage = _selector.selectGameIntro(gameType);
    await _playVoiceMessage(voiceMessage);
  }

  /// Memainkan dorongan semangat atau bantuan pemikiran saat anak mengamati
  Future<void> playEncouragement(String gameType) async {
    final voiceMessage = _selector.selectGameEncouragement(gameType);
    await _playVoiceMessage(voiceMessage);
  }

  /// Memainkan transisi saat berpindah ke soal berikutnya dengan mempertimbangkan progres
  Future<void> playTransition([VoiceMessageContext? context]) async {
    final ctx = context ?? const VoiceMessageContext(targetWord: '');
    final voiceMessage = _selector.selectTransition(ctx);
    await _playVoiceMessage(voiceMessage);
  }

  /// Memainkan selebrasi selesai sesi
  Future<void> playCompletion([VoiceMessageContext? context]) async {
    final ctx = context ?? const VoiceMessageContext(targetWord: '', isCompleted: true);
    final voiceMessage = _selector.selectCompletionMessage(ctx);
    await _playVoiceMessage(voiceMessage);
  }

  /// Memainkan ajakan berbicara untuk target word tertentu
  Future<void> playSpeechPrompt(String targetWord, {int attempt = 1}) async {
    // Jika kata ada di koleksi audio rekaman lokal, putar kombinasi prerecorded
    final wordAsset = _audioManager.getWordAssetPath(targetWord);
    if (wordAsset != null) {
      await _controller.playSpeechPrompt(targetWord);
      return;
    }

    final voiceMessage = _selector.selectSpeechPrompt(targetWord, attempt: attempt);
    await _playVoiceMessage(voiceMessage, targetWord: targetWord);
  }

  /// Memainkan contoh pengucapan kata target
  Future<void> playWordExample(String targetWord) async {
    await _controller.playWordExample(targetWord);
  }

  /// Menghentikan seluruh audio saat navigasi atau pergantian soal
  Future<void> stop() async {
    await _controller.stop();
  }

  /// Eksekusi pemutaran VoiceMessage secara aman melalui controller
  Future<void> _playVoiceMessage(VoiceMessage message, {String? targetWord}) async {
    // 1. Cek apakah ada file rekaman manusia langsung
    if (message.assetPath != null) {
      await _controller.playHumanAudio(message.assetPath!);
      return;
    }

    // 2. Putar via dynamic neural speech / fallback TTS
    final textToSpeak = message.formattedDialogueText;
    await _controller.speakDynamic(textToSpeak);
  }

  /// Memperbolehkan dependency injection untuk testing
  void setProviderForTesting(SpeechOutputProvider testProvider) {
    _controller.setProviderForTesting(testProvider);
  }
}
