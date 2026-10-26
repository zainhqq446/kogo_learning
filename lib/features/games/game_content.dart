import 'dart:math' as math;

import '../../core/curriculum/curriculum.dart';
import '../../core/curriculum/vocabulary.dart';

class FindObjectRound {
  const FindObjectRound({required this.target, required this.letter, required this.options});

  final VocabItem target;
  final String letter;

  /// Empat pilihan bergambar (satu benar).
  final List<VocabItem> options;
}

class MissingLetterRound {
  const MissingLetterRound({required this.item, required this.word, required this.blankIndex, required this.options});

  final VocabItem item;

  /// Kata yang ditampilkan (huruf besar), contoh `APEL`.
  final String word;
  final int blankIndex;
  final List<String> options;

  String get answer => word[blankIndex];
}

class FillBlankRound {
  const FillBlankRound({required this.item, required this.word, required this.blanks, required this.keyboard});

  final VocabItem item;
  final String word;
  final List<int> blanks;
  final List<String> keyboard;
}

class ChoiceRound {
  const ChoiceRound({required this.target, required this.options});

  final VocabItem target;
  final List<VocabItem> options;
}

/// Menyusun soal setiap permainan dari unit kosakata secara deterministik
/// (seed per node) sehingga susunan soal stabil dan dapat diuji.
class GameContent {
  GameContent._();

  static const _vowels = ['A', 'I', 'U', 'E', 'O'];
  static const _consonants = ['B', 'D', 'G', 'K', 'L', 'M', 'N', 'P', 'R', 'S', 'T'];

  static List<VocabItem> listenRepeat(LearningNode node) => node.unit.items;

  static List<FindObjectRound> findObject(LearningNode node) {
    final random = math.Random(node.seed);
    final pool = node.materi == Materi.huruf ? vocabHuruf : node.materi.items;
    return [
      for (final item in node.unit.items)
        () {
          final letter = item.firstLetter;
          final distractors = pool.where((o) => o.firstLetter != letter && o.text != item.text).toList()..shuffle(random);
          final unique = <VocabItem>[];
          for (final d in distractors) {
            if (unique.every((u) => u.firstLetter != d.firstLetter && u.pictureAsset != d.pictureAsset)) unique.add(d);
            if (unique.length == 3) break;
          }
          final options = [item, ...unique]..shuffle(random);
          return FindObjectRound(target: item, letter: letter, options: options);
        }(),
    ];
  }

  static List<MissingLetterRound> missingLetter(LearningNode node) {
    final random = math.Random(node.seed);
    return [
      for (final item in node.unit.items)
        () {
          final word = _displayWord(item);
          final blank = item.isLetter ? 0 : _blankIndex(word, random);
          final answer = word[blank];
          final source = _vowels.contains(answer) ? _vowels : _consonants;
          final others = source.where((c) => c != answer).toList()..shuffle(random);
          final options = [answer, ...others.take(3)]..shuffle(random);
          return MissingLetterRound(item: item, word: word, blankIndex: blank, options: options);
        }(),
    ];
  }

  static List<FillBlankRound> fillBlank(LearningNode node) {
    final random = math.Random(node.seed);
    return [
      for (final item in node.unit.items)
        () {
          final word = _displayWord(item);
          final vowelPositions = [
            for (var i = 0; i < word.length; i++)
              if (_vowels.contains(word[i])) i,
          ];
          final maxBlanks = word.length <= 4 ? 2 : 3;
          final blanks = (vowelPositions.length <= maxBlanks ? vowelPositions : ([...vowelPositions]..shuffle(random)).take(maxBlanks).toList())..sort();
          final needed = blanks.map((i) => word[i]).toSet();
          final extra = _consonants.where((c) => !needed.contains(c)).toList()..shuffle(random);
          final keyboard = [..._vowels, ...extra.take(4)]..shuffle(random);
          return FillBlankRound(item: item, word: word, blanks: blanks, keyboard: keyboard);
        }(),
    ];
  }

  static List<ChoiceRound> listening(LearningNode node) {
    final random = math.Random(node.seed);
    final items = node.unit.items;
    final pool = node.materi.items;
    return [
      for (final item in items)
        () {
          final others = items.where((o) => o.text != item.text).toList();
          if (others.length < 3) {
            final more = pool.where((o) => !items.contains(o)).toList()..shuffle(random);
            others.addAll(more.take(3 - others.length));
          }
          others.shuffle(random);
          final options = [item, ...others.take(3)]..shuffle(random);
          return ChoiceRound(target: item, options: options);
        }(),
    ];
  }

  /// Papan Cocokkan: kolom kata dan kolom gambar diacak terpisah.
  static ({List<VocabItem> words, List<VocabItem> pictures}) matching(LearningNode node) {
    final random = math.Random(node.seed);
    final words = [...node.unit.items]..shuffle(random);
    var pictures = [...node.unit.items]..shuffle(random);
    // Hindari susunan identik agar anak benar-benar mencocokkan.
    var guard = 0;
    while (words.length > 1 && _sameOrder(words, pictures) && guard++ < 5) {
      pictures = [...pictures]..shuffle(random);
    }
    return (words: words, pictures: pictures);
  }

  static bool _sameOrder(List<VocabItem> a, List<VocabItem> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i].text != b[i].text) return false;
    }
    return true;
  }

  /// Untuk huruf: kata contohnya (APEL); untuk kata/frasa: teksnya sendiri.
  static String _displayWord(VocabItem item) => (item.letter?.text ?? item.text).toUpperCase();

  /// Huruf yang dikosongkan: vokal pada kata pertama selain huruf awal
  /// (contoh Figma: AP_L), sehingga huruf awal tetap menjadi petunjuk.
  static int _blankIndex(String word, math.Random random) {
    final firstWordEnd = word.indexOf(RegExp('[ -]'));
    final limit = firstWordEnd < 0 ? word.length : firstWordEnd;
    final candidates = [
      for (var i = 1; i < limit; i++)
        if (_vowels.contains(word[i])) i,
    ];
    if (candidates.isEmpty) return limit > 1 ? 1 : 0;
    return candidates[random.nextInt(candidates.length)];
  }
}
