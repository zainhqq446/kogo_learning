/// Model hasil pengenalan ucapan (Speech Recognition Result).
/// Memisahkan metadata engine secara bersih dan terstandarisasi.
class SpeechRecognitionResultModel {
  /// Teks yang berhasil dikenali oleh mesin pengenal ucapan.
  final String recognizedText;

  /// Tingkat keyakinan/confidence dari pengenalan (0.0 sampai 1.0).
  final double confidence;

  /// Durasi proses pengenalan suara.
  final Duration duration;

  /// Nama penyedia / engine (misal: 'sherpa_onnx', 'whisper', 'system_stt', 'mock').
  final String provider;

  /// Bahasa / locale pengenalan (misal: 'id_ID').
  final String locale;

  /// Menandakan apakah ini hasil akhir (final) atau hasil sementara (partial/interim).
  final bool isFinal;

  const SpeechRecognitionResultModel({
    required this.recognizedText,
    this.confidence = 1.0,
    this.duration = Duration.zero,
    required this.provider,
    this.locale = 'id_ID',
    this.isFinal = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'recognized_text': recognizedText,
      'confidence': confidence,
      'duration_ms': duration.inMilliseconds,
      'provider': provider,
      'locale': locale,
      'is_final': isFinal ? 1 : 0,
    };
  }

  factory SpeechRecognitionResultModel.fromMap(Map<String, dynamic> map) {
    return SpeechRecognitionResultModel(
      recognizedText: map['recognized_text'] as String? ?? '',
      confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
      duration: Duration(milliseconds: map['duration_ms'] as int? ?? 0),
      provider: map['provider'] as String? ?? 'unknown',
      locale: map['locale'] as String? ?? 'id_ID',
      isFinal: (map['is_final'] as int? ?? 1) == 1,
    );
  }

  SpeechRecognitionResultModel copyWith({
    String? recognizedText,
    double? confidence,
    Duration? duration,
    String? provider,
    String? locale,
    bool? isFinal,
  }) {
    return SpeechRecognitionResultModel(
      recognizedText: recognizedText ?? this.recognizedText,
      confidence: confidence ?? this.confidence,
      duration: duration ?? this.duration,
      provider: provider ?? this.provider,
      locale: locale ?? this.locale,
      isFinal: isFinal ?? this.isFinal,
    );
  }

  @override
  String toString() {
    return 'SpeechRecognitionResultModel(text: "$recognizedText", conf: $confidence, dur: ${duration.inMilliseconds}ms, prov: $provider, final: $isFinal)';
  }
}
