import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/core/curriculum/curriculum.dart';
import 'package:kogo_voice_learning/core/curriculum/vocabulary.dart';

void main() {
  group('Vocabulary (batasan masalah)', () {
    test('every picture asset exists on disk', () {
      for (final materi in Materi.values) {
        for (final item in materi.items) {
          final asset = item.pictureAsset;
          if (asset == null) {
            expect(item.pictureEmoji, isNotNull, reason: '${item.text} has neither image nor emoji');
            continue;
          }
          expect(File(asset).existsSync(), isTrue, reason: 'missing $asset');
        }
      }
    });

    test('syllable counts match each material', () {
      for (final w in vocabDuaSuku) {
        expect(w.syllables.length, 2, reason: w.text);
        expect(w.syllables.join(), w.text, reason: w.text);
      }
      for (final w in vocabTigaSuku) {
        expect(w.syllables.length, 3, reason: w.text);
        expect(w.syllables.join(), w.text, reason: w.text);
      }
      for (final w in vocabBeberapaKata) {
        expect(w.text.split(' ').length, 2, reason: 'phrase must have two words: ${w.text}');
        expect(w.syllables.join(), w.text.replaceAll(' ', '').replaceAll('-', ''), reason: w.text);
      }
    });

    test('words are unique within a material', () {
      for (final materi in Materi.values) {
        final texts = materi.items.map((e) => e.text).toList();
        expect(texts.toSet().length, texts.length, reason: materi.title);
      }
    });

    test('letter examples start with their letter', () {
      for (final item in vocabHuruf) {
        expect(item.text.length, 1);
        expect(item.letter!.text.startsWith(item.text), isTrue, reason: item.letter!.text);
      }
    });

    test('vocabulary only uses concrete noun images (no verbs/adjectives folders)', () {
      for (final materi in Materi.values) {
        for (final item in materi.items) {
          final asset = item.pictureAsset;
          if (asset == null) continue;
          expect(asset.contains('/kata_benda/'), isTrue, reason: asset);
        }
      }
    });
  });

  group('Curriculum structure', () {
    test('units are balanced between 3 and 4 items', () {
      for (final materi in Materi.values) {
        final units = Curriculum.unitsOf(materi);
        final covered = units.expand((u) => u.items).length;
        expect(covered, materi.items.length);
        for (final u in units) {
          expect(u.items.length, inInclusiveRange(3, Curriculum.unitSize), reason: '${materi.title} unit ${u.index}');
        }
      }
    });

    test('every unit contains the four thesis games in order', () {
      for (final materi in Materi.values) {
        for (final unit in Curriculum.unitsOf(materi)) {
          expect(unit.games.take(4), [GameType.listenRepeat, GameType.findObject, GameType.missingLetter, GameType.matching]);
          expect(unit.games.length, 5);
        }
      }
    });

    test('letters never use fill-blank (it needs whole words)', () {
      for (final node in Curriculum.nodesOf(Materi.huruf)) {
        expect(node.game, isNot(GameType.fillBlank));
      }
    });

    test('node indexes are sequential and seeds unique', () {
      final seeds = <int>{};
      for (final materi in Materi.values) {
        final nodes = Curriculum.nodesOf(materi);
        for (var i = 0; i < nodes.length; i++) {
          expect(nodes[i].index, i);
          expect(seeds.add(nodes[i].seed), isTrue);
        }
      }
      expect(Curriculum.maxStars, Curriculum.totalNodes * 3);
    });

    test('codes round-trip', () {
      for (final m in Materi.values) {
        expect(Materi.fromCode(m.code), m);
      }
      for (final g in GameType.values) {
        expect(GameType.fromCode(g.code), g);
      }
    });
  });

  group('Stars and reward tiers', () {
    test('stars follow first-try accuracy', () {
      expect(Curriculum.starsFor(firstTryCorrect: 4, total: 4), 3);
      expect(Curriculum.starsFor(firstTryCorrect: 3, total: 4), 2);
      expect(Curriculum.starsFor(firstTryCorrect: 2, total: 4), 2);
      expect(Curriculum.starsFor(firstTryCorrect: 1, total: 4), 1);
      expect(Curriculum.starsFor(firstTryCorrect: 0, total: 4), 1);
      expect(Curriculum.starsFor(firstTryCorrect: 0, total: 0), 1);
    });

    test('tiers are ordered, reachable, and report progress', () {
      final thresholds = RewardTier.values.map((t) => t.minStars).toList();
      expect(thresholds, orderedEquals([...thresholds]..sort()));
      expect(RewardTier.berlian.minStars, lessThanOrEqualTo(Curriculum.maxStars));
      expect(RewardTier.perunggu.progressPercent(5), 50);
      expect(RewardTier.perunggu.isEarned(10), isTrue);
      expect(RewardTier.earnedCount(0), 0);
      expect(RewardTier.earnedCount(150), 3);
    });
  });
}
