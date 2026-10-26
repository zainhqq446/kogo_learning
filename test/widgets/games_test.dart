import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/app/app_session.dart';
import 'package:kogo_voice_learning/core/curriculum/curriculum.dart';
import 'package:kogo_voice_learning/data/db/kogo_database.dart';
import 'package:kogo_voice_learning/features/games/game_content.dart';
import 'package:kogo_voice_learning/features/games/game_page.dart';
import 'package:kogo_voice_learning/features/games/reward_dialog.dart';
import 'package:kogo_voice_learning/services/speech/speech_listener.dart';

import '../helpers/fakes.dart';
import '../helpers/pump.dart';
import '../helpers/test_env.dart';

LearningNode nodeOf(Materi materi, GameType game, {int unit = 0}) => Curriculum.nodesOf(materi).firstWhere((n) => n.game == game && n.unit.index == unit);

void main() {
  late FakeSpeechListener listener;

  setUp(() async {
    listener = (await resetTestEnv()).listener;
  });

  Future<void> openGame(WidgetTester tester, LearningNode node) async {
    usePhoneSize(tester);
    await tester.runAsync(() async {
      final kid = await AppSession.instance.learners.create(name: 'Sarah', school: 'TK Pertiwi', age: 6);
      await AppSession.instance.activate(kid);
    });
    await tester.pumpWidget(testApp(GamePage(node: node)));
    await settle(tester, total: const Duration(seconds: 3));
  }

  Future<List<Map<String, Object?>>> rows(WidgetTester tester, String sql) async =>
      (await tester.runAsync(() async => (await KogoDatabase.instance.database).rawQuery(sql)))!;

  Future<void> tapMic(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Tekan untuk berbicara'));
    await settle(tester, total: const Duration(seconds: 2));
  }

  /// Dialog hadiah tampil; lalu waktu dimajukan agar timer sinkronisasi latar selesai.
  Future<void> expectReward(WidgetTester tester, {int? stars}) async {
    expect(find.byType(RewardDialog), findsOneWidget);
    if (stars != null) expect(find.text('+$stars bintang'), findsOneWidget);
    await settle(tester, total: const Duration(seconds: 4));
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.text('Lanjutkan'));
    await settle(tester, total: const Duration(seconds: 3));
  }

  group('Dengar & Ulangi (voice recognition)', () {
    testWidgets('three wrong tries reveal the word; stars reflect first-try accuracy', (tester) async {
      final node = nodeOf(Materi.duaSuku, GameType.listenRepeat);
      final words = node.unit.items;
      listener
        ..say('mobil')
        ..say('gajah')
        ..say('ular');
      for (final w in words.skip(1)) {
        listener.say(w.text);
      }
      await openGame(tester, node);

      await tapMic(tester);
      expect(find.text('Belum tepat. Coba lagi, ya!'), findsOneWidget);
      expect(find.textContaining('Kogo mendengar'), findsOneWidget);
      await tapMic(tester);
      await tapMic(tester);
      expect(find.text('Tidak apa-apa! Ayo lanjut 🌟'), findsOneWidget);
      await next(tester);

      for (var i = 1; i < words.length; i++) {
        await tapMic(tester);
        expect(find.text('Bagus sekali! 🎉'), findsOneWidget);
        await next(tester);
      }
      await expectReward(tester, stars: 2); // 3 dari 4 benar pada percobaan pertama

      final logged = await rows(tester, 'SELECT target_text, is_correct, attempt_number FROM answer_attempts ORDER BY id');
      expect(logged.length, 3 + words.length - 1);
      expect(logged.take(3).map((r) => r['attempt_number']), [1, 2, 3]);
    });

    testWidgets('silence does not cost a try and is logged as STT error', (tester) async {
      final node = nodeOf(Materi.duaSuku, GameType.listenRepeat);
      listener.outcomes.add(const ListenOutcome(alternates: [], error: ListenError.noSpeech, responseMs: 900));
      listener.say(node.unit.items.first.text);
      await openGame(tester, node);

      await tapMic(tester);
      expect(find.text('Suaramu belum terdengar. Coba lagi, ya!'), findsOneWidget);
      await tapMic(tester);
      expect(find.text('Bagus sekali! 🎉'), findsOneWidget);

      final logged = await rows(tester, 'SELECT is_correct, stt_error FROM answer_attempts ORDER BY id');
      expect(logged, [
        {'is_correct': 0, 'stt_error': 'noSpeech'},
        {'is_correct': 1, 'stt_error': null},
      ]);
      final learner = AppSession.instance.learner!;
      final metrics = (await tester.runAsync(() => AppSession.instance.progress.metrics(learnerId: learner.id)))!;
      expect(metrics.sttAttempts, 2);
      expect(metrics.sessionsWithErrors, 1);
      expect(metrics.errorRate, 100); // 1 dari 1 sesi mengalami galat suara (Tabel 3.1)
    });

    testWidgets('near miss shows "almost" feedback', (tester) async {
      final node = nodeOf(Materi.duaSuku, GameType.listenRepeat);
      expect(node.unit.items[1].text, 'buku');
      listener
        ..say('bola')
        ..say('buka');
      await openGame(tester, node);
      await tapMic(tester);
      await next(tester);
      await tapMic(tester);
      expect(find.text('Hampir benar! Coba lagi 💪'), findsOneWidget);
    });

    testWidgets('microphone permission denied shows parent help and skip', (tester) async {
      listener.prepareError = ListenError.permissionDenied;
      await openGame(tester, nodeOf(Materi.duaSuku, GameType.listenRepeat));
      await tapMic(tester);
      expect(find.text('Kogo butuh izin mikrofon 🎤'), findsOneWidget);
      expect(find.text('Buka Pengaturan'), findsOneWidget);
      await tester.tap(find.text('Lewati'));
      await settle(tester, total: const Duration(seconds: 2));
      expect(find.text('BUKU'), findsOneWidget, reason: 'moved to the next word');
    });

    testWidgets('letter material accepts Indonesian letter names', (tester) async {
      final node = nodeOf(Materi.huruf, GameType.listenRepeat);
      listener.say('be');
      await openGame(tester, node);
      expect(find.text('A'), findsOneWidget);
      listener.outcomes.insert(0, const ListenOutcome(alternates: ['a'], responseMs: 500));
      await tapMic(tester);
      expect(find.text('Bagus sekali! 🎉'), findsOneWidget);
      await next(tester);
      await tapMic(tester);
      expect(find.text('Bagus sekali! 🎉'), findsOneWidget, reason: '"be" is the letter B');
    });
  });

  testWidgets('Cari Objek: wrong choice is disabled, correct advances to reward', (tester) async {
    final node = nodeOf(Materi.duaSuku, GameType.findObject);
    final rounds = GameContent.findObject(node);
    await openGame(tester, node);
    String label(String s) => s[0].toUpperCase() + s.substring(1);

    for (var i = 0; i < rounds.length; i++) {
      final round = rounds[i];
      expect(find.text(round.letter), findsWidgets);
      if (i == 0) {
        final wrong = round.options.firstWhere((o) => o.text != round.target.text);
        await tester.tap(find.text(label(wrong.text)));
        await settle(tester, total: const Duration(seconds: 2));
        expect(find.text('Coba Lagi!'), findsOneWidget);
      }
      await tester.tap(find.text(label(round.target.text)));
      await settle(tester, total: const Duration(seconds: 3));
    }
    await expectReward(tester, stars: 2);
  });

  testWidgets('Huruf Hilang: wrong letter is cleared, correct letter completes word', (tester) async {
    final node = nodeOf(Materi.duaSuku, GameType.missingLetter);
    final rounds = GameContent.missingLetter(node);
    await openGame(tester, node);
    for (var i = 0; i < rounds.length; i++) {
      final round = rounds[i];
      if (i == 0) {
        final wrong = round.options.firstWhere((o) => o != round.answer);
        await tester.tap(find.bySemanticsLabel('Huruf $wrong'));
        await settle(tester, total: const Duration(milliseconds: 500));
        expect(find.text('Coba Lagi!'), findsOneWidget);
        await settle(tester, total: const Duration(seconds: 1));
        expect(find.text('Coba Lagi!'), findsNothing, reason: 'wrong letter is cleared');
      }
      await tester.tap(find.bySemanticsLabel('Huruf ${round.answer}'));
      await settle(tester, total: const Duration(seconds: 3));
    }
    await expectReward(tester);
  });

  testWidgets('Cocokkan: mismatch is rejected, all pairs matched completes', (tester) async {
    final node = nodeOf(Materi.duaSuku, GameType.matching);
    final items = node.unit.items;
    await openGame(tester, node);
    expect(find.text('Cocok: 0 / ${items.length}'), findsOneWidget);

    Finder picture(String text) => find.bySemanticsLabel(text).last;
    await tester.tap(find.text(items[0].display));
    await tester.pump();
    await tester.tap(picture(items[1].text));
    await settle(tester, total: const Duration(seconds: 2));
    expect(find.text('Cocok: 0 / ${items.length}'), findsOneWidget);

    for (var i = 0; i < items.length; i++) {
      await tester.tap(find.text(items[i].display));
      await tester.pump();
      await tester.tap(picture(items[i].text));
      await settle(tester, total: const Duration(seconds: 2));
    }
    await settle(tester, total: const Duration(seconds: 3));
    await expectReward(tester);
  });

  testWidgets('Dengar & Pilih: choose the heard word', (tester) async {
    final node = nodeOf(Materi.duaSuku, GameType.listening);
    final rounds = GameContent.listening(node);
    await openGame(tester, node);
    for (final round in rounds) {
      await tester.tap(find.text(round.target.display));
      await settle(tester, total: const Duration(seconds: 3));
    }
    await expectReward(tester, stars: 3);
  });

  testWidgets('Isi Huruf Kosong: wrong letters cleared, right word completes', (tester) async {
    final node = nodeOf(Materi.duaSuku, GameType.fillBlank, unit: 1);
    final rounds = GameContent.fillBlank(node);
    await openGame(tester, node);
    for (var i = 0; i < rounds.length; i++) {
      final round = rounds[i];
      if (i == 0) {
        for (final _ in round.blanks) {
          final wrong = round.keyboard.firstWhere((k) => !round.blanks.any((b) => round.word[b] == k));
          await tester.tap(find.bySemanticsLabel('Huruf $wrong'));
          await tester.pump();
        }
        await tester.tap(find.text('Periksa'));
        await settle(tester, total: const Duration(seconds: 3));
        expect(find.text('Periksa'), findsOneWidget, reason: 'still playing after wrong check');
      }
      for (final b in round.blanks) {
        await tester.tap(find.bySemanticsLabel('Huruf ${round.word[b]}'));
        await tester.pump();
      }
      await tester.tap(find.text('Periksa'));
      await settle(tester, total: const Duration(seconds: 4));
    }
    await expectReward(tester);
  });

  testWidgets('leaving a game asks for confirmation and marks session abandoned', (tester) async {
    await openGame(tester, nodeOf(Materi.duaSuku, GameType.findObject));
    await tester.tap(find.text('Kembali'));
    await settle(tester, total: const Duration(seconds: 1));
    expect(find.text('Berhenti bermain?'), findsOneWidget);
    await tester.tap(find.text('Lanjut main'));
    await settle(tester, total: const Duration(seconds: 1));
    expect(find.text('Cari objek yang dimulai dengan:'), findsOneWidget);

    await tester.tap(find.text('Kembali'));
    await settle(tester, total: const Duration(seconds: 1));
    await tester.tap(find.text('Ya, keluar'));
    await settle(tester, total: const Duration(seconds: 1));
    final sessions = await rows(tester, 'SELECT status FROM game_sessions');
    expect(sessions, [
      {'status': 'abandoned'},
    ]);
  });

  testWidgets('reward "Lanjut" opens the next game in the path', (tester) async {
    final nodes = Curriculum.nodesOf(Materi.duaSuku);
    final node = nodes[3];
    expect(node.game, GameType.matching);
    await openGame(tester, nodes[4]);
    final rounds = GameContent.listening(nodes[4]);
    for (final round in rounds) {
      await tester.tap(find.text(round.target.display));
      await settle(tester, total: const Duration(seconds: 3));
    }
    await tester.tap(find.text('Lanjut'));
    await settle(tester, total: const Duration(seconds: 3));
    expect(find.text(nodes[5].game.title), findsWidgets);
    expect(find.byType(GamePage), findsOneWidget);
  });
}
