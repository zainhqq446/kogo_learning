import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'openai_tts_service.dart';
import 'speech_output_provider.dart';

/// Implementasi Hybrid Voice Provider yang menggabungkan:
/// 1. Prerecorded Human Audio (Audioplayers dari assets/audio/)
/// 2. Prerecorded Word Audio jika kata target tersedia di assets/audio/words/
/// 3. Neural OpenAI TTS (gpt-4o-mini-tts: marin/cedar) via OpenAiTtsService
/// 4. FlutterTts offline fallback jika OpenAI service tidak aktif / offline.
class HybridSpeechOutputProvider implements SpeechOutputProvider {
  final AudioPlayer _audioPlayer;
  final OpenAiTtsService _openAiTtsService;
  FlutterTts? _dynamicTts;

  bool _isPlaying = false;
  final _isPlayingController = StreamController<bool>.broadcast();
  StreamSubscription? _playerCompleteSub;
  Completer<void>? _currentPlayCompleter;

  // Cache untuk kata yang sudah diperiksa ketersediaan audionya
  final Set<String> _knownWordAssets = {
    'a', 'b', 'c', 'd', 'e',
    'apel', 'bola', 'buku', 'meja', 'sapi', 'kaki',
    'sepatu', 'kereta', 'kelinci', 'kamera',
    'helikopter', 'matahari', 'laboratorium',
  };

  HybridSpeechOutputProvider({
    AudioPlayer? audioPlayer,
    OpenAiTtsService? openAiTtsService,
  })  : _audioPlayer = audioPlayer ?? AudioPlayer(),
        _openAiTtsService = openAiTtsService ?? OpenAiTtsService() {
    _init();
  }

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
      // audioplayers AssetSource path relatif terhadap folder 'assets/'
      final cleanPath = assetPath.startsWith('assets/')
          ? assetPath.substring(7)
          : assetPath;

      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource(cleanPath));

      // Timeout proteksi 6 detik jika onPlayerComplete terhambat
      await completer.future.timeout(
        const Duration(seconds: 6),
        onTimeout: () {
          _isPlaying = false;
          _isPlayingController.add(false);
        },
      );
    } catch (e) {
      debugPrint('[HybridSpeechOutputProvider] playHuman error ($assetPath): $e');
      _isPlaying = false;
      _isPlayingController.add(false);
    }
  }

  @override
  Future<void> speakDynamicText(String text) async {
    final normalized = text.trim().toLowerCase();
    if (_knownWordAssets.contains(normalized)) {
      await playHuman('assets/audio/words/$normalized.mp3');
      return;
    }

    // Dynamic voice synthesis: prioritaskan OpenAI gpt-4o-mini-tts (marin / cedar)
    await stop();
    _isPlaying = true;
    _isPlayingController.add(true);

    try {
      final neuralBytes = await _openAiTtsService.synthesizeSpeech(text);
      if (neuralBytes != null && neuralBytes.isNotEmpty) {
        final completer = Completer<void>();
        _currentPlayCompleter = completer;

        await _audioPlayer.stop();
        await _audioPlayer.play(BytesSource(neuralBytes));

        await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            _isPlaying = false;
            _isPlayingController.add(false);
          },
        );
        return;
      }

      // Offline / Local Fallback jika OpenAI tidak terkonfigurasi atau offline
      _dynamicTts ??= FlutterTts();
      await _dynamicTts?.setLanguage('id-ID');
      await _dynamicTts?.setSpeechRate(0.44);
      await _dynamicTts?.setPitch(1.15);

      final completer = Completer<void>();
      _dynamicTts?.setCompletionHandler(() {
        if (!completer.isCompleted) completer.complete();
      });
      _dynamicTts?.setErrorHandler((_) {
        if (!completer.isCompleted) completer.complete();
      });

      await _dynamicTts?.speak(text);
      await completer.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () {},
      );
    } catch (e) {
      debugPrint('[HybridSpeechOutputProvider] speakDynamicText error: $e');
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
    // 1. Putar frasa rekaman manusia ("Sekarang, coba ucapkan")
    await playHuman(phraseAsset);

    // 2. Jeda hening yang natural
    if (pauseDuration > Duration.zero) {
      await Future<void>.delayed(pauseDuration);
    }

    // 3. Putar kata target (prerecorded kata jika ada, atau fallback)
    final normalized = word.trim().toLowerCase();
    final assetToPlay = wordAsset ??
        (_knownWordAssets.contains(normalized) ? 'assets/audio/words/$normalized.mp3' : null);

    if (assetToPlay != null) {
      await playHuman(assetToPlay);
    } else {
      await speakDynamicText(word);
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      await _dynamicTts?.stop();
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
    _openAiTtsService.dispose();
    await _isPlayingController.close();
  }
}
