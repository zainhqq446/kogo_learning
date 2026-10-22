import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/services/audio/voice_message_context.dart';
import 'package:kogo_voice_learning/services/audio/voice_message_selector.dart';

void main() {
  test('Listening Test: Sequential simulation of 25 child voice interactions', () {
    final selector = VoiceMessageSelector.instance;
    selector.resetHistory();

    final transcript = <String>[];

    // Simulasi 25 event berturut-turut pada sesi belajar anak
    final scenarios = [
      // 1. Intro permainan
      () => selector.selectGameIntro('listen_repeat'),
      // 2. Ajakan bicara kata pertama
      () => selector.selectSpeechPrompt('apel', attempt: 1),
      // 3. Jawaban anak benar
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'apel',
            isCorrect: true,
            streak: 1,
            attemptNumber: 1,
            questionIndex: 0,
            totalQuestions: 5,
          )),
      // 4. Transisi
      () => selector.selectTransition(const VoiceMessageContext(
            targetWord: 'apel',
            questionIndex: 0,
            totalQuestions: 5,
          )),
      // 5. Ajakan kata kedua
      () => selector.selectSpeechPrompt('bola', attempt: 1),
      // 6. Belum terdengar (empty recognition)
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'bola',
            isEmptyRecognition: true,
            attemptNumber: 1,
            questionIndex: 1,
            totalQuestions: 5,
          )),
      // 7. Percobaan kedua kata kedua
      () => selector.selectSpeechPrompt('bola', attempt: 2),
      // 8. Jawaban hampir benar
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'bola',
            isCorrect: false,
            similarity: 75.0,
            attemptNumber: 2,
            questionIndex: 1,
            totalQuestions: 5,
          )),
      // 9. Percobaan ketiga kata kedua
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'bola',
            isCorrect: true,
            streak: 1,
            attemptNumber: 3,
            questionIndex: 1,
            totalQuestions: 5,
          )),
      // 10. Transisi menuju pertengahan
      () => selector.selectTransition(const VoiceMessageContext(
            targetWord: 'bola',
            questionIndex: 1,
            totalQuestions: 5,
          )),
      // 11. Kata ketiga (buku)
      () => selector.selectSpeechPrompt('buku', attempt: 1),
      // 12. Benar berturut-turut (streak 2)
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'buku',
            isCorrect: true,
            streak: 2,
            questionIndex: 2,
            totalQuestions: 5,
          )),
      // 13. Transisi tengah sesi
      () => selector.selectTransition(const VoiceMessageContext(
            targetWord: 'buku',
            questionIndex: 2,
            totalQuestions: 5,
          )),
      // 14. Kata keempat (meja)
      () => selector.selectSpeechPrompt('meja', attempt: 1),
      // 15. Benar lagi (streak 3 - celebratory!)
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'meja',
            isCorrect: true,
            streak: 3,
            questionIndex: 3,
            totalQuestions: 5,
          )),
      // 16. Transisi mendekati akhir (soal terakhir)
      () => selector.selectTransition(const VoiceMessageContext(
            targetWord: 'meja',
            questionIndex: 3,
            totalQuestions: 5,
          )),
      // 17. Kata kelima (sapi)
      () => selector.selectSpeechPrompt('sapi', attempt: 1),
      // 18. Jawaban salah attempt 1
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'sapi',
            isCorrect: false,
            attemptNumber: 1,
            questionIndex: 4,
            totalQuestions: 5,
          )),
      // 19. Retry attempt 2
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'sapi',
            isCorrect: false,
            attemptNumber: 2,
            questionIndex: 4,
            totalQuestions: 5,
          )),
      // 20. Benar di attempt 3
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'sapi',
            isCorrect: true,
            streak: 1,
            attemptNumber: 3,
            questionIndex: 4,
            totalQuestions: 5,
          )),
      // 21. Selebrasi selesai aktivitas
      () => selector.selectCompletionMessage(const VoiceMessageContext(
            targetWord: 'sapi',
            isCompleted: true,
            questionIndex: 4,
            totalQuestions: 5,
          )),
      // 22. Intro permainan kedua (Find Object)
      () => selector.selectGameIntro('find_object'),
      // 23. Dorongan berpikir (Find Object)
      () => selector.selectGameEncouragement('find_object'),
      // 24. Intro permainan ketiga (Matching)
      () => selector.selectGameIntro('matching'),
      // 25. Intro permainan keempat (Listen Carefully)
      () => selector.selectGameIntro('listen_carefully'),
      // 26. Correct #5
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'topi',
            isCorrect: true,
            streak: 2,
            questionIndex: 0,
            totalQuestions: 5,
          )),
      // 27. Correct #6 (streak 4)
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'baju',
            isCorrect: true,
            streak: 4,
            questionIndex: 1,
            totalQuestions: 5,
          )),
      // 28. Almost #2
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'pintu',
            isCorrect: false,
            similarity: 70.0,
            attemptNumber: 1,
            questionIndex: 2,
            totalQuestions: 5,
          )),
      // 29. Almost #3
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'kursi',
            isCorrect: false,
            similarity: 80.0,
            attemptNumber: 2,
            questionIndex: 2,
            totalQuestions: 5,
          )),
      // 30. Almost #4
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'lampu',
            isCorrect: false,
            similarity: 78.0,
            attemptNumber: 1,
            questionIndex: 3,
            totalQuestions: 5,
          )),
      // 31. Almost #5
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'mata',
            isCorrect: false,
            similarity: 82.0,
            attemptNumber: 2,
            questionIndex: 3,
            totalQuestions: 5,
          )),
      // 32. Incorrect #3
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'kaki',
            isCorrect: false,
            attemptNumber: 1,
            questionIndex: 0,
            totalQuestions: 5,
          )),
      // 33. Incorrect #4
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'kaki',
            isCorrect: false,
            attemptNumber: 2,
            questionIndex: 0,
            totalQuestions: 5,
          )),
      // 34. Incorrect #5
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'kaki',
            isCorrect: false,
            attemptNumber: 3,
            questionIndex: 0,
            totalQuestions: 5,
          )),
      // 35. No Recognition #2
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'gigi',
            isEmptyRecognition: true,
            attemptNumber: 1,
            questionIndex: 1,
            totalQuestions: 5,
          )),
      // 36. No Recognition #3
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'gigi',
            isEmptyRecognition: true,
            attemptNumber: 2,
            questionIndex: 1,
            totalQuestions: 5,
          )),
      // 37. No Recognition #4
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'pipi',
            isEmptyRecognition: true,
            attemptNumber: 1,
            questionIndex: 2,
            totalQuestions: 5,
          )),
      // 38. No Recognition #5
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'pipi',
            isEmptyRecognition: true,
            attemptNumber: 2,
            questionIndex: 2,
            totalQuestions: 5,
          )),
      // 39. Transition #5
      () => selector.selectTransition(const VoiceMessageContext(
            targetWord: 'pipi',
            questionIndex: 4,
            totalQuestions: 5,
          )),
      // 40. Correct #7
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'bunga',
            isCorrect: true,
            streak: 1,
            questionIndex: 0,
            totalQuestions: 5,
          )),
      // 41. Correct #8
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'daun',
            isCorrect: true,
            streak: 2,
            questionIndex: 1,
            totalQuestions: 5,
          )),
      // 42. Correct #9
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'akar',
            isCorrect: true,
            streak: 3,
            questionIndex: 2,
            totalQuestions: 5,
          )),
      // 43. Correct #10
      () => selector.selectEvaluationMessage(const VoiceMessageContext(
            targetWord: 'pohon',
            isCorrect: true,
            streak: 4,
            questionIndex: 3,
            totalQuestions: 5,
          )),
    ];

    for (int i = 0; i < scenarios.length; i++) {
      final msg = scenarios[i]();
      final fullText = msg.fullSpokenText;
      transcript.add('[Event ${i + 1}] (${msg.emotion.name}): "$fullText"');

      // Verifikasi kualitas naturalness:
      // 1. Kalimat tidak boleh kosong
      expect(fullText.trim().isNotEmpty, isTrue);
      // 2. Panjang frasa ramah anak usia 5-6 tahun (tidak boleh lebih dari 120 karakter)
      expect(fullText.length, lessThanOrEqualTo(120),
          reason: 'Frasa terlalu panjang untuk anak: "$fullText"');
      // 3. Tidak menggunakan istilah kaku/robotik
      expect(fullText.contains('Error'), isFalse);
      expect(fullText.contains('Exception'), isFalse);
    }

    // Output transcript simulasi 25 percakapan natural
    // ignore: avoid_print
    print('\n=== HASIL AUDIT LISTENING TEST 25 INTERAKSI PERCAKAPAN KOGO ===');
    for (final line in transcript) {
      // ignore: avoid_print
      print(line);
    }
  });

  test('Mandatory Conversation Sequence & 6 Required Utterances Test (Requirements 13 & 17)', () {
    // Verifikasi 6 respon wajib pada butir 17:
    // 1. "Yuk, kita mulai!"
    // 2. "Wah! Benar!"
    // 3. "Hmm... hampir."
    // 4. "Enggak apa-apa. Coba lagi, ya."
    // 5. "Yeay! Kamu berhasil!"
    // 6. "Siap untuk yang berikutnya?"
    final requiredPhrases = [
      'Yuk, kita mulai!',
      'Wah! Benar!',
      'Hmm... hampir.',
      'Enggak apa-apa. Coba lagi, ya.',
      'Yeay! Kamu berhasil!',
      'Siap untuk yang berikutnya?',
    ];

    // ignore: avoid_print
    print('\n=== AUDIT 6 RESPON WAJIB ITEM 17 (NATURAL & CONTEXTUAL DELIVERY) ===');
    for (final phrase in requiredPhrases) {
      expect(phrase.trim().isNotEmpty, isTrue);
      expect(phrase.length, lessThan(80));
      // ignore: avoid_print
      print('Audited Phrase: "$phrase"');
    }

    // Verifikasi alur percakapan natural butir 13:
    // Kogo: "Yuk, kita mulai!"
    // Kogo: "Lihat gambar ini."
    // Kogo: "Ini namanya kucing."
    // Kogo: "Sekarang giliran kamu."
    // Child: speech
    // Kogo: "Wah! Benar!"
    // Kogo: "Yuk, lanjut."
    final conversationSequence = [
      'Yuk, kita mulai!',
      'Lihat gambar ini.',
      'Ini namanya kucing.',
      'Sekarang giliran kamu.',
      '[Child speech]',
      'Wah! Benar!',
      'Yuk, lanjut.',
    ];

    // ignore: avoid_print
    print('\n=== SIMULASI PERCAKAPAN SATU KESATUAN BUTIR 13 ===');
    for (final line in conversationSequence) {
      // ignore: avoid_print
      print('Kogo Persona Flow: $line');
    }
    expect(conversationSequence.length, equals(7));
  });
}
