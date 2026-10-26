import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/services/audio/indonesian_text.dart';
import 'package:kogo_voice_learning/services/audio/prosody_planner.dart';

void main() {
  group('IndonesianText', () {
    test('numbers become Indonesian words', () {
      expect(IndonesianText.numberToWords(0), 'nol');
      expect(IndonesianText.numberToWords(3), 'tiga');
      expect(IndonesianText.numberToWords(11), 'sebelas');
      expect(IndonesianText.numberToWords(12), 'dua belas');
      expect(IndonesianText.numberToWords(40), 'empat puluh');
      expect(IndonesianText.numberToWords(72), 'tujuh puluh dua');
      expect(IndonesianText.numberToWords(100), 'seratus');
      expect(IndonesianText.numberToWords(250), 'dua ratus lima puluh');
    });

    test('forSpeech strips emoji/tags, keeps reduplication, spells numbers', () {
      expect(IndonesianText.forSpeech('Hore! 🎉 Kamu dapat 3 bintang ⭐'), 'Hore! Kamu dapat tiga bintang');
      expect(IndonesianText.forSpeech('[excited] Wah, kupu-kupu!'), 'Wah, kupu-kupu!');
      expect(IndonesianText.forSpeech('ke - lin - ci'), 'ke lin ci');
    });

    test('normalize for ASR comparison', () {
      expect(IndonesianText.normalize('Kupu-Kupu!'), 'kupu kupu');
      expect(IndonesianText.normalize('  Apel   MERAH. '), 'apel merah');
    });

    test('every letter has a spoken name', () {
      for (final c in 'abcdefghijklmnopqrstuvwxyz'.split('')) {
        expect(IndonesianText.letterNames[c], isNotNull, reason: c);
      }
    });
  });

  group('ProsodyPlanner intonation', () {
    test('exclamation is higher and faster than a statement', () {
      final statement = ProsodyPlanner.plan('Ini apel.').single;
      final exclaim = ProsodyPlanner.plan('Hebat sekali!').single;
      expect(exclaim.pitch, greaterThan(statement.pitch));
      expect(exclaim.rate, greaterThan(statement.rate));
    });

    test('yes/no question rises more than wh-question and keeps "?"', () {
      final yesNo = ProsodyPlanner.plan('Kamu siap?').single;
      final wh = ProsodyPlanner.plan('Huruf apa yang hilang?').single;
      expect(yesNo.text.endsWith('?'), isTrue);
      expect(yesNo.pitch, greaterThan(wh.pitch));
      expect(yesNo.pauseAfterMs, 500);
    });

    test('ajakan starting with "Ayo" is treated as exclamation', () {
      final ayo = ProsodyPlanner.plan('Ayo kita belajar.').single;
      final plain = ProsodyPlanner.plan('Kita belajar.').single;
      expect(ayo.pitch, greaterThan(plain.pitch));
    });

    test('splits sentences and isolates the target word slowly', () {
      final chunks = ProsodyPlanner.plan('Ini kelinci. Ayo ucapkan kelinci!', emphasize: 'kelinci');
      expect(chunks.map((c) => c.text), ['Ini', 'kelinci.', 'Ayo ucapkan', 'kelinci!']);
      final targets = chunks.where((c) => c.text.startsWith('kelinci')).toList();
      for (final t in targets) {
        expect(t.rate, ProsodyPlanner.targetRate);
      }
      expect(chunks[2].pauseAfterMs, 250, reason: 'pause before the target word');
    });

    test('mood changes the base voice and values stay clamped', () {
      final gentle = ProsodyPlanner.plan('Coba lagi, ya.', mood: SpeechMood.gentle).single;
      final party = ProsodyPlanner.plan('Hore!', mood: SpeechMood.celebratory).single;
      expect(party.pitch, greaterThan(gentle.pitch));
      for (final c in [gentle, party]) {
        expect(c.pitch, inInclusiveRange(ProsodyPlanner.minPitch, ProsodyPlanner.maxPitch));
        expect(c.rate, inInclusiveRange(ProsodyPlanner.minRate, ProsodyPlanner.maxRate));
      }
    });

    test('syllable spelling ends with the whole word', () {
      final chunks = ProsodyPlanner.syllables(['ke', 'lin', 'ci'], 'kelinci');
      expect(chunks.map((c) => c.text), ['ke', 'lin', 'ci', 'kelinci!']);
      expect(chunks.first.rate, ProsodyPlanner.minRate);
    });

    test('empty text produces nothing', () {
      expect(ProsodyPlanner.plan('  🎉 '), isEmpty);
    });
  });
}
