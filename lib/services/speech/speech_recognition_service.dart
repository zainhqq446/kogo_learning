import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechRecognitionService {
  SpeechRecognitionService._();

  static final SpeechRecognitionService instance =
      SpeechRecognitionService._();

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _initialized = false;
  bool _available = false;
  String? _localeId;

  bool get isAvailable => _available;
  bool get isListening => _speech.isListening;
  String? get localeId => _localeId;

  Future<bool> initialize({
    void Function(String status)? onStatus,
    void Function(SpeechRecognitionError error)? onError,
  }) async {
    if (_initialized) {
      return _available;
    }

    _available = await _speech.initialize(
      debugLogging: true,
      onStatus: onStatus,
      onError: onError,
    );

    _initialized = true;

    if (!_available) {
      return false;
    }

    final locales = await _speech.locales();

    // Cari Bahasa Indonesia bila tersedia.
    for (final locale in locales) {
      final id = locale.localeId.toLowerCase();

      if (id == 'id_id' ||
          id == 'id-id' ||
          id == 'in_id' ||
          id == 'in-id') {
        _localeId = locale.localeId;
        break;
      }
    }

    return _available;
  }

  Future<void> listen({
    required void Function(SpeechRecognitionResult result) onResult,
  }) async {
    final available = await initialize();

    if (!available) {
      throw StateError(
        'Speech recognition tidak tersedia pada perangkat.',
      );
    }

    await _speech.listen(
      onResult: onResult,
      listenOptions: stt.SpeechListenOptions(
        // Untuk latihan satu huruf/kata,
        // kita hanya membutuhkan hasil final.
        partialResults: false,

        // Error no_match tidak kita gunakan
        // untuk menghentikan aplikasi secara kasar.
        cancelOnError: false,

        // Gunakan recognition service perangkat.
        onDevice: false,

        localeId: _localeId,

        // Satu sesi maksimum 10 detik.
        listenFor: const Duration(seconds: 10),

        // Berhenti setelah 3 detik tanpa ucapan.
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> stop() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
  }

  Future<void> cancel() async {
    if (_speech.isListening) {
      await _speech.cancel();
    }
  }
}