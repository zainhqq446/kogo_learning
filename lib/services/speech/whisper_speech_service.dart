import 'dart:async';
import 'dart:typed_data';

import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

class WhisperSpeechService {
  WhisperSpeechService._();

  static final WhisperSpeechService instance =
      WhisperSpeechService._();

  WhisperModelManager? _modelManager;
  WhisperEngine? _engine;
  WhisperRecorder? _recorder;
  WhisperVad? _vad;

  StreamSubscription<RecordingChunk>? _recordingSubscription;
  Completer<void>? _recordingDone;

  final List<double> _samples = [];
  final List<double> _vadBuffer = [];

  bool _initialized = false;
  bool _available = false;
  bool _isRecording = false;

  bool _speechDetected = false;
  bool _autoStopTriggered = false;

  int _silentWindows = 0;

  String? _loadedModelId;
  String? _loadedVadModelId;

  DateTime? _recordingStartedAt;

  void Function()? _onSpeechEnded;

  bool get isAvailable => _available;

  bool get isRecording => _isRecording;

  double get recordedSeconds {
    return _samples.length / 16000.0;
  }

  Future<void> initialize({
    void Function(double progress)? onDownloadProgress,
    bool useBaseModel = false,
  }) async {
    final whisperDescriptor = useBaseModel
        ? WhisperModelCatalog.base
        : WhisperModelCatalog.tiny;

    _modelManager ??= WhisperModelManager();

    // ==========================================
    // WHISPER MODEL
    // ==========================================

    if (_loadedModelId != whisperDescriptor.id) {
      _engine?.dispose();
      _engine = null;

      var whisperModel =
          await _modelManager!.findCatalogModel(
        whisperDescriptor,
      );

      if (whisperModel == null) {
        await for (final progress
            in _modelManager!.downloadCatalogModel(
          whisperDescriptor,
        )) {
          final fraction = progress.fraction;

          if (fraction != null) {
            onDownloadProgress?.call(
              fraction * 0.6,
            );
          }
        }

        whisperModel =
            await _modelManager!.findCatalogModel(
          whisperDescriptor,
        );
      }

      if (whisperModel == null) {
        throw StateError(
          'Model Whisper gagal dipasang.',
        );
      }

      _engine = await WhisperEngine.load(
        whisperModel.path,
        config: const WhisperConfig(
          useGpu: false,
          useFlashAttention: true,
        ),
      );

      _loadedModelId = whisperDescriptor.id;
    }

    // ==========================================
    // SILERO VAD
    // ==========================================

    final vadDescriptor =
        WhisperModelCatalog.sileroVad;

    if (_vad == null ||
        _loadedVadModelId != vadDescriptor.id) {
      var vadModel =
          await _modelManager!.findCatalogModel(
        vadDescriptor,
      );

      if (vadModel == null) {
        await for (final progress
            in _modelManager!.downloadCatalogModel(
          vadDescriptor,
        )) {
          final fraction = progress.fraction;

          if (fraction != null) {
            onDownloadProgress?.call(
              0.6 + (fraction * 0.4),
            );
          }
        }

        vadModel =
            await _modelManager!.findCatalogModel(
          vadDescriptor,
        );
      }

      if (vadModel == null) {
        throw StateError(
          'Model Silero VAD gagal dipasang.',
        );
      }

      _vad?.dispose();

      _vad = WhisperVad.load(
        vadModel.path,
        useGpu: false,
        threads: 2,
      );

      _loadedVadModelId = vadDescriptor.id;
    }

    _initialized = true;
    _available = true;
  }

  Future<bool> requestMicrophonePermission() async {
    final recorder = _recorder ??= WhisperRecorder();

    return recorder.requestPermission();
  }

