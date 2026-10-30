import 'dart:math' as math;

import '../../core/curriculum/curriculum.dart';
import '../../core/curriculum/vocabulary.dart';
import 'indonesian_text.dart';
import 'prosody_planner.dart';

/// Satu kalimat Kogo beserta suasananya.
class VoiceLine {
  const VoiceLine(this.text, this.mood, {this.emphasize});

  final String text;
  final SpeechMood mood;
  final String? emphasize;
}

/// Kumpulan kalimat Kogo. Pilihan acak tidak mengulang kalimat yang sama
/// dua kali berturut-turut agar terdengar alami.
class VoiceLines {
  VoiceLines({math.Random? random}) : _random = random ?? math.Random();

  final math.Random _random;
  final Map<String, int> _last = {};

  static const _correct = ['Hebat!', 'Pintar sekali!', 'Betul! Kamu keren!', 'Wah, benar sekali!', 'Bagus sekali!', 'Yei, tepat!', 'Hore, kamu berhasil!'];
  static const _wrong = ['Belum tepat. Ayo coba lagi!', 'Tidak apa-apa, coba lagi, ya!', 'Hmm, coba yang lain, ya.', 'Sedikit lagi! Ayo coba lagi!'];
  static const _almost = ['Hampir benar! Coba sekali lagi, ya?', 'Sedikit lagi! Ayo ucapkan lebih jelas!', 'Wah, hampir! Dengarkan Kogo, lalu ulangi, ya.'];
  static const _noSpeech = ['Kogo belum mendengar suaramu. Ucapkan lebih keras, ya!', 'Hmm, suaranya belum terdengar. Coba lagi, ya?'];
  static const _streak = ['Wah, benar terus! Kamu hebat sekali!', 'Luar biasa! Kamu pintar!'];

  VoiceLine _pick(String key, List<String> pool, SpeechMood mood) {
    var index = _random.nextInt(pool.length);
    if (pool.length > 1 && index == _last[key]) index = (index + 1) % pool.length;
    _last[key] = index;
    return VoiceLine(pool[index], mood);
  }

  VoiceLine correct() => _pick('correct', _correct, SpeechMood.celebratory);
  VoiceLine wrong() => _pick('wrong', _wrong, SpeechMood.encouraging);
  VoiceLine almost() => _pick('almost', _almost, SpeechMood.encouraging);
  VoiceLine noSpeech() => _pick('noSpeech', _noSpeech, SpeechMood.gentle);
  VoiceLine streak() => _pick('streak', _streak, SpeechMood.excited);

  /// Tanpa nama anak agar dapat direkam sekali; nama tetap tampil di layar.
  static VoiceLine greeting() => const VoiceLine('Halo, teman! Aku Kogo. Ayo kita belajar kata bersama!', SpeechMood.playful);

  static VoiceLine welcomeNew() => const VoiceLine('Halo! Aku Kogo. Siapa namamu? Minta bantuan Ayah atau Bunda untuk mengisi, ya!', SpeechMood.warm);

  static VoiceLine materiIntro(Materi materi) => VoiceLine('Ayo belajar ${materi.title}! Pilih lingkaran yang bergoyang, ya.', SpeechMood.playful);

  static VoiceLine locked() => const VoiceLine('Yang ini masih terkunci. Selesaikan dulu permainan sebelumnya, ya!', SpeechMood.gentle);

  static VoiceLine gameIntro(GameType game) => switch (game) {
    GameType.listenRepeat => const VoiceLine('Dengarkan baik-baik, lalu ucapkan, ya!', SpeechMood.playful),
    GameType.findObject => const VoiceLine('Ayo cari gambar yang tepat!', SpeechMood.playful),
    GameType.missingLetter => const VoiceLine('Ada huruf yang hilang. Huruf apa, ya?', SpeechMood.curious),
    GameType.matching => const VoiceLine('Cocokkan kata dengan gambarnya, ya!', SpeechMood.playful),
    GameType.listening => const VoiceLine('Dengarkan baik-baik, lalu pilih kata yang kamu dengar!', SpeechMood.curious),
    GameType.fillBlank => const VoiceLine('Isi huruf yang kosong, ya!', SpeechMood.playful),
  };

  /// "Ini apel. Ayo ucapkan: apel!" — kata target diberi penekanan.
  static VoiceLine listenRepeatPrompt(VocabItem item) {
    if (item.isLetter) {
      final name = IndonesianText.letterNames[item.text] ?? item.text;
      return VoiceLine('Ini huruf $name. $name untuk ${item.letter!.text}. Ayo ucapkan: $name!', SpeechMood.playful, emphasize: name);
    }
    return VoiceLine('Ini ${item.text}. Ayo ucapkan: ${item.text}!', SpeechMood.playful, emphasize: item.text);
  }

  static VoiceLine findObjectPrompt(String letter) {
    final name = IndonesianText.letterNames[letter.toLowerCase()] ?? letter;
    return VoiceLine('Cari benda yang dimulai dengan huruf $name!', SpeechMood.curious, emphasize: name);
  }

  static VoiceLine reveal(VocabItem item) {
    final word = item.isLetter ? (IndonesianText.letterNames[item.text] ?? item.text) : item.text;
    return VoiceLine('Tidak apa-apa! Ini $word. Ayo kita lanjut!', SpeechMood.gentle, emphasize: word);
  }

  static VoiceLine completion(int stars) => switch (stars) {
    3 => VoiceLine('Hore! Kamu dapat $stars bintang! Hebat sekali!', SpeechMood.celebratory),
    2 => VoiceLine('Yei! Kamu dapat $stars bintang! Ayo terus belajar!', SpeechMood.excited),
    _ => VoiceLine('Kamu dapat $stars bintang! Ayo coba lagi supaya dapat lebih banyak, ya?', SpeechMood.warm),
  };

  static VoiceLine newReward(RewardTier tier) => VoiceLine('Wah! Kamu mendapat hadiah ${tier.title}! Hebat sekali!', SpeechMood.celebratory);

  static VoiceLine rewardsPage(int stars) => stars == 0
      ? const VoiceLine('Kumpulkan bintang untuk membuka hadiah, ya!', SpeechMood.warm)
      : const VoiceLine('Wah, bintangmu sudah terkumpul. Hebat! Ayo kumpulkan lagi!', SpeechMood.excited);

  static const allMatched = VoiceLine('Sempurna! Semua cocok!', SpeechMood.celebratory);
  static const voiceCheck = VoiceLine('Halo! Aku Kogo. Apakah suaraku terdengar jelas?', SpeechMood.playful);

  /// "Hebat! bola!" — pujian lalu kata yang benar.
  static String praiseWithWord(VoiceLine line, String word) => '${line.text} $word!';

  /// "Bola! Hebat!" — kata yang dipilih lalu pujian.
  static String wordThenLine(String word, VoiceLine line) => '$word! ${line.text}';

  /// "Itu bola. Coba lagi, ya!" — menyebut pilihan yang salah.
  static String thatIs(String word, VoiceLine line) => 'Itu $word. ${line.text}';

  /// Semua kalimat acak (untuk daftar rekaman).
  static List<String> get pooledTexts => [..._correct, ..._wrong, ..._almost, ..._noSpeech, ..._streak];
}
