import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/core/curriculum/vocabulary.dart';
import 'package:kogo_voice_learning/services/speech/pronunciation_evaluator.dart';

VocabItem word(String text) => [...vocabDuaSuku, ...vocabTigaSuku, ...vocabBeberapaKata].firstWhere((w) => w.text == text);
VocabItem letter(String l) => vocabHuruf.firstWhere((w) => w.text == l);

SpeechBand band(VocabItem item, List<String> heard) => PronunciationEvaluator.evaluate(item, heard).band;

void main() {
  group('words', () {
    test('exact match with punctuation and capitals is correct and strict', () {
      final r = PronunciationEvaluator.evaluate(word('bola'), ['Bola.']);
      expect(r.band, SpeechBand.correct);
      expect(r.strictMatch, isTrue);
      expect(r.similarity, 1.0);
    });

    test('fillers and repetitions around the word are ignored', () {
      expect(band(word('apel'), ['ini apel']), SpeechBand.correct);
      expect(band(word('kucing'), ['eh kucing kucing']), SpeechBand.correct);
      expect(band(word('kelinci'), ['namanya kelinci']), SpeechBand.correct);
    });

    test('child speech (cadel r→l, final h) is tolerated but not strict', () {
      final r = PronunciationEvaluator.evaluate(word('rumah'), ['lumah']);
      expect(r.band, SpeechBand.correct);
      expect(r.strictMatch, isFalse);
      expect(band(word('jerapah'), ['jelapa']), SpeechBand.correct);
    });

    test('best alternate (n-best) wins', () {
      expect(band(word('buku'), ['buka', 'buku']), SpeechBand.correct);
    });

    test('near miss is "almost", unrelated word is incorrect', () {
      expect(band(word('buku'), ['buka']), SpeechBand.almost);
      expect(band(word('gajah'), ['mobil']), SpeechBand.incorrect);
    });

    test('long word with one slip is accepted', () {
      expect(band(word('kepiting'), ['kepitin']), SpeechBand.correct);
    });

    test('silence is noSpeech', () {
      expect(band(word('bola'), []), SpeechBand.noSpeech);
      expect(band(word('bola'), ['  ']), SpeechBand.noSpeech);
    });

    test('phrases and reduplication', () {
      expect(band(word('apel merah'), ['Apel merah!']), SpeechBand.correct);
      expect(band(word('apel merah'), ['ini apel merah ya']), SpeechBand.correct);
      expect(band(word('kupu-kupu oranye'), ['kupu kupu oranye']), SpeechBand.correct);
      expect(band(word('apel merah'), ['apel']), isNot(SpeechBand.correct));
    });
  });

  group('letters (Indonesian letter names)', () {
    test('letter names and STT spellings are accepted', () {
      expect(band(letter('b'), ['be']), SpeechBand.correct);
      expect(band(letter('b'), ['B']), SpeechBand.correct);
      expect(band(letter('c'), ['ce']), SpeechBand.correct);
      expect(band(letter('f'), ['ef']), SpeechBand.correct);
      expect(band(letter('z'), ['zet']), SpeechBand.correct);
      expect(band(letter('a'), ['huruf a']), SpeechBand.correct);
    });

    test('different letter is not correct', () {
      expect(band(letter('b'), ['ka']), isNot(SpeechBand.correct));
    });
  });

  test('levenshtein and similarity helpers', () {
    expect(PronunciationEvaluator.levenshtein('kitten', 'sitting'), 3);
    expect(PronunciationEvaluator.similarity('buku', 'buka'), 0.75);
    expect(PronunciationEvaluator.fold('syal kharisma rumah'), 'sal kalisma luma');
  });
}
