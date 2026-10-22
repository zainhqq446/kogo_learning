import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/services/audio/kogo_voice_style.dart';
import 'package:kogo_voice_learning/services/audio/speech_message_manager.dart';

void main() {
  group('SpeechMessageManager & Voice Variation Tests', () {
    late SpeechMessageManager manager;

    setUp(() {
      manager = SpeechMessageManager.instance;
      manager.resetHistory();
    });

    test('1. Instruction messages are cheerful, child-friendly, and non-empty', () {
      final msg = manager.getInstructionMessage();
      expect(msg, isNotEmpty);
      expect(manager.instructionMessages.contains(msg), isTrue);
    });

    test('2. Correct answer produces encouraging message and does not repeat consecutively', () {
      final context1 = const SpeechMessageContext(
        targetWord: 'Buku',
        isCorrect: true,
        similarityPercent: 100.0,
      );

      final msg1 = manager.generateMessage(context1);
      final msg2 = manager.generateMessage(context1);

      expect(msg1, isNotEmpty);
      expect(msg2, isNotEmpty);
      expect(msg1, isNot(equals(msg2)), reason: 'Non-repeating rule must prevent consecutive duplicates');
      expect(manager.correctMessages.contains(msg1), isTrue);
      expect(manager.correctMessages.contains(msg2), isTrue);
    });

    test('3. Almost correct answer (high similarity) gives gentle, encouraging feedback without shame', () {
      final context = const SpeechMessageContext(
        targetWord: 'Buku',
        isCorrect: false,
        similarityPercent: 75.0,
      );

      final msg = manager.generateMessage(context);
      expect(msg, isNotEmpty);
      expect(manager.almostCorrectMessages.contains(msg), isTrue);

      // Verify no negative or punishing words
      expect(msg.toLowerCase().contains('salah'), isFalse);
      expect(msg.toLowerCase().contains('gagal'), isFalse);
    });

    test('4. Incorrect answer (low similarity) gives soft retry encouragement', () {
      final context = const SpeechMessageContext(
        targetWord: 'Buku',
        isCorrect: false,
        similarityPercent: 30.0,
        attemptNumber: 1,
      );

      final msg = manager.generateMessage(context);
      expect(msg, isNotEmpty);
      expect(manager.incorrectMessages.contains(msg), isTrue);
      expect(msg.toLowerCase().contains('salah'), isFalse);
    });

    test('5. Empty recognition provides audio prompt to speak again into the mic', () {
      final context = const SpeechMessageContext(
        targetWord: 'Buku',
        isCorrect: false,
        isEmptyRecognition: true,
      );

      final msg = manager.generateMessage(context);
      expect(msg, isNotEmpty);
      expect(manager.noRecognitionMessages.contains(msg), isTrue);
    });

    test('6. Second attempt (retry) provides calming support', () {
      final context = const SpeechMessageContext(
        targetWord: 'Buku',
        isCorrect: false,
        similarityPercent: 40.0,
        attemptNumber: 2,
      );

      final msg = manager.generateMessage(context);
      expect(msg, isNotEmpty);
      expect(manager.retryMessages.contains(msg), isTrue);
    });

    test('7. Consecutive streak >= 3 provides milestone celebration messages', () {
      final context = const SpeechMessageContext(
        targetWord: 'Buku',
        isCorrect: true,
        streak: 3,
      );

      final msg = manager.generateMessage(context);
      expect(msg, isNotEmpty);
      expect(manager.streakMessages.contains(msg), isTrue);
    });

    test('8. Activity completion provides warm celebratory message', () {
      final context = const SpeechMessageContext(
        targetWord: 'Buku',
        isCompleted: true,
      );

      final msg = manager.generateMessage(context);
      expect(msg, isNotEmpty);
      expect(manager.completionMessages.contains(msg), isTrue);
    });

    test('9. Speech invitation incorporates target word naturally', () {
      final msg = manager.getSpeechInvitation('Bola');
      expect(msg, contains('Bola'));
    });

    test('10. KogoVoiceStyle matches early childhood audio profile requirements', () {
      const style = KogoVoiceStyle.childFriendly;
      expect(style.language, equals('id-ID'));
      expect(style.speechRate, lessThan(0.50)); // Moderate and clear
      expect(style.speechRate, greaterThan(0.35));
      expect(style.pitch, greaterThan(1.0)); // Cheerful & warm
      expect(style.volume, equals(1.0));
    });
  });
}
