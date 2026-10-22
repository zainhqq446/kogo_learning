import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/services/speech/speech_evaluator.dart';

void main() {
  const evaluator = SpeechEvaluator();

  group('SpeechEvaluator Pronunciation Evaluation Tests', () {
    test('exact match: case-insensitive identical string evaluates as correct with 0 distance and 100% similarity', () {
      final result = evaluator.evaluate(
        targetText: 'BOLA',
        recognizedText: 'bola',
        confidence: 0.95,
        duration: const Duration(milliseconds: 500),
      );

      expect(result.targetText, equals('BOLA'));
      expect(result.recognizedText, equals('bola'));
      expect(result.normalizedTarget, equals('bola'));
      expect(result.normalizedRecognized, equals('bola'));
      expect(result.editDistance, equals(0));
      expect(result.similarityScore, equals(1.0));
      expect(result.similarityPercent, equals(100.0));
      expect(result.confidence, equals(0.95));
      expect(result.isCorrect, isTrue);
      expect(result.feedback, contains('Hebat'));
      expect(result.duration, equals(const Duration(milliseconds: 500)));
    });

    test('missing character: omission of one letter increases edit distance and reduces similarity', () {
      // "KAPAL" vs "KAPA" (missing 'L') -> edit distance 1
      final result = evaluator.evaluate(
        targetText: 'KAPAL',
        recognizedText: 'KAPA',
      );

      expect(result.normalizedTarget, equals('kapal'));
      expect(result.normalizedRecognized, equals('kapa'));
      expect(result.editDistance, equals(1));
      // 1.0 - (1 / 5) = 0.8
      expect(result.similarityScore, closeTo(0.8, 0.001));
      expect(result.similarityPercent, equals(80.0));
      expect(result.isCorrect, isFalse);
      expect(result.feedback, contains('Hampir tepat'));
    });

    test('extra character: insertion of letter increases edit distance and reduces similarity', () {
      // "BOLA" vs "BOLAS" (extra 'S') -> edit distance 1
      final result = evaluator.evaluate(
        targetText: 'BOLA',
        recognizedText: 'BOLAS',
      );

      expect(result.normalizedTarget, equals('bola'));
      expect(result.normalizedRecognized, equals('bolas'));
      expect(result.editDistance, equals(1));
      // 1.0 - (1 / 5) = 0.8
      expect(result.similarityScore, closeTo(0.8, 0.001));
      expect(result.similarityPercent, equals(80.0));
      expect(result.isCorrect, isFalse);
    });

    test('substitution: KOPER vs KOPEL must stay distinctly different and not forced to target', () {
      final result = evaluator.evaluate(
        targetText: 'KOPER',
        recognizedText: 'KOPEL',
      );

      // Rule: recognized text must NOT be changed to target
      expect(result.targetText, equals('KOPER'));
      expect(result.recognizedText, equals('KOPEL'));
      expect(result.normalizedTarget, equals('koper'));
      expect(result.normalizedRecognized, equals('kopel'));

      // 'R' -> 'L' is 1 substitution
      expect(result.editDistance, equals(1));
      // 1.0 - (1 / 5) = 0.8
      expect(result.similarityScore, closeTo(0.8, 0.001));
      expect(result.similarityPercent, equals(80.0));
      expect(result.isCorrect, isFalse);
    });

    test('empty recognition: handles silence / empty recognized text without throwing', () {
      final result = evaluator.evaluate(
        targetText: 'MATA',
        recognizedText: '',
      );

      expect(result.normalizedTarget, equals('mata'));
      expect(result.normalizedRecognized, equals(''));
      expect(result.editDistance, equals(4));
      expect(result.similarityScore, equals(0.0));
      expect(result.similarityPercent, equals(0.0));
      expect(result.isCorrect, isFalse);
      expect(result.feedback, contains('Suara belum terdengar'));
    });

    test('uppercase / lowercase / extra spaces normalization', () {
      final result = evaluator.evaluate(
        targetText: '  sEpA-tU   ',
        recognizedText: 'SEPATU',
      );

      // Normalization handles casing and trims
      expect(result.normalizedTarget, equals('sepa-tu'));
      expect(result.normalizedRecognized, equals('sepatu'));
      expect(result.editDistance, equals(1)); // hyphen '-'
    });

    test('confidence vs similarity vs correctness independence', () {
      // High ASR confidence, but wrong pronunciation (recognized "KUDA", target "BOLA")
      final result = evaluator.evaluate(
        targetText: 'BOLA',
        recognizedText: 'KUDA',
        confidence: 0.99, // ASR is very confident it heard "KUDA"
      );

      // Rule: confidence != similarity != isCorrect
      expect(result.confidence, equals(0.99));
      expect(result.similarityScore, lessThan(0.5));
      expect(result.isCorrect, isFalse);

      // Wrong answer is valid as a research log and object
      expect(result.toMap()['is_correct'], equals(0));
      expect(result.toMap()['target_text'], equals('BOLA'));
      expect(result.toMap()['recognized_text'], equals('KUDA'));
    });

    test('custom threshold allows partial tolerance when configured', () {
      const tolerantEvaluator = SpeechEvaluator(correctnessThreshold: 0.75);

      final result = tolerantEvaluator.evaluate(
        targetText: 'KAPAL',
        recognizedText: 'KAPA', // 80% similarity >= 75%
      );

      expect(result.similarityPercent, equals(80.0));
      expect(result.isCorrect, isTrue);
    });
  });
}
