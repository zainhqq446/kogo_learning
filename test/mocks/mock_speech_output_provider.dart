import 'dart:async';
import 'package:kogo_voice_learning/services/audio/speech_output_provider.dart';

/// Mock SpeechOutputProvider untuk unit testing dan widget testing.
/// Mencegah ketergantungan pada native audio platform channel saat running flutter test.
class MockSpeechOutputProvider implements SpeechOutputProvider {
  final List<String> playedAudios = [];
  final List<String> spokenTexts = [];
  bool _isPlaying = false;
  final _isPlayingController = StreamController<bool>.broadcast();

  @override
  bool get isPlaying => _isPlaying;

  @override
  Stream<bool> get isPlayingStream => _isPlayingController.stream;

  @override
  Future<void> playHuman(String assetPath) async {
    playedAudios.add(assetPath);
    _isPlaying = false;
  }

  @override
  Future<void> speakDynamicText(String text) async {
    spokenTexts.add(text);
    _isPlaying = false;
  }

  @override
  Future<void> playPhraseAndWord({
    required String phraseAsset,
    required String word,
    String? wordAsset,
    Duration pauseDuration = const Duration(milliseconds: 250),
  }) async {
    playedAudios.add(phraseAsset);
    if (wordAsset != null) {
      playedAudios.add(wordAsset);
    } else {
      spokenTexts.add(word);
    }
  }

  @override
  Future<void> stop() async {
    _isPlaying = false;
    _isPlayingController.add(false);
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _isPlayingController.close();
  }

  void clear() {
    playedAudios.clear();
    spokenTexts.clear();
  }
}