  Future<void> startRecording({
    void Function()? onSpeechEnded,
  }) async {
    if (_isRecording) {
      return;
    }

    if (!_initialized || !_available) {
      await initialize();
    }

    final recorder = _recorder ??= WhisperRecorder();

    if (_vad == null) {
      throw StateError(
        'Silero VAD belum siap.',
      );
    }

    final permissionGranted =
        await recorder.requestPermission();

    if (!permissionGranted) {
      throw StateError(
        'Izin microphone tidak diberikan.',
      );
    }

    _samples.clear();
    _vadBuffer.clear();

    _speechDetected = false;
    _autoStopTriggered = false;
    _silentWindows = 0;

    _onSpeechEnded = onSpeechEnded;

    _vad!.reset();

    _recordingDone = Completer<void>();

    _recordingStartedAt = DateTime.now();
    _isRecording = true;

    final stream = await recorder.start(
      sampleRate: 16000,
      chunkMilliseconds: 100,
    );

    await _recordingSubscription?.cancel();

    _recordingSubscription = stream.listen(
      _handleRecordingChunk,
      onError: (Object error, StackTrace stackTrace) {
        if (!(_recordingDone?.isCompleted ?? true)) {
          _recordingDone!.completeError(
            error,
            stackTrace,
          );
        }
      },
      onDone: () {
        if (!(_recordingDone?.isCompleted ?? true)) {
          _recordingDone!.complete();
        }
      },
      cancelOnError: false,
    );
  }

  void _handleRecordingChunk(RecordingChunk chunk) {
    if (!_isRecording) {
      return;
    }

    _samples.addAll(chunk.samples);
    _vadBuffer.addAll(chunk.samples);

    const vadWindowSamples = 5120;

    if (_vadBuffer.length < vadWindowSamples) {
      return;
    }

    final vad = _vad;

    if (vad == null) {
      return;
    }

    final windowSamples = Float32List.fromList(
      _vadBuffer.sublist(
        0,
        vadWindowSamples,
      ),
    );

    _vadBuffer.removeRange(
      0,
      vadWindowSamples,
    );

    final speech = vad.isSpeech(
      windowSamples,
      continuous: true,
    );

    if (speech) {
      _speechDetected = true;
      _silentWindows = 0;
      return;
    }

    if (!_speechDetected) {
      return;
    }

    _silentWindows++;

    // 3 × 320 ms = ±960 ms hening.
    if (_silentWindows >= 3 &&
        !_autoStopTriggered &&
        _samples.length >= 11200) {
      _autoStopTriggered = true;

      final callback = _onSpeechEnded;

      if (callback != null) {
        callback();
      }
    }
  }

