import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/data/models/lesson_model.dart';
import 'package:kogo_voice_learning/data/models/question_model.dart';
import 'package:kogo_voice_learning/features/activity/presentation/pages/word_assembly_page.dart';
import 'package:kogo_voice_learning/services/audio/bgm_manager.dart';
import 'package:kogo_voice_learning/services/audio/voice_interaction_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../mocks/mock_speech_output_provider.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    BgmManager.instance.setDisabledForTesting(true);
    VoiceInteractionController.instance.setProviderForTesting(MockSpeechOutputProvider());
  });

  testWidgets('WordAssemblyPage: menyusun huruf kata dan kata berulang dengan tanda hubung', (
    WidgetTester tester,
  ) async {
    const lesson = LessonModel(
      id: 1,
      stageId: 2,
      title: 'Susun Kata Test',
      lessonType: 'word_assembly',
      orderIndex: 1,
      isActive: true,
    );

    final questions = [
      const QuestionModel(
        id: 101,
        lessonId: 1,
        targetText: 'buku',
        normalizedTarget: 'buku',
        orderIndex: 1,
        isActive: true,
      ),
      const QuestionModel(
        id: 102,
        lessonId: 1,
        targetText: 'lumba-lumba',
        normalizedTarget: 'lumba-lumba',
        orderIndex: 2,
        isActive: true,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: WordAssemblyPage(
          lesson: lesson,
          questionsOverride: questions,
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Pastikan halaman terbuka
    expect(find.text('Susun Kata 🔤'), findsOneWidget);
    expect(find.text('Kata 1 dari 2'), findsOneWidget);
    expect(find.text('Pilih Huruf:'), findsOneWidget);

    // Dapatkan semua tombol huruf yang tersedia untuk 'buku' (b, u, k, u)
    // Susun secara berurutan: b, u, k, u
    // Klik huruf 'B'
    await tester.tap(find.widgetWithText(ElevatedButton, 'B').first);
    await tester.pumpAndSettle();

    // Klik huruf 'U'
    await tester.tap(find.widgetWithText(ElevatedButton, 'U').first);
    await tester.pumpAndSettle();

    // Klik huruf 'K'
    await tester.tap(find.widgetWithText(ElevatedButton, 'K').first);
    await tester.pumpAndSettle();

    // Klik huruf 'U' sisa
    await tester.tap(find.widgetWithText(ElevatedButton, 'U').first);
    await tester.pumpAndSettle();

    // Verifikasi feedback jawaban benar
    expect(find.text('Hebat! Kata "buku" tersusun dengan tepat!'), findsOneWidget);

    // Tekan tombol Lanjut
    final lanjutBtn = find.text('Lanjut ⏩');
    expect(lanjutBtn, findsOneWidget);
    await tester.tap(lanjutBtn);
    await tester.pumpAndSettle();

    // Verifikasi kata kedua: 'lumba-lumba'
    expect(find.text('Kata 2 dari 2'), findsOneWidget);
    // Tanda hubung '-' harus ada dalam kepingan huruf
    expect(find.widgetWithText(ElevatedButton, '-'), findsOneWidget);
  });
}
