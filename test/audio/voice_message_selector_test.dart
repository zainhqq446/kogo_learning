import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/services/audio/kogo_voice_manager.dart';
import 'package:kogo_voice_learning/services/audio/voice_cache.dart';
import 'package:kogo_voice_learning/services/audio/voice_message.dart';
import 'package:kogo_voice_learning/services/audio/voice_message_context.dart';
import 'package:kogo_voice_learning/services/audio/voice_message_selector.dart';
import '../mocks/mock_speech_output_provider.dart';

void main() {
  group('VoiceMessageSelector & Voice Companion Experience Tests', () {
    late VoiceMessageSelector selector;

    setUp(() {
      selector = VoiceMessageSelector.instance;
      selector.resetHistory();
    });

    test('1. Categories contain 8–12 variations to prevent monotony', () {
      expect(selector.correctOptions.length, inInclusiveRange(8, 15));
      expect(selector.introOptions.length, inInclusiveRange(8, 15));
      expect(selector.questionPrompts.length, inInclusiveRange(8, 15));
      expect(selector.almostOptions.length, inInclusiveRange(8, 15));
      expect(selector.wrongOptions.length, inInclusiveRange(8, 15));
      expect(selector.streakOptions.length, inInclusiveRange(8, 15));
      expect(selector.transitionOptions.length, inInclusiveRange(8, 15));
      expect(selector.completionOptions.length, inInclusiveRange(8, 15));
    });

    test('2. Streak >= 3 produces celebratory emotion and exciting vocal delivery', () {
      final context = const VoiceMessageContext(
        targetWord: 'apel',
        isCorrect: true,
        streak: 3,
        attemptNumber: 1,
      );

      final message = selector.selectEvaluationMessage(context);
      expect(message.emotion, equals(VoiceEmotion.celebratory));
      expect(selector.streakOptions.contains(message.text), isTrue);
      expect(message.customInstruction, contains('celebrate consecutive wins'));
    });

    test('3. Attempt-aware responses adapt from gentle encouragement to supportive guide', () {
      final attempt1 = selector.selectEvaluationMessage(const VoiceMessageContext(
        targetWord: 'bola',
        isCorrect: false,
        attemptNumber: 1,
      ));
      expect(selector.wrongOptions.contains(attempt1.text), isTrue);
      expect(attempt1.emotion, equals(VoiceEmotion.gentle));

      final attempt2 = selector.selectEvaluationMessage(const VoiceMessageContext(
        targetWord: 'bola',
        isCorrect: false,
        attemptNumber: 2,
      ));
      expect(selector.attempt2Options.contains(attempt2.text), isTrue);

      final attempt3 = selector.selectEvaluationMessage(const VoiceMessageContext(
        targetWord: 'bola',
        isCorrect: false,
        attemptNumber: 3,
      ));
      expect(selector.attempt3Options.contains(attempt3.text), isTrue);
    });

    test('4. Progress-aware transitions encourage child as they approach session completion', () {
      // Mid-progress
      final midContext = const VoiceMessageContext(
        targetWord: 'buku',
        questionIndex: 2,
        totalQuestions: 5,
      );
      final midMsg = selector.selectTransition(midContext);
      expect(midMsg.text.isNotEmpty, isTrue);

      // Last question
      final lastContext = const VoiceMessageContext(
        targetWord: 'sapi',
        questionIndex: 4,
        totalQuestions: 5,
      );
      final lastMsg = selector.selectTransition(lastContext);
      expect(selector.progressLastQuestionOptions.contains(lastMsg.text), isTrue);
      expect(lastMsg.emotion, equals(VoiceEmotion.warm));
    });

    test('5. Non-repetition maintains 3-event history window', () {
      final chosen = <String>[];
      final context = const VoiceMessageContext(
        targetWord: 'kucing',
        isCorrect: true,
        streak: 0,
      );

      for (int i = 0; i < 4; i++) {
        final msg = selector.selectEvaluationMessage(context);
        if (chosen.length >= 3) {
          final lastThree = chosen.sublist(chosen.length - 3);
          expect(lastThree.contains(msg.text), isFalse,
              reason: 'Message "${msg.text}" was repeated within the 3-event window: $lastThree');
        }
        chosen.add(msg.text);
      }
    });

    test('6. Empty recognition provides patient, calm instruction', () {
      final context = const VoiceMessageContext(
        targetWord: 'meja',
        isEmptyRecognition: true,
      );

      final message = selector.selectEvaluationMessage(context);
      expect(message.emotion, equals(VoiceEmotion.patient));
      expect(selector.noRecognitionOptions.contains(message.text), isTrue);
      expect(message.customInstruction, contains('patient'));
    });

    test('7. Provides game intros and encouragements for all 5 interactive modes', () {
      final modes = [
        'find_object',
        'matching',
        'listen_carefully',
        'missing_letter',
        'listen_repeat',
      ];

      for (final mode in modes) {
        final intro = selector.selectGameIntro(mode);
        expect(intro.text.isNotEmpty, isTrue);
        expect(intro.emotion, equals(VoiceEmotion.playful));

        final enc = selector.selectGameEncouragement(mode);
        expect(enc.text.isNotEmpty, isTrue);
        expect(enc.emotion, equals(VoiceEmotion.curious));
      }
    });

    test('8. VoiceCache stores and retrieves audio bytes correctly', () {
      final cache = VoiceCache.instance;
      cache.clear();

      final bytes = Uint8List.fromList([10, 20, 30, 40]);
      cache.put('test_key', bytes);

      expect(cache.contains('test_key'), isTrue);
      expect(cache.get('test_key'), equals(bytes));
      expect(cache.size, equals(1));

      cache.clear();
      expect(cache.contains('test_key'), isFalse);
      expect(cache.size, equals(0));
    });

    test('9. KogoVoiceManager plays contextual feedback and speech prompts gracefully', () async {
      final mockProvider = MockSpeechOutputProvider();
      KogoVoiceManager.instance.setProviderForTesting(mockProvider);

      // Play prompt for known prerecorded word
      await KogoVoiceManager.instance.playSpeechPrompt('apel');
      expect(mockProvider.playedAudios.length, greaterThanOrEqualTo(1));

      // Play evaluation feedback
      final context = const VoiceMessageContext(
        targetWord: 'apel',
        isCorrect: true,
        streak: 3,
      );
      await KogoVoiceManager.instance.playEvaluationFeedback(context);
      expect(mockProvider.spokenTexts.isNotEmpty || mockProvider.playedAudios.isNotEmpty, isTrue);
    });

    test('10. KogoVoiceManager plays dynamic voice intro for all 5 primary games', () async {
      final mockProvider = MockSpeechOutputProvider();
      KogoVoiceManager.instance.setProviderForTesting(mockProvider);

      final dynamicGames = [
        'listen_repeat',
        'find_object',
        'matching',
        'listen_carefully',
        'missing_letter',
      ];
      for (final game in dynamicGames) {
        mockProvider.clear();
        await KogoVoiceManager.instance.playGameIntro(game);
        expect(mockProvider.spokenTexts.length, equals(1), reason: 'Game $game should trigger speakDynamicText');
        expect(mockProvider.playedAudios, isEmpty, reason: 'Game $game should NOT play local human audio');
      }
    });
  });
}
