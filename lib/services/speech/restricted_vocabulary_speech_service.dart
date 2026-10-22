import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter/foundation.dart';

class RestrictedSpeechResult {
  final String recognizedText;
  final String selectedText;
  final List<String> alternates;
  final double confidence;
  final bool isFinal;

  const RestrictedSpeechResult({
    required this.recognizedText,
    required this.selectedText,
    required this.alternates,
    required this.confidence,
    required this.isFinal,
  });
}

class RestrictedVocabularySpeechService {
  final SpeechToText _speech = SpeechToText();

  bool _initialized = false;
  String _targetWord = '';
  List<String> _vocabulary = [];

  Future<bool> initialize() async {
    if (_initialized) {
      return true;
    }

    _initialized = await _speech.initialize(
      debugLogging: true,
      onStatus: (status) {
        debugPrint('[SPEECH STATUS] $status');
      },
      onError: (SpeechRecognitionError error) {
        debugPrint(
          '[SPEECH ERROR] '
          'errorMsg=${error.errorMsg}, '
          'permanent=${error.permanent}',
        );
      },
    );

    debugPrint('[SPEECH] initialized=$_initialized');

    if (_initialized) {
      final locales = await _speech.locales();

      final indonesiaLocales = locales
          .where(
            (locale) =>
                locale.localeId.toLowerCase().startsWith('id'),
          )
          .toList();

      debugPrint('[SPEECH] Indonesian locales:');

      for (final locale in indonesiaLocales) {
        debugPrint(
          '  ${locale.localeId} - ${locale.name}',
        );
      }
    }

    return _initialized;
  }

  Future<bool> startListening({
    required String targetWord,
    List<String>? vocabulary,
    void Function(RestrictedSpeechResult result)? onResult,
    void Function(String text)? onPartial,
    void Function(String message)? onError,
  }) async {
    final ready = await initialize();

    if (!ready) {
      onError?.call(
        'Speech recognition tidak tersedia.',
      );
      return false;
    }

    if (_speech.isListening) {
      await _speech.stop();
    }

    _targetWord = _normalize(targetWord);

    final rawVocabulary = <String>[
      targetWord,
      ...?vocabulary,
    ];

    _vocabulary = rawVocabulary
        .map(_normalize)
        .where((word) => word.isNotEmpty)
        .toSet()
        .toList();

    debugPrint('');
    debugPrint('==========================================');
    debugPrint(' RESTRICTED VOCABULARY SPEECH TEST');
    debugPrint('==========================================');
    debugPrint('TARGET     : $_targetWord');
    debugPrint('VOCABULARY : $_vocabulary');
    debugPrint('LOCALE     : id-ID');
    debugPrint('ON DEVICE  : false');
    debugPrint('==========================================');

    final options = SpeechListenOptions(
      partialResults: true,
      onDevice: false,
      listenMode: ListenMode.confirmation,
      localeId: 'id-ID',
      pauseFor: const Duration(milliseconds: 900),
      listenFor: const Duration(seconds: 5),
      cancelOnError: true,
      autoPunctuation: false,
      contextualPhrases: _vocabulary,
    );

    try {
      await _speech.listen(
        listenOptions: options,
        onResult: (SpeechRecognitionResult result) {
          final rawText = result.recognizedWords.trim();

          final alternates = result.alternates
              .map(
                (item) => item.recognizedWords.trim(),
              )
              .where((text) => text.isNotEmpty)
              .toList();

          String selectedText = rawText;

          // Kalau target muncul sebagai salah satu alternate,
          // gunakan target tersebut.
          final exactTarget = alternates.where(
            (text) => _normalize(text) == _targetWord,
          );

          if (exactTarget.isNotEmpty) {
            selectedText = exactTarget.first;
          }

          final speechResult = RestrictedSpeechResult(
            recognizedText: rawText,
            selectedText: selectedText,
            alternates: alternates,
            confidence: result.confidence,
            isFinal: result.finalResult,
          );

          debugPrint('');
          debugPrint('----------- SPEECH RESULT -----------');
          debugPrint('RAW        : $rawText');
          debugPrint('SELECTED   : $selectedText');
          debugPrint('FINAL      : ${result.finalResult}');
          debugPrint(
            'CONFIDENCE : '
            '${result.hasConfidenceRating ? result.confidence : 'N/A'}',
          );
          debugPrint('ALTERNATES : $alternates');
          debugPrint('-------------------------------------');

          onPartial?.call(rawText);
          onResult?.call(speechResult);
        },
      );

      return true;
    } catch (e) {
      debugPrint('[SPEECH START ERROR] $e');
      onError?.call(e.toString());
      return false;
    }
  }

  Future<void> stopListening() async {
    if (_speech.isListening) {
      debugPrint('[SPEECH] stopping...');
      await _speech.stop();
    }
  }

  Future<void> cancelListening() async {
    if (_speech.isListening) {
      debugPrint('[SPEECH] cancelling...');
      await _speech.cancel();
    }
  }

  bool get isListening => _speech.isListening;

  String get targetWord => _targetWord;

  List<String> get vocabulary =>
      List.unmodifiable(_vocabulary);

  bool matchesTarget(String text) {
    return _normalize(text) == _targetWord;
  }

  String normalize(String text) {
    return _normalize(text);
  }

  String _normalize(String text) {
    return text
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]+', unicode: true), '')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  void dispose() {
    if (_speech.isListening) {
      _speech.cancel();
    }
  }
}
