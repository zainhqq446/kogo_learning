import 'dart:async';
import 'package:flutter/foundation.dart';
import 'audio_message_manager.dart';
import 'kogo_voice_style.dart';
import 'voice_interaction_controller.dart';

/// Adapter kompatibilitas KogoTtsService agar pemanggilan lama dialihkan ke
/// VoiceInteractionController & AudioMessageManager (Hybrid Voice System rekaman manusia).
/// Mencegah breaking changes pada modul yang memanggil `KogoTtsService.instance.speak(...)`.
class KogoTtsService {
  KogoTtsService._internal();
  static final KogoTtsService instance = KogoTtsService._internal();

  final VoiceInteractionController _voiceController = VoiceInteractionController.instance;
  final AudioMessageManager _messageManager = AudioMessageManager.instance;
  KogoVoiceStyle _currentStyle = KogoVoiceStyle.childFriendly;

  KogoVoiceStyle get currentStyle => _currentStyle;

  Future<void> setStyle(KogoVoiceStyle style) async {
    _currentStyle = style;
  }

  /// Mengucapkan ucapan atau memutar audio manusia yang sesuai.
  Future<void> speak(String text, {bool interrupt = true, KogoVoiceStyle? style}) async {
    if (text.trim().isEmpty) return;

    try {
      final cleanText = text.trim();
      final wordAsset = _messageManager.getWordAssetPath(cleanText);

      if (wordAsset != null) {
        await _voiceController.playHumanAudio(wordAsset);
        return;
      }

      // Deteksi ajakan bicara dengan kata target
      if (cleanText.toLowerCase().contains('ucapkan') ||
          cleanText.toLowerCase().contains('bilang') ||
          cleanText.toLowerCase().contains('katakan')) {
        // Ekstrak kata terakhir atau kata kunci
        final parts = cleanText.split(RegExp(r'\s+'));
        final lastWord = parts.isNotEmpty ? parts.last.replaceAll(RegExp(r'[^\w]'), '') : cleanText;
        await _voiceController.playSpeechPrompt(lastWord);
        return;
      }

      // Cek apakah teks cocok dengan frasa instruksi atau feedback
      if (cleanText.toLowerCase().contains('selesai') || cleanText.toLowerCase().contains('semua')) {
        await _voiceController.playCompletion();
        return;
      }

      if (cleanText.toLowerCase().contains('hebat') ||
          cleanText.toLowerCase().contains('benar') ||
          cleanText.toLowerCase().contains('tepat') ||
          cleanText.toLowerCase().contains('bagus') ||
          cleanText.toLowerCase().contains('berhasil')) {
        await _voiceController.playEvaluationFeedback(
          AudioContextInfo(targetWord: cleanText, isCorrect: true),
        );
        return;
      }

      if (cleanText.toLowerCase().contains('coba lagi') ||
          cleanText.toLowerCase().contains('belum') ||
          cleanText.toLowerCase().contains('sedikit lagi')) {
        await _voiceController.playEvaluationFeedback(
          AudioContextInfo(targetWord: cleanText, isCorrect: false),
        );
        return;
      }

      // Fallback dynamic speech
      await _voiceController.speakDynamic(cleanText);
    } catch (e) {
      debugPrint('[KogoTtsService] Speak error: $e');
    }
  }

  /// Menghentikan seluruh audio
  Future<void> stop() async {
    await _voiceController.stop();
  }
}
