import 'dart:async';
import 'speech_recognition_error_model.dart';
import 'speech_recognition_provider.dart';
import 'speech_recognition_result_model.dart';

/// Implementasi Mock dari [SpeechRecognitionProvider] untuk testing terisolasi.
/// Memungkinkan pengujian menyeluruh tanpa membutuhkan perangkat keras mikrofon nyata.
class MockSpeechRecognitionProvider implements SpeechRecognitionProvider {
  final String _name;
  bool _initialized = false;
  bool _listening = false;
  void Function(SpeechRecognitionResultModel result)? _onResult;
  void Function(SpeechRecognitionErrorModel error)? _onError;

  MockSpeechRecognitionProvider({String? name})
      : _name = name ?? 'mock_provider';

  @override
  String get providerName => _name;

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isListening => _listening;

  @override
  Future<bool> initialize({
    String? locale,
    void Function(String status)? onStatus,
    void Function(SpeechRecognitionErrorModel error)? onError,
  }) async {
    _onError = onError;
    _initialized = true;
    onStatus?.call('ready');
    return true;
  }

  @override
  Future<void> startListening({
    required void Function(SpeechRecognitionResultModel result) onResult,
    Duration? timeout,
    List<String>? expectedVocabulary,
  }) async {
    if (!_initialized) {
      final err = SpeechRecognitionErrorModel(
        code: SpeechRecognitionErrorCode.notInitialized,
        message: 'Mock provider belum diinisialisasi',
        provider: _name,
      );
      _onError?.call(err);
      throw err;
    }

    _listening = true;
    _onResult = onResult;
  }

  @override
  Future<void> stopListening() async {
    _listening = false;
  }

  @override
  Future<void> cancelListening() async {
    _listening = false;
    _onResult = null;
  }

  @override
  Future<void> dispose() async {
    _listening = false;
    _initialized = false;
    _onResult = null;
    _onError = null;
  }

  /// Helper untuk menyimulasikan hasil deteksi suara dari provider
  void emitResult(SpeechRecognitionResultModel result) {
    if (_listening && _onResult != null) {
      _onResult!(result);
    }
  }

  /// Helper untuk menyimulasikan error dari provider
  void emitError(SpeechRecognitionErrorModel error) {
    _onError?.call(error);
  }
}
