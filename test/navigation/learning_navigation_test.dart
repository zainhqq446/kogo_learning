import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kogo_voice_learning/data/database/app_database.dart';
import 'package:kogo_voice_learning/features/stage/presentation/pages/stage_page.dart';
import 'package:kogo_voice_learning/services/audio/voice_interaction_controller.dart';
import 'package:kogo_voice_learning/services/auth/session_manager.dart';
import 'package:kogo_voice_learning/services/audio/bgm_manager.dart';
import 'package:flutter/services.dart';
import '../mocks/mock_speech_output_provider.dart';

void main() {
  late MockSpeechOutputProvider mockAudio;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (MethodCall methodCall) async => 1,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (MethodCall methodCall) async => 1,
    );

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    BgmManager.instance.setDisabledForTesting(true);
    mockAudio = MockSpeechOutputProvider();
    VoiceInteractionController.instance.setProviderForTesting(mockAudio);
    await AppDatabase.instance.deleteDatabase();
    await AppDatabase.instance.database;

    final sessionManager = SessionManager.instance;
    await sessionManager.initDevice(deviceId: 'dev_test_nav');
    await sessionManager.loginChild(childCode: 'P001', pin: '1234');
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  Future<void> pumpAsync(WidgetTester tester) async {
    for (int i = 0; i < 5; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump();
    }
  }

  testWidgets('Navigation Flow: Stage -> Lesson -> Question -> Next Question -> Complete and Back', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    // 1. Render StagePage
    await tester.pumpWidget(
      const MaterialApp(
        home: StagePage(),
      ),
    );

    // Let the async SQLite query execute
    await pumpAsync(tester);
    await pumpAsync(tester);
    await pumpAsync(tester);

    // 2. Stage page loads stages from SQLite
    expect(find.text('Pilih Tahap'), findsOneWidget);
    expect(find.text('Huruf'), findsOneWidget);
    expect(find.text('Dua Suku Kata'), findsOneWidget);
    expect(find.text('Tiga Suku Kata'), findsOneWidget);
    expect(find.text('Banyak Suku Kata'), findsOneWidget);

    // 3. Tap Stage 1 ('Huruf') -> Navigates to LessonPage (Checkpoint Adventure Map)
    await tester.tap(find.text('Huruf'));
    await pumpAsync(tester);

    // Verify LessonPage is open with title 'Huruf' in AppBar and loaded Checkpoints
    expect(find.widgetWithText(AppBar, 'Huruf'), findsOneWidget);
    expect(find.text('Checkpoint 1'), findsOneWidget);
    expect(find.text('Mulai Di Sini! 👆'), findsOneWidget);

    // 4. Tap 'Checkpoint 1' -> Navigates to CheckpointSessionPage (Step 1: Listen & Repeat)
    await tester.tap(find.text('Checkpoint 1'));
    await pumpAsync(tester);

    // 5. Verify QuestionPage is open with Stage 1 questions (A to E)
    expect(find.text('Pertanyaan 1 dari 5'), findsOneWidget);
    expect(find.text('Ucapkan:'), findsOneWidget);
    expect(find.text('A'), findsOneWidget); // Target letter from database
    expect(find.byType(LinearProgressIndicator), findsWidgets);

    // 6. Tap 'Pertanyaan Berikutnya' to progress through questions
    final nextBtn = find.text('Pertanyaan Berikutnya');
    await tester.ensureVisible(nextBtn);
    await tester.tap(nextBtn);
    await pumpAsync(tester);

    // Verify Question 2
    expect(find.text('Pertanyaan 2 dari 5'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);

    // Progress to Question 3
    await tester.ensureVisible(nextBtn);
    await tester.tap(nextBtn);
    await pumpAsync(tester);
    expect(find.text('Pertanyaan 3 dari 5'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);

    // Progress to Question 4
    await tester.ensureVisible(nextBtn);
    await tester.tap(nextBtn);
    await pumpAsync(tester);
    expect(find.text('Pertanyaan 4 dari 5'), findsOneWidget);
    expect(find.text('D'), findsOneWidget);

    // Progress to Question 5 (last question in Listen & Repeat)
    await tester.ensureVisible(nextBtn);
    await tester.tap(nextBtn);
    await pumpAsync(tester);
    expect(find.text('Pertanyaan 5 dari 5'), findsOneWidget);
    expect(find.text('E'), findsOneWidget);

    final selesaiBtn = find.text('Selesai');
    expect(selesaiBtn, findsOneWidget);

    // 7. Tap 'Selesai' -> Icebreaking dialog appears -> skip icebreaking
    await tester.ensureVisible(selesaiBtn);
    await tester.tap(selesaiBtn);
    await pumpAsync(tester);

    final icebreakingBtn = find.text('Lewati / Lanjut ⏩');
    if (icebreakingBtn.evaluate().isNotEmpty) {
      await tester.tap(icebreakingBtn);
      await pumpAsync(tester);
    }

    // Step 1 completed, CheckpointSession shows transition dialog to Game Step 2
    expect(find.text('Lanjut ke Game Berikutnya!'), findsOneWidget);
    final mulaiBtn = find.text('Mulai! 🚀');
    expect(mulaiBtn, findsOneWidget);
    await tester.tap(mulaiBtn);
    await pumpAsync(tester);

    // Back out from CheckpointSession to LessonPage
    final sessionBackBtn = find.byType(BackButton);
    if (sessionBackBtn.evaluate().isNotEmpty) {
      await tester.tap(sessionBackBtn.first, warnIfMissed: false);
      await pumpAsync(tester);
    }

    // Verify safely back at LessonPage
    expect(find.text('Checkpoint 1'), findsOneWidget);

    // 8. Test back button from LessonPage back to StagePage
    await tester.tap(find.byType(BackButton), warnIfMissed: false);
    await pumpAsync(tester);
    await pumpAsync(tester);

    // Verify safely back at StagePage
    expect(find.text('Pilih Tahap'), findsOneWidget);
    expect(find.text('Huruf'), findsOneWidget);
  });

  testWidgets('Stage Locking: Stage 2 is locked when Stage 1 is not completed, showing dialog on tap', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: StagePage(),
      ),
    );
    await pumpAsync(tester);
    await pumpAsync(tester);
    await pumpAsync(tester);

    expect(find.text('Huruf'), findsOneWidget);
    expect(find.text('Dua Suku Kata'), findsOneWidget);

    // Tap Stage 2 ('Dua Suku Kata') yang masih terkunci
    await tester.tap(find.text('Dua Suku Kata'));
    await pumpAsync(tester);

    // Verify Dialog Tahap Terkunci muncul
    expect(find.text('Tahap Terkunci 🔒'), findsOneWidget);
    expect(find.text('Siap, Mengerti! 🚀'), findsOneWidget);

    // Dismiss dialog
    await tester.tap(find.text('Siap, Mengerti! 🚀'));
    await pumpAsync(tester);
    expect(find.text('Tahap Terkunci 🔒'), findsNothing);
  });
}
