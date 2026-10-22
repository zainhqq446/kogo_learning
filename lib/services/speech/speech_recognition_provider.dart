import 'speech_recognition_error_model.dart';
import 'speech_recognition_result_model.dart';

/// Abstraksi kontrak penyedia pengenalan suara (Speech Recognition Provider).
/// UI dan business logic bergantung pada interface ini, BUKAN langsung pada engine tertentu (Whisper/Sherpa/dll).
abstract class SpeechRecognitionProvider {
  /// Nama pengidentifikasi unik penyedia (misal: 'whisper', 'sherpa_onnx', 'system', 'mock').
  String get providerName;

  /// Status apakah provider sudah berhasil diinisialisasi.
  bool get isInitialized;

  /// Status apakah provider saat ini sedang aktif mendengarkan audio.
  bool get isListening;

  /// Menginisialisasi engine dan sumber daya yang diperlukan (model, permissions, audio pipeline).
  Future<bool> initialize({
    String? locale,
    void Function(String status)? onStatus,
    void Function(SpeechRecognitionErrorModel error)? onError,
  });

  /// Memulai proses mendengarkan ucapan mikrofon.
  /// Callback [onResult] dipanggil setiap kali ada hasil (interim maupun final).
  Future<void> startListening({
    required void Function(SpeechRecognitionResultModel result) onResult,
    Duration? timeout,
    List<String>? expectedVocabulary,
  });

  /// Menghentikan proses mendengarkan dan memproses audio yang sudah terekam untuk menghasilkan evaluasi final.
  Future<void> stopListening();

  /// Membatalkan proses mendengarkan dan membuang audio buffer tanpa memproses hasil.
  Future<void> cancelListening();

  /// Membersihkan seluruh resource, memori, model, atau stream yang digunakan oleh provider.
  Future<void> dispose();
}