  Future<WhisperTranscriptionResult>
      stopAndTranscribe({
    bool useBaseModel = false,
  }) async {
    // Simpan waktu mulai SEBELUM recorder dihentikan.
    final recordingStartedAt =
        _recordingStartedAt;

    if (_isRecording) {
      await _stopRecorderOnly();
    }

    if (_samples.isEmpty) {
      throw StateError(
        'Tidak ada audio yang berhasil direkam.',
      );
    }

    // Model sudah dimuat sebelumnya.
    // initialize hanya memastikan model yang diminta benar.
    await initialize(
      useBaseModel: useBaseModel,
    );

    final engine = _engine;

    if (engine == null) {
      throw StateError(
        'Whisper engine belum siap.',
      );
    }

    final rawSamples =
        Float32List.fromList(_samples);

    // ==========================================
    // VAD: ambil hanya bagian speech
    // ==========================================

    Float32List speechSamples = rawSamples;

    final vad = _vad;

    if (vad != null) {
      vad.reset();

      final segments = vad.segments(
        rawSamples,
        threshold: 0.35,
        minSpeechMs: 180,
        minSilenceMs: 180,
        maxSpeechSeconds: 3,
        speechPadMs: 100,
        samplesOverlap: 0.1,
      );

      if (segments.isNotEmpty) {
        final startSample = (
          segments.first.start.inMilliseconds * 16
        ).clamp(
          0,
          rawSamples.length,
        );

        final endSample = (
          segments.last.end.inMilliseconds * 16
        ).clamp(
          0,
          rawSamples.length,
        );

        if (endSample > startSample) {
          speechSamples =
              Float32List.fromList(
            rawSamples.sublist(
              startSample,
              endSample,
            ),
          );
        }
      }
    }

    // Maksimal satu ucapan 3 detik.
    const maxSpeechSamples =
        16000 * 3;

    if (speechSamples.length >
        maxSpeechSamples) {
      speechSamples =
          Float32List.fromList(
        speechSamples.sublist(
          0,
          maxSpeechSamples,
        ),
      );
    }

    final speechSeconds =
        speechSamples.length / 16000.0;

    // ==========================================
    // WHISPER
    // ==========================================

    final inferenceStartedAt =
        DateTime.now();

    final options =
        const TranscribeOptions(
      language: 'id',
      translate: false,
      detectLanguage: false,
      noContext: true,
      suppressBlank: true,
      suppressNonSpeechTokens: false,
      tokenTimestamps: false,
      noTimestamps: true,
      singleSegment: true,
    ).withPerformanceMode(
      WhisperPerformanceMode.responsive,
    );

    final task = engine.transcribe(
      speechSamples,
      options: options,
    );

    final result = await task.result;

    final measuredInferenceTime =
        DateTime.now().difference(
      inferenceStartedAt,
    );

    final totalElapsed =
        recordingStartedAt == null
            ? measuredInferenceTime
            : DateTime.now().difference(
                recordingStartedAt,
              );

    return WhisperTranscriptionResult(
      text: result.text.trim(),
      recordedSeconds:
          rawSamples.length / 16000.0,
      speechSeconds: speechSeconds,
      inferenceTime: result.processingTime,
      measuredInferenceTime:
          measuredInferenceTime,
      totalElapsed: totalElapsed,
    );
  }

  Future<void> _stopRecorderOnly() async {
    final recorder = _recorder;

    if (recorder != null && _isRecording) {
      await recorder.stop();
    }

    _isRecording = false;

    await _recordingSubscription?.cancel();
    _recordingSubscription = null;

    _recordingDone = null;

    _onSpeechEnded = null;

    _autoStopTriggered = false;
    _silentWindows = 0;

    _recordingStartedAt = null;
  }

  Future<void> stopRecording() async {
    await _stopRecorderOnly();
  }

  Future<void> cancelRecording() async {
    final recorder = _recorder;

    if (recorder != null && _isRecording) {
      await recorder.stop();
    }

    await _recordingSubscription?.cancel();

    _recordingSubscription = null;
    _recordingDone = null;

    _onSpeechEnded = null;

    _samples.clear();
    _vadBuffer.clear();

    _speechDetected = false;
    _autoStopTriggered = false;
    _silentWindows = 0;

    _isRecording = false;
    _recordingStartedAt = null;

    _vad?.reset();
  }

  void dispose() {
    _recordingSubscription?.cancel();

    if (_isRecording) {
      _recorder?.stop();
    }

    _recordingSubscription = null;
    _recordingDone = null;

    _recorder = null;

    _vad?.dispose();
    _vad = null;

    _engine?.dispose();
    _engine = null;

    _modelManager?.close();
    _modelManager = null;

    _samples.clear();
    _vadBuffer.clear();

    _initialized = false;
    _available = false;
    _isRecording = false;

    _speechDetected = false;
    _autoStopTriggered = false;
    _silentWindows = 0;

    _loadedModelId = null;
    _loadedVadModelId = null;

    _recordingStartedAt = null;
    _onSpeechEnded = null;
  }
}

class WhisperTranscriptionResult {
  final String text;

  final double recordedSeconds;

  final double speechSeconds;

  final Duration inferenceTime;

  final Duration measuredInferenceTime;

  final Duration totalElapsed;

  const WhisperTranscriptionResult({
    required this.text,
    required this.recordedSeconds,
    required this.speechSeconds,
    required this.inferenceTime,
    required this.measuredInferenceTime,
    required this.totalElapsed,
  });
}