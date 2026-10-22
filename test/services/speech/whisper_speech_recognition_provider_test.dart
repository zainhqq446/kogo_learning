import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/services/speech/speech_recognition_error_model.dart';
import 'package:kogo_voice_learning/services/speech/speech_recognition_provider.dart';
import 'package:kogo_voice_learning/services/speech/whisper_speech_recognition_provider.dart';

void main() {
  test('WhisperSpeechRecognitionProvider satisfies SpeechRecognitionProvider contract', () {
    final SpeechRecognitionProvider provider = WhisperSpeechRecognitionProvider.instance;

    expect(provider.providerName, equals('whisper_tiny'));
    expect(provider.isInitialized, isFalse);
    expect(provider.isListening, isFalse);
  });

  test('WhisperSpeechRecognitionProvider enforces initialization before listening', () async {
    final provider = WhisperSpeechRecognitionProvider.instance;

    expect(
      () => provider.startListening(
        onResult: (_) {},
        expectedVocabulary: ['BOLA'],
      ),
      throwsA(
        isA<SpeechRecognitionErrorModel>().having(
          (e) => e.code,
          'code',
          equals(SpeechRecognitionErrorCode.notInitialized),
        ),
      ),
    );
  });

  test('WhisperSpeechRecognitionProvider exposes latency metrics (start, inference, total)', () {
    final provider = WhisperSpeechRecognitionProvider.instance;

    expect(provider.lastStartLatency, equals(Duration.zero));
    expect(provider.lastInferenceLatency, equals(Duration.zero));
    expect(provider.lastTotalResponseTime, equals(Duration.zero));
  });

  test('WhisperSpeechRecognitionProvider cancel and dispose clean up without exception', () async {
    final provider = WhisperSpeechRecognitionProvider.instance;

    await provider.cancelListening();
    expect(provider.isListening, isFalse);

    await provider.dispose();
    expect(provider.isInitialized, isFalse);
    expect(provider.isListening, isFalse);
  });
}
