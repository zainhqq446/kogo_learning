import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kogo_voice_learning/data/database/app_database.dart';
import 'package:kogo_voice_learning/features/stage/presentation/pages/stage_page.dart';
import 'package:kogo_voice_learning/services/audio/voice_interaction_controller.dart';
import '../mocks/mock_speech_output_provider.dart';

void main() {
  late MockSpeechOutputProvider mockAudio;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    mockAudio = MockSpeechOutputProvider();
    VoiceInteractionController.instance.setProviderForTesting(mockAudio);
    await AppDatabase.instance.deleteDatabase();
    await AppDatabase.instance.database;
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  Future<void> pumpAsync(WidgetTester tester) async {
    for (int i = 0; i < 2; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump();
    }
  }

  testWidgets('Navigation Flow: Stage -> Lesson -> Question -> Next Question -> Complete and Back', (
    WidgetTester tester,
  ) async {
    // 1. Render StagePage
    await tester.pumpWidget(
      const MaterialApp(
        home: StagePage(),
      ),
    );

    // Let the async SQLite query execute
    await pumpAsync(tester);

    // 2. Stage page loads stages from SQLite
    expect(find.text('Pilih Tahap'), findsOneWidget);
    expect(find.text('Huruf'), findsOneWidget);
    expect(find.text('Dua Suku Kata'), findsOneWidget);
    expect(find.text('Tiga Suku Kata'), findsOneWidget);
    expect(find.text('Banyak Suku Kata'), findsOneWidget);

    // 3. Tap Stage 1 ('Huruf') -> Navigates to LessonPage
    await tester.tap(find.text('Huruf'));
    await pumpAsync(tester);

    // Verify LessonPage is open with title 'Huruf' in AppBar and loaded lessons from SQLite
    expect(find.widgetWithText(AppBar, 'Huruf'), findsOneWidget);
    expect(find.text('Listen & Repeat'), findsOneWidget);
    expect(find.text('Find Object'), findsOneWidget);
    expect(find.text('Matching Object'), findsOneWidget);
    expect(find.text('Listen Carefully'), findsOneWidget);

    // 4. Tap 'Listen & Repeat' -> Navigates to QuestionPage
    await tester.tap(find.text('Listen & Repeat'));
    await pumpAsync(tester);

    // 5. Verify QuestionPage is open with question from SQLite
    expect(find.widgetWithText(AppBar, 'Listen & Repeat'), findsOneWidget);
    expect(find.text('Pertanyaan 1 dari 5'), findsOneWidget);
    expect(find.text('Ucapkan:'), findsOneWidget);
    expect(find.text('A'), findsOneWidget); // Target text from database
    expect(find.text('Ucapkan huruf A'), findsOneWidget); // Hint text from database
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // 6. Tap 'Pertanyaan Berikutnya' to progress through questions
    final nextBtn = find.text('Pertanyaan Berikutnya');
    await tester.ensureVisible(nextBtn);
    await tester.tap(nextBtn);
    await pumpAsync(tester);

    // Verify Question 2
    expect(find.text('Pertanyaan 2 dari 5'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('Ucapkan huruf B'), findsOneWidget);

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

    // Progress to Question 5 (last question)
    await tester.ensureVisible(nextBtn);
    await tester.tap(nextBtn);
    await pumpAsync(tester);
    expect(find.text('Pertanyaan 5 dari 5'), findsOneWidget);
    expect(find.text('E'), findsOneWidget);

    final selesaiBtn = find.text('Selesai');
    expect(selesaiBtn, findsOneWidget);

    // 7. Tap 'Selesai' -> Dialog appears -> Dialog closes and navigates back
    await tester.ensureVisible(selesaiBtn);
    await tester.tap(selesaiBtn);
    await pumpAsync(tester);

    expect(find.text('Hebat! 🎉'), findsOneWidget);
    expect(find.text('Kamu sudah menyelesaikan semua pertanyaan.'), findsOneWidget);

    // Tap dialog 'Selesai' button
    await tester.tap(find.widgetWithText(TextButton, 'Selesai'));
    await pumpAsync(tester);

    // Verify we navigated safely back to LessonPage
    expect(find.text('Listen & Repeat'), findsOneWidget);
    expect(find.text('Find Object'), findsOneWidget);

    // 8. Test back button from LessonPage back to StagePage
    await tester.tap(find.byType(BackButton));
    await pumpAsync(tester);

    // Verify safely back at StagePage
    expect(find.text('Pilih Tahap'), findsOneWidget);
    expect(find.text('Huruf'), findsOneWidget);
  });
}
