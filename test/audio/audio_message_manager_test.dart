import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/services/audio/audio_message_manager.dart';

void main() {
  group('AudioMessageManager Game Companion & Non-Repeating Audio Tests', () {
    late AudioMessageManager manager;

    setUp(() {
      manager = AudioMessageManager.instance;
      manager.resetHistory();
    });

    test('1. selectInstructionAudio returns valid asset and does not repeat consecutively', () {
      final audio1 = manager.selectInstructionAudio();
      final audio2 = manager.selectInstructionAudio();

      expect(audio1.assetPath, isNotEmpty);
      expect(audio2.assetPath, isNotEmpty);
      expect(audio1.assetPath, isNot(equals(audio2.assetPath)));
    });

    test('2. selectGameIntro provides specific warm intros for all game modes', () {
      final games = ['find_object', 'matching', 'listen_carefully', 'missing_letter', 'listen_repeat'];
      for (final game in games) {
        final intro = manager.selectGameIntro(game);
        expect(intro.assetPath, contains('assets/audio/games/'));
        expect(intro.textRepresentation, isNotEmpty);
      }
    });

    test('3. selectTransitionAudio returns cheerful transition prompts', () {
      final trans1 = manager.selectTransitionAudio();
      final trans2 = manager.selectTransitionAudio();

      expect(trans1.assetPath, contains('transition_next'));
      expect(trans2.assetPath, contains('transition_next'));
      expect(trans1.assetPath, isNot(equals(trans2.assetPath)));
    });

    test('4. selectEncouragementAudio returns warm encouragement for children', () {
      final enc = manager.selectEncouragementAudio();
      expect(enc.assetPath, contains('encouragement_look'));
      expect(enc.textRepresentation, isNotEmpty);
    });

    test('5. selectFeedbackAudio handles isCorrect, streak >= 3, and almostCorrect', () {
      final correctContext = const AudioContextInfo(
        targetWord: 'Buku',
        isCorrect: true,
        streak: 1,
      );
      final streakContext = const AudioContextInfo(
        targetWord: 'Buku',
        isCorrect: true,
        streak: 3,
      );
      final almostContext = const AudioContextInfo(
        targetWord: 'Buku',
        isCorrect: false,
        similarityPercent: 80.0,
      );

      final correctAudio = manager.selectFeedbackAudio(correctContext);
      final streakAudio = manager.selectFeedbackAudio(streakContext);
      final almostAudio = manager.selectFeedbackAudio(almostContext);

      expect(correctAudio.category, equals(AudioCategory.correct));
      expect(streakAudio.category, equals(AudioCategory.streak));
      expect(almostAudio.category, equals(AudioCategory.almostCorrect));
    });

    test('6. getWordAssetPath maps known vocabulary to asset paths', () {
      expect(manager.getWordAssetPath('Bola'), equals('assets/audio/words/bola.mp3'));
      expect(manager.getWordAssetPath('Apel'), equals('assets/audio/words/apel.mp3'));
      expect(manager.getWordAssetPath('UnknownWord'), isNull);
    });

    test('7. avoids repetition within the last 3 events when alternatives exist', () {
      final selectedList = <String>[];
      for (int i = 0; i < 4; i++) {
        final item = manager.selectInstructionAudio();
        selectedList.add(item.assetPath);
      }
      // In a list of 5 options, 4 consecutive picks should all be distinct under a 3-event window
      expect(selectedList.toSet().length, equals(4));
    });
  });
}
