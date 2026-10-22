import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/services/speech/mock_speech_recognition_provider.dart';
import 'package:kogo_voice_learning/services/speech/speech_recognition_error_model.dart';
import 'package:kogo_voice_learning/services/speech/speech_recognition_provider.dart';
import 'package:kogo_voice_learning/services/speech/speech_recognition_result_model.dart';

void main() {
  group('SpeechRecognitionResultModel', () {
    test('instantiates with expected properties and defaults', () {
      const result = SpeechRecognitionResultModel(
        recognizedText: 'BOLA',
        confidence: 0.95,
        duration: Duration(milliseconds: 1200),
        provider: 'mock',
        locale: 'id_ID',
        isFinal: true,
      );

      expect(result.recognizedText, equals('BOLA'));
      expect(result.confidence, equals(0.95));
      expect(result.duration.inMilliseconds, equals(1200));
      expect(result.provider, equals('mock'));
      expect(result.locale, equals('id_ID'));
      expect(result.isFinal, isTrue);
    });

    test('toMap and fromMap serialize and deserialize correctly', () {
      const original = SpeechRecognitionResultModel(
        recognizedText: 'APEL',
        confidence: 0.88,
        duration: Duration(milliseconds: 850),
        provider: 'whisper_mock',
        locale: 'id_ID',
        isFinal: true,
      );

      final map = original.toMap();
      final fromMap = SpeechRecognitionResultModel.fromMap(map);

      expect(fromMap.recognizedText, equals(original.recognizedText));
      expect(fromMap.confidence, closeTo(original.confidence, 0.001));
      expect(fromMap.duration, equals(original.duration));
      expect(fromMap.provider, equals(original.provider));
      expect(fromMap.locale, equals(original.locale));
      expect(fromMap.isFinal, equals(original.isFinal));
    });

    test('copyWith updates specified fields only', () {
      const original = SpeechRecognitionResultModel(
        recognizedText: 'KUCING',
        provider: 'test_provider',
      );

      final updated = original.copyWith(
        confidence: 0.99,
        isFinal: true,
      );

      expect(updated.recognizedText, equals('KUCING'));
      expect(updated.provider, equals('test_provider'));
      expect(updated.confidence, equals(0.99));
      expect(updated.isFinal, isTrue);
    });
  });

  group('SpeechRecognitionErrorModel', () {
    test('instantiates with appropriate error codes and properties', () {
      const error = SpeechRecognitionErrorModel(
        code: SpeechRecognitionErrorCode.permissionDenied,
        message: 'Izin mikrofon tidak diberikan',
        provider: 'system_stt',
      );

      expect(error.code, equals(SpeechRecognitionErrorCode.permissionDenied));
      expect(error.message, contains('Izin mikrofon'));
      expect(error.provider, equals('system_stt'));
      expect(error.toString(), contains('permissionDenied'));
    });
  });

  group('SpeechRecognitionProvider Contract & Mock Implementation', () {
    test('lifecycle: initialize -> startListening -> emitResult -> stopListening -> dispose', () async {
      final SpeechRecognitionProvider provider = MockSpeechRecognitionProvider(
        name: 'test_mock_engine',
      );

      expect(provider.providerName, equals('test_mock_engine'));
      expect(provider.isInitialized, isFalse);
      expect(provider.isListening, isFalse);

      String? statusReceived;
      SpeechRecognitionErrorModel? errorReceived;

      // 1. Initialize
      final initOk = await provider.initialize(
        locale: 'id_ID',
        onStatus: (status) => statusReceived = status,
        onError: (err) => errorReceived = err,
      );

      expect(initOk, isTrue);
      expect(provider.isInitialized, isTrue);
      expect(statusReceived, equals('ready'));
      expect(errorReceived, isNull);

      // 2. Start Listening
      SpeechRecognitionResultModel? capturedResult;
      await provider.startListening(
        onResult: (res) {
          capturedResult = res;
        },
      );
      expect(provider.isListening, isTrue);

      // 3. Emit Result from provider
      (provider as MockSpeechRecognitionProvider).emitResult(
        const SpeechRecognitionResultModel(
          recognizedText: 'MATA',
          confidence: 0.92,
          provider: 'test_mock_engine',
          isFinal: true,
        ),
      );

      expect(capturedResult, isNotNull);
      expect(capturedResult!.recognizedText, equals('MATA'));
      expect(capturedResult!.confidence, equals(0.92));
      expect(capturedResult!.provider, equals('test_mock_engine'));

      // 4. Stop Listening
      await provider.stopListening();
      expect(provider.isListening, isFalse);

      // 5. Dispose
      await provider.dispose();
      expect(provider.isInitialized, isFalse);
      expect(provider.isListening, isFalse);
    });

    test('throws when startListening is called prior to initialize', () async {
      final provider = MockSpeechRecognitionProvider();
      expect(
        () => provider.startListening(onResult: (_) {}),
        throwsA(isA<SpeechRecognitionErrorModel>()),
      );
    });
  });
}
