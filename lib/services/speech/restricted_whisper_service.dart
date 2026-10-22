import 'package:flutter/foundation.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

class RestrictedWhisperResult {
  final String target;
  final String recognized;
  final bool isCorrect;
  final Duration audioDuration;
  final List<WhisperSegment> segments;

  const RestrictedWhisperResult({
    required this.target,
    required this.recognized,
    required this.isCorrect,
    required this.audioDuration,
    required this.segments,
  });
}

class RestrictedWhisperService {
  WhisperEngine? _engine;
  WhisperStreamTask? _task;

  bool _listening = false;

  Future<void> initialize({
    required String modelPath,
  }) async {
    if (_engine != null) {
      return;
    }

    debugPrint('[WHISPER] Loading model...');

    _engine = await WhisperEngine.load(
      modelPath,
      config: const WhisperConfig(
        useGpu: true,
        useFlashAttention: true,
        useDtw: false,
      ),
    );

    debugPrint('[WHISPER] Model loaded');
    debugPrint(
      '[WHISPER] Engine: ${_engine!.modelInfo}',
    );
    debugPrint(
      '[WHISPER] System: ${WhisperEngine.systemInfo}',
    );
  }

  Future<bool> startListening({
    required String targetWord,
    void Function(String text)? onPartial,
    void Function(String message)? onError,
  }) async {
    final engine = _engine;

    if (engine == null) {
      onError?.call('Model Whisper belum siap.');
      return false;
    }

    if (_listening) {
      return false;
    }

    try {
      final normalizedTarget = _normalize(targetWord);

      debugPrint('');
      debugPrint('========================================');
      debugPrint('       RESTRICTED WHISPER TEST');
      debugPrint('========================================');
      debugPrint('TARGET: $normalizedTarget');
      debugPrint('LANGUAGE: id');
      debugPrint('PROMPT: $normalizedTarget');
      debugPrint('========================================');

      final options = TranscribeOptions(
        strategy: WhisperSamplingStrategy.greedy,
        threads: 4,
        language: 'id',
        translate: false,
        detectLanguage: false,
        singleSegment: true,
        noContext: true,
        noTimestamps: true,
        tokenTimestamps: false,
        suppressBlank: true,
        suppressNonSpeechTokens: true,
        temperature: 0.0,
        temperatureIncrement: 0.0,
        maxTokensPerSegment: 16,
        noSpeechThreshold: 0.6,
        initialPrompt:
            'Kata yang diucapkan adalah "$normalizedTarget".',
        greedyBestOf: 1,
      ).withPerformanceMode(
        WhisperPerformanceMode.responsive,
      );

      _task = await engine.transcribeMicrophone(
        options: options,
        config: WhisperStreamConfig(
          updateInterval: const Duration(seconds: 1),
          windowDuration: const Duration(seconds: 6),
          confirmationLag: const Duration(seconds: 1),
        ),
      );

      _listening = true;

      _task!.updates.listen(
        (update) {
          final text = update.text.trim();

          debugPrint(
            '[WHISPER PARTIAL] '
            'text="$text" '
            'audio=${update.audioDuration.inMilliseconds}ms '
            'final=${update.isFinal}',
          );

          onPartial?.call(text);
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint(
            '[WHISPER STREAM ERROR] '
            '${error.toString()}',
          );

          debugPrint(
            stackTrace.toString(),
          );

          onError?.call(error.toString());
        },
      );

      debugPrint('[WHISPER] microphone started');

      return true;
    } catch (e, stackTrace) {
      debugPrint(
        '[WHISPER START ERROR] ${e.toString()}',
      );

      debugPrint(
        stackTrace.toString(),
      );

      _listening = false;
      onError?.call(e.toString());

      return false;
    }
  }

  Future<RestrictedWhisperResult?> stopListening({
    required String targetWord,
  }) async {
    final task = _task;

    if (task == null) {
      return null;
    }

    try {
      debugPrint('');
      debugPrint('[WHISPER] stopping microphone...');

      final update = await task.stop();

      _listening = false;
      _task = null;

      final recognized = update.confirmedText.trim();
      final target = _normalize(targetWord);
      final normalizedRecognized = _normalize(recognized);

      final correct =
          normalizedRecognized == target;

      debugPrint('');
      debugPrint('========================================');
      debugPrint('         WHISPER FINAL RESULT');
      debugPrint('========================================');
      debugPrint('TARGET     : $target');
      debugPrint(
        'RECOGNIZED : $normalizedRecognized',
      );
      debugPrint(
        'CORRECT    : $correct',
      );
      debugPrint(
        'AUDIO      : '
        '${update.audioDuration.inMilliseconds} ms',
      );
      debugPrint(
        'SEGMENTS   : '
        '${update.confirmedSegments.length}',
      );

      for (int i = 0;
          i < update.confirmedSegments.length;
          i++) {
        final segment = update.confirmedSegments[i];

        debugPrint(
          'SEGMENT[$i]: "${segment.text}" '
          '${segment.start} → ${segment.end}',
        );

        for (final token in segment.tokens) {
          debugPrint(
            '   TOKEN: "${token.text}" '
            'prob=${token.probability.toStringAsFixed(4)}',
          );
        }
      }

      debugPrint(
        '========================================',
      );
      debugPrint('');

      return RestrictedWhisperResult(
        target: targetWord,
        recognized: recognized,
        isCorrect: correct,
        audioDuration: update.audioDuration,
        segments: update.confirmedSegments,
      );
    } catch (e, stackTrace) {
      _listening = false;
      _task = null;

      debugPrint(
        '[WHISPER STOP ERROR] ${e.toString()}',
      );

      debugPrint(
        stackTrace.toString(),
      );

      rethrow;
    }
  }

  Future<void> cancelListening() async {
    final task = _task;

    if (task == null) {
      return;
    }

    try {
      await task.cancel();
    } finally {
      _task = null;
      _listening = false;
    }
  }

  bool get isListening => _listening;

  String _normalize(String text) {
    return text
        .toLowerCase()
        .trim()
        .replaceAll(
          RegExp(
            r'[^\p{L}\p{N}\s]+',
            unicode: true,
          ),
          '',
        )
        .replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
  }

  void dispose() {
    _task?.cancel();
    _task = null;

    _engine?.dispose();
    _engine = null;

    _listening = false;
  }
}