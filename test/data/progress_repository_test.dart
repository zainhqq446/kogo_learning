import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/core/curriculum/curriculum.dart';
import 'package:kogo_voice_learning/data/learner_repository.dart';
import 'package:kogo_voice_learning/data/progress_repository.dart';

import '../helpers/test_database.dart';

void main() {
  late LearnerRepository learners;
  late ProgressRepository progress;

  setUp(() async {
    await useFreshTestDatabase();
    learners = LearnerRepository();
    progress = ProgressRepository();
  });

  group('Biodata (Users)', () {
    test('validation follows thesis rules (umur 5–6, data lengkap)', () {
      expect(BiodataValidation.name(''), isNotNull);
      expect(BiodataValidation.name('A'), isNotNull);
      expect(BiodataValidation.name('Sarah'), isNull);
      expect(BiodataValidation.name('<script>'), isNotNull);
      expect(BiodataValidation.school(' '), isNotNull);
      expect(BiodataValidation.school('TK Pertiwi'), isNull);
      expect(BiodataValidation.age(4), isNotNull);
      expect(BiodataValidation.age(7), isNotNull);
      expect(BiodataValidation.age(5), isNull);
      expect(BiodataValidation.age(6), isNull);
    });

    test('create, list, activate and update learners', () async {
      final a = await learners.create(name: '  Sarah   Putri ', school: 'TK Pertiwi', age: 6);
      final b = await learners.create(name: 'Budi', school: 'TK Melati', age: 5);
      expect(a.name, 'Sarah Putri');
      expect(a.firstName, 'Sarah');
      expect((await learners.all()).map((l) => l.name), ['Budi', 'Sarah Putri']);

      expect(await learners.active(), isNull);
      await learners.setActive(b.id);
      expect((await learners.active())!.id, b.id);

      final updated = await learners.update(b, name: 'Budi Santoso', school: 'TK Melati', age: 6);
      expect(updated.age, 6);
      expect((await learners.byId(b.id))!.name, 'Budi Santoso');

      await learners.clearActive();
      expect(await learners.active(), isNull);
    });

    test('invalid biodata is rejected', () async {
      expect(() => learners.create(name: 'Ani', school: 'TK', age: 8), throwsArgumentError);
      expect(() => learners.create(name: '', school: 'TK Melati', age: 5), throwsArgumentError);
    });
  });

  group('Game sessions, stars and rewards', () {
    test('stars keep the best score and unlock the next node', () async {
      final kid = await learners.create(name: 'Sarah', school: 'TK Pertiwi', age: 6);
      final nodes = Curriculum.nodesOf(Materi.duaSuku);

      expect(ProgressRepository.isUnlocked({}, 0), isTrue);
      expect(ProgressRepository.isUnlocked({}, 1), isFalse);

      final s1 = await progress.startSession(learnerId: kid.id, node: nodes[0]);
      final r1 = await progress.completeSession(sessionId: s1, learnerId: kid.id, node: nodes[0], totalItems: 4, firstTryCorrect: 2);
      expect(r1.stars, 2);
      expect(r1.isFirstCompletion, isTrue);

      final s2 = await progress.startSession(learnerId: kid.id, node: nodes[0]);
      final r2 = await progress.completeSession(sessionId: s2, learnerId: kid.id, node: nodes[0], totalItems: 4, firstTryCorrect: 1);
      expect(r2.stars, 1);
      expect(r2.improved, isFalse);

      final stars = await progress.starsFor(kid.id, Materi.duaSuku);
      expect(stars, {0: 2}, reason: 'best score is kept');
      expect(ProgressRepository.isUnlocked(stars, 1), isTrue);
      expect(ProgressRepository.isUnlocked(stars, 2), isFalse);
      expect(ProgressRepository.currentNodeIndex(stars, nodes.length), 1);

      final s3 = await progress.startSession(learnerId: kid.id, node: nodes[0]);
      final r3 = await progress.completeSession(sessionId: s3, learnerId: kid.id, node: nodes[0], totalItems: 4, firstTryCorrect: 4);
      expect(r3.improved, isTrue);
      expect((await progress.starsFor(kid.id, Materi.duaSuku))[0], 3);
    });

    test('reward tiers unlock once when total stars cross the threshold', () async {
      final kid = await learners.create(name: 'Sarah', school: 'TK Pertiwi', age: 6);
      final nodes = Curriculum.nodesOf(Materi.huruf);
      final newTiers = <RewardTier>[];
      for (var i = 0; i < 4; i++) {
        final s = await progress.startSession(learnerId: kid.id, node: nodes[i]);
        final r = await progress.completeSession(sessionId: s, learnerId: kid.id, node: nodes[i], totalItems: 4, firstTryCorrect: 4);
        newTiers.addAll(r.newTiers);
      }
      expect(newTiers, [RewardTier.perunggu], reason: '12 stars reach Perunggu (10) exactly once');

      final stats = await progress.stats(kid.id);
      expect(stats.totalStars, 12);
      expect(stats.completedNodes, 4);
      expect(stats.completedPerMateri[Materi.huruf], 4);
      expect(stats.unseenRewards, 1);
      expect(stats.earnedTiers, [RewardTier.perunggu]);

      await progress.markRewardsSeen(kid.id);
      expect((await progress.stats(kid.id)).unseenRewards, 0);
    });

    test('progress is isolated per learner', () async {
      final a = await learners.create(name: 'Sarah', school: 'TK Pertiwi', age: 6);
      final b = await learners.create(name: 'Budi', school: 'TK Melati', age: 5);
      final node = Curriculum.nodesOf(Materi.tigaSuku).first;
      final s = await progress.startSession(learnerId: a.id, node: node);
      await progress.completeSession(sessionId: s, learnerId: a.id, node: node, totalItems: 4, firstTryCorrect: 4);
      expect((await progress.stats(a.id)).totalStars, 3);
      expect((await progress.stats(b.id)).totalStars, 0);
      expect(await progress.starsFor(b.id, Materi.tigaSuku), isEmpty);
    });
  });

  group('Streak (Beruntun Belajar)', () {
    test('counts consecutive days ending today or yesterday', () {
      final now = DateTime(2026, 10, 25, 9);
      expect(ProgressRepository.streakFrom([], now), 0);
      expect(ProgressRepository.streakFrom(['2026-10-25'], now), 1);
      expect(ProgressRepository.streakFrom(['2026-10-25', '2026-10-24', '2026-10-23'], now), 3);
      expect(ProgressRepository.streakFrom(['2026-10-24', '2026-10-23'], now), 2, reason: 'yesterday keeps streak alive');
      expect(ProgressRepository.streakFrom(['2026-10-23'], now), 0, reason: 'gap of two days breaks streak');
      expect(ProgressRepository.streakFrom(['2026-10-25', '2026-10-23'], now), 1);
      expect(ProgressRepository.streakFrom(['2026-03-01', '2026-02-28'], DateTime(2026, 3, 1)), 2, reason: 'month boundary');
    });

    test('streak comes from completed sessions on different days', () async {
      final kid = await learners.create(name: 'Sarah', school: 'TK Pertiwi', age: 6);
      final nodes = Curriculum.nodesOf(Materi.huruf);
      final today = DateTime.now();
      for (var d = 0; d < 3; d++) {
        final day = today.subtract(Duration(days: d));
        final s = await progress.startSession(learnerId: kid.id, node: nodes[d], now: day);
        await progress.completeSession(sessionId: s, learnerId: kid.id, node: nodes[d], totalItems: 4, firstTryCorrect: 4, now: day);
      }
      expect((await progress.stats(kid.id)).streakDays, 3);
    });
  });

  group('Research metrics (Tabel 3.1)', () {
    test('STT accuracy, error rate, response time and task completion', () async {
      final kid = await learners.create(name: 'Sarah', school: 'TK Pertiwi', age: 6);
      final speak = Curriculum.nodesOf(Materi.duaSuku).first;
      expect(speak.game, GameType.listenRepeat);

      final s1 = await progress.startSession(learnerId: kid.id, node: speak);
      await progress.logAttempt(
        sessionId: s1,
        learnerId: kid.id,
        game: GameType.listenRepeat,
        target: 'bola',
        answer: 'bola',
        isCorrect: true,
        attemptNumber: 1,
        similarity: 1,
        responseMs: 800,
      );
      await progress.logAttempt(
        sessionId: s1,
        learnerId: kid.id,
        game: GameType.listenRepeat,
        target: 'buku',
        answer: 'buka',
        isCorrect: true,
        attemptNumber: 1,
        similarity: 0.75,
        responseMs: 1200,
      );
      await progress.logAttempt(
        sessionId: s1,
        learnerId: kid.id,
        game: GameType.listenRepeat,
        target: 'susu',
        answer: '',
        isCorrect: false,
        attemptNumber: 1,
        responseMs: 1000,
        sttError: 'no_match',
      );
      await progress.logAttempt(sessionId: s1, learnerId: kid.id, game: GameType.matching, target: 'kuda', answer: 'kuda', isCorrect: true, attemptNumber: 1);
      await progress.completeSession(sessionId: s1, learnerId: kid.id, node: speak, totalItems: 4, firstTryCorrect: 2);
      final s2 = await progress.startSession(learnerId: kid.id, node: speak);
      await progress.abandonSession(s2);

      final m = await progress.metrics(learnerId: kid.id);
      expect(m.sttAttempts, 3, reason: 'only voice attempts count');
      expect(m.sttAccuracy, closeTo(66.67, 0.01));
      expect(m.errorRate, closeTo(33.33, 0.01));
      expect(m.avgResponseMs, 1000);
      expect(m.taskCompletion, 50);

      final all = await progress.metrics();
      expect(all.sttAttempts, 3);
    });
  });
}
