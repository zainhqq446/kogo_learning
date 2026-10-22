/// Jenis kategori kegagalan atau error pada speech recognition.
enum SpeechRecognitionErrorCode {
  /// Izin mikrofon ditolak atau belum diberikan oleh pengguna.
  permissionDenied,

  /// Engine atau layanan tidak tersedia pada sistem/perangkat.
  notAvailable,

  /// Model belum dimuat atau inisialisasi belum selesai.
  notInitialized,

  /// Tidak ada ucapan atau kata yang cocok (no match).
  noSpeechDetected,

  /// Mikrofon sedang sibuk atau dipakai oleh proses lain.
  audioRecordingError,

  /// Batas waktu mendengarkan habis (timeout).
  timeout,

  /// Kesalahan internal pada engine atau library bawaan.
  internalError,

  /// Kesalahan umum atau belum terklasifikasi.
  unknown,
}

/// Model error yang jelas dan terstandarisasi untuk speech recognition.
class SpeechRecognitionErrorModel implements Exception {
  final SpeechRecognitionErrorCode code;
  final String message;
  final String? provider;
  final Object? originalError;

  const SpeechRecognitionErrorModel({
    required this.code,
    required this.message,
    this.provider,
    this.originalError,
  });

  @override
  String toString() {
    return 'SpeechRecognitionErrorModel(code: $code, message: "$message", provider: $provider)';
  }
}
