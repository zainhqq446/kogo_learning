/// Konfigurasi gaya suara dan Text-to-Speech untuk Kogo Voice Learning.
/// Dirancang khusus agar suara terdengar ramah, ceria, hangat, dan memberi semangat
/// untuk anak usia dini (5–6 tahun).
class KogoVoiceStyle {
  /// Kecepatan bicara (0.0 - 1.0). 0.42 memberikan tempo sedang yang tenang dan jelas bagi anak.
  final double speechRate;

  /// Nada suara / intonasi (0.5 - 2.0). 1.18 memberikan nada lebih ceria dan hangat.
  final double pitch;

  /// Volume audio (0.0 - 1.0).
  final double volume;

  /// Bahasa / locale untuk TTS (default: Bahasa Indonesia).
  final String language;

  /// Deskripsi personality suara
  final String personality;

  const KogoVoiceStyle({
    this.speechRate = 0.44,
    this.pitch = 1.18,
    this.volume = 1.0,
    this.language = 'id-ID',
    this.personality = 'friendly, cheerful, encouraging, warm, playful, patient',
  });

  /// Gaya suara utama yang ramah anak, hangat, dan ekspresif.
  static const KogoVoiceStyle childFriendly = KogoVoiceStyle(
    speechRate: 0.44,
    pitch: 1.18,
    volume: 1.0,
    language: 'id-ID',
  );

  /// Gaya suara untuk instruksi tenang & jelas.
  static const KogoVoiceStyle gentleGuide = KogoVoiceStyle(
    speechRate: 0.42,
    pitch: 1.12,
    volume: 1.0,
    language: 'id-ID',
  );

  /// Gaya suara untuk selebrasi dan pencapaian ceria.
  static const KogoVoiceStyle celebratory = KogoVoiceStyle(
    speechRate: 0.46,
    pitch: 1.22,
    volume: 1.0,
    language: 'id-ID',
  );

  KogoVoiceStyle copyWith({
    double? speechRate,
    double? pitch,
    double? volume,
    String? language,
    String? personality,
  }) {
    return KogoVoiceStyle(
      speechRate: speechRate ?? this.speechRate,
      pitch: pitch ?? this.pitch,
      volume: volume ?? this.volume,
      language: language ?? this.language,
      personality: personality ?? this.personality,
    );
  }
}
