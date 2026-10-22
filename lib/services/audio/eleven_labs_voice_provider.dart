import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'eleven_labs_dialogue_session.dart';
import 'eleven_labs_tts_service.dart';
import 'speech_output_provider.dart';
import 'voice_cache.dart';

/// Implementasi SpeechOutputProvider resmi berbasis ElevenLabs Voice Engine.
/// Menyediakan sintesis suara ekspresif, hangat, ramah anak Bahasa Indonesia
/// sebagai satu kesatuan unit ucapan utuh (single conversational unit)
/// melalui ElevenLabs Text-to-Dialogue streaming WebSocket API (eleven_v4_turbo).
class ElevenLabsVoiceProvider implements SpeechOutputProvider {
  final AudioPlayer _audioPlayer;
  final ElevenLabsTtsService _elevenLabsTtsService;
  final ElevenLabsDialogueSession _dialogueSession;
  final VoiceCache _voiceCache = VoiceCache.instance;

  bool _isPlaying = false;
  final _isPlayingController = StreamController<bool>.broadcast();
  StreamSubscription? _playerCompleteSub;
  Completer<void>? _currentPlayCompleter;

  ElevenLabsVoiceProvider({
    AudioPlayer? audioPlayer,
    ElevenLabsTtsService? elevenLabsTtsService,
    ElevenLabsDialogueSession? dialogueSession,
  })  : _audioPlayer = audioPlayer ?? AudioPlayer(),
        _elevenLabsTtsService = elevenLabsTtsService ?? ElevenLabsTtsService(),
        _dialogueSession = dialogueSession ?? ElevenLabsDialogueSession() {
    _init();
  }

  ElevenLabsTtsService get ttsService => _elevenLabsTtsService;
  ElevenLabsDialogueSession get dialogueSession => _dialogueSession;

  void _init() {
    _playerCompleteSub = _audioPlayer.onPlayerComplete.listen((_) {
      _isPlaying = false;
      _isPlayingController.add(false);
      if (!(_currentPlayCompleter?.isCompleted ?? true)) {
        _currentPlayCompleter?.complete();
      }
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      final playing = state == PlayerState.playing;
      if (_isPlaying != playing) {
        _isPlaying = playing;
        _isPlayingController.add(playing);
      }
    });
  }

  @override
  bool get isPlaying => _isPlaying;

  @override
  Stream<bool> get isPlayingStream => _isPlayingController.stream;

  @override
  Future<void> playHuman(String assetPath) async {
    await stop();

    final completer = Completer<void>();
    _currentPlayCompleter = completer;

    _isPlaying = true;
    _isPlayingController.add(true);

    try {
      final cleanPath = assetPath.startsWith('assets/')
          ? assetPath.substring(7)
          : assetPath;

      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource(cleanPath));

      await completer.future.timeout(
        const Duration(seconds: 6),
        onTimeout: () {
          _isPlaying = false;
          _isPlayingController.add(false);
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ElevenLabsVoiceProvider] playHuman error ($assetPath): $e');
      }
      _isPlaying = false;
      _isPlayingController.add(false);
    }
  }

  @override
  Future<void> speakDynamicText(String text) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;

    await stop();
    _isPlaying = true;
    _isPlayingController.add(true);

    try {
      final cacheKey = 'eleven_${_dialogueSession.voiceId}_$cleanText';
      Uint8List? audioBytes;

      if (_voiceCache.contains(cacheKey)) {
        audioBytes = _voiceCache.get(cacheKey);
      } else {
        // 1. Jalur Utama: WebSocket Persistent Dialogue Streaming (v4 Turbo)
        if (_dialogueSession.hasApiKey) {
          audioBytes = await _dialogueSession.sendTurn(cleanText);

          // JANGAN fallback diam-diam ke Flash jika v4 Turbo gagal atau mengembalikan null/empty
          if (audioBytes == null || audioBytes.isEmpty) {
            if (kDebugMode) {
              debugPrint(
                '[V4 TURBO ERROR]\n'
                'stage=speakDynamicText\n'
                'operation_id=0\n'
                'message=ElevenLabs v4 Turbo dialogue session returned empty audio or failed\n'
                'text="$cleanText"',
              );
            }
            return;
          }
        } else if (_elevenLabsTtsService.hasApiKey || _elevenLabsTtsService.baseUrl.contains('/api')) {
          // Gunakan HTTP TTS via direct API key atau via backend proxy gateway
          audioBytes = await _elevenLabsTtsService.synthesizeSpeech(cleanText);
        }

        if (audioBytes != null && audioBytes.isNotEmpty) {
          _voiceCache.put(cacheKey, audioBytes);
        }
      }

      if (audioBytes != null && audioBytes.isNotEmpty) {
        final completer = Completer<void>();
        _currentPlayCompleter = completer;

        await _audioPlayer.stop();
        await _audioPlayer.play(BytesSource(audioBytes));

        await completer.future.timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            _isPlaying = false;
            _isPlayingController.add(false);
          },
        );
        return;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ElevenLabsVoiceProvider] speakDynamicText error: $e');
      }
    } finally {
      _isPlaying = false;
      _isPlayingController.add(false);
    }
  }

  @override
  Future<void> playPhraseAndWord({
    required String phraseAsset,
    required String word,
    String? wordAsset,
    Duration pauseDuration = const Duration(milliseconds: 250),
  }) async {
    // Satu kesatuan pemikiran percakapan (Single conversational unit):
    // Jika API key ElevenLabs aktif (pada dialogue session atau HTTP TTS service),
    // atau terhubung ke backend voice proxy, ucapkan frasa ajakan dan kata target
    // dalam satu kalimat alami dan hangat agar tidak terdengar patah atau terpotong.
    if (_dialogueSession.hasApiKey ||
        _elevenLabsTtsService.hasApiKey ||
        _elevenLabsTtsService.baseUrl.contains('/api')) {
      final combinedUtterance = 'Sekarang, coba ucapkan $word!';
      await speakDynamicText(combinedUtterance);
      return;
    }

    // Jika offline / tanpa API key dan aset suara manusia tersedia, putar berurutan
    await playHuman(phraseAsset);

    if (pauseDuration > Duration.zero) {
      await Future<void>.delayed(pauseDuration);
    }

    if (wordAsset != null) {
      await playHuman(wordAsset);
    } else {
      await speakDynamicText(word);
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      await _dialogueSession.stop();
    } catch (_) {}
    _isPlaying = false;
    _isPlayingController.add(false);
    if (!(_currentPlayCompleter?.isCompleted ?? true)) {
      _currentPlayCompleter?.complete();
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _playerCompleteSub?.cancel();
    await _audioPlayer.dispose();
    await _dialogueSession.dispose();
    _elevenLabsTtsService.dispose();
    await _isPlayingController.close();
  }
}
