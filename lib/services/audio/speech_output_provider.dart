import 'dart:async';

/// Kontrak abstrak penyedia output audio / suara Kogo.
/// Memisahkan pemutaran audio rekaman manusia (human prerecorded)
/// dan sintesis kata dinamis (dynamic word).
abstract class SpeechOutputProvider {
  /// Memutar file audio manusia prerecorded (dari asset bundle).
  Future<void> playHuman(String assetPath);

  /// Memutar kata/teks dinamis dengan mekanisme cache.
  Future<void> speakDynamicText(String text);

  /// Memutar frasa manusia diikuti kata target (human phrase + target word).
  Future<void> playPhraseAndWord({
    required String phraseAsset,
    required String word,
    String? wordAsset,
    Duration pauseDuration = const Duration(milliseconds: 250),
  });

  /// Menghentikan pemutaran audio yang sedang berjalan saat ini.
  Future<void> stop();

  /// Membersihkan sumber daya.
  Future<void> dispose();

  /// Mengetahui apakah audio sedang diputar.
  bool get isPlaying;

  /// Stream status pemutaran audio.
  Stream<bool> get isPlayingStream;
}
