import '../../core/curriculum/vocabulary.dart';
import 'indonesian_text.dart';

/// Kunci rekaman suara Kogo. Dipakai bersama oleh aplikasi dan
/// `tool/voice_catalog.dart` sehingga teks yang direkam selalu cocok dengan
/// teks yang diucapkan.
class VoiceKeys {
  VoiceKeys._();

  static final _sentenceSplit = RegExp(r'(?<=[.!?])\s+');
  static final _spaces = RegExp(r'\s+');

  /// Teks ucapan yang dinormalkan (huruf kecil, spasi tunggal).
  static String key(String text) => IndonesianText.forSpeech(text).toLowerCase().replaceAll(_spaces, ' ').trim();

  /// Kalimat-kalimat dalam satu ucapan, dipisah setelah . ! atau ?.
  static List<String> sentences(String text) => IndonesianText.forSpeech(text).split(_sentenceSplit).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  static String word(VocabItem item) => key('${item.text}.');
  static String letter(String letter) => key(IndonesianText.letterNames[letter.toLowerCase()] ?? letter);
  static String spell(VocabItem item) => 'eja: ${key(item.text)}';
}
