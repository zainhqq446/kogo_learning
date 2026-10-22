import 'kogo_voice_style.dart';

/// Emosi suara untuk memberikan ekspresi vokal yang natural dan responsif.
enum VoiceEmotion {
  excited,      // Sangat senang & gembira saat anak berhasil (Correct)
  celebratory,  // Lebih energetik & spontan saat streak atau pencapaian
  encouraging,  // Optimistis, santai & suportif saat hampir benar
  gentle,       // Lembut, menenangkan, tidak menghakimi saat salah/retry
  patient,      // Sabar, tenang & membantu saat suara tidak terdengar
  curious,      // Menstimulasi rasa ingin tahu anak saat intro/instruksi
  playful,      // Ceria dan mengajak bermain (Game intro & explanation)
  warm,         // Hangat, bangga dan mendampingi (Completion / default)
}

/// Representasi pesan suara yang telah diproses oleh VoiceMessageSelector,
/// siap diputar oleh VoiceOutputProvider melalui audio rekaman atau neural TTS.
class VoiceMessage {
  /// Kalimat utama yang diucapkan (misal: "Bagus sekali!")
  final String text;

  /// Reaksi mikro spontan di awal kalimat (misal: "Wah!", "Yeay!", "Wow!")
  final String? microReaction;

  /// Path ke file audio lokal (jika tersedia dari koleksi rekaman aset)
  final String? assetPath;

  /// Emosi vokal yang harus direfleksikan dalam intonasi suara
  final VoiceEmotion emotion;

  /// Konfigurasi gaya suara (pitch, speech rate, dsb.)
  final KogoVoiceStyle voiceStyle;

  /// Instruksi spesifik per-event untuk steerable neural TTS
  final String customInstruction;

  /// Menandakan apakah pesan ini berasal dari frasa statis yang di-cache
  final bool isStatic;

  const VoiceMessage({
    required this.text,
    this.microReaction,
    this.assetPath,
    this.emotion = VoiceEmotion.warm,
    this.voiceStyle = KogoVoiceStyle.childFriendly,
    this.customInstruction = '',
    this.isStatic = true,
  });

  /// Kalimat lengkap termasuk micro-reaction dan jeda natural untuk TTS
  String get fullSpokenText {
    if (microReaction != null && microReaction!.trim().isNotEmpty) {
      return '$microReaction... $text';
    }
    return text;
  }

  /// Format teks percakapan dengan audio tag terkontrol untuk model conversational (eleven_v4_turbo / v3)
  String get formattedDialogueText {
    final baseText = fullSpokenText;
    final tag = _audioTagForEmotion(emotion, customInstruction);
    if (tag.isNotEmpty) {
      return '$tag $baseText';
    }
    return baseText;
  }

  static String _audioTagForEmotion(VoiceEmotion emotion, [String customInstruction = '']) {
    final lower = customInstruction.toLowerCase();
    if (lower.contains('excitement') || lower.contains('celebrate') || lower.contains('energetic')) {
      return '[excited]';
    }
    if (lower.contains('gentle') || lower.contains('reassuring') || lower.contains('patient') || lower.contains('never disappointed')) {
      return '[gently]';
    }
    if (lower.contains('curious') || lower.contains('optimistic')) {
      return '[curious]';
    }
    if (lower.contains('cheerful') || lower.contains('playful') || lower.contains('proud')) {
      return '[cheerfully]';
    }

    switch (emotion) {
      case VoiceEmotion.excited:
        return '[excited]';
      case VoiceEmotion.celebratory:
        return '[excited]';
      case VoiceEmotion.encouraging:
        return '[curious]';
      case VoiceEmotion.gentle:
        return '[gently]';
      case VoiceEmotion.patient:
        return '[gently]';
      case VoiceEmotion.curious:
        return '[curious]';
      case VoiceEmotion.playful:
        return '[cheerfully]';
      case VoiceEmotion.warm:
        return '[cheerfully]';
    }
  }

  @override
  String toString() => 'VoiceMessage(text: "$text", micro: "$microReaction", emotion: $emotion, asset: $assetPath, instruction: "$customInstruction")';
}
