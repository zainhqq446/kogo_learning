import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

import 'speech_recognition_error_model.dart';
import 'speech_recognition_provider.dart';
import 'speech_recognition_result_model.dart';

/// Implementasi [SpeechRecognitionProvider] menggunakan engine Whisper Tiny Multilingual.
///
/// Karakteristik utama:
/// 1. Menggunakan model Whisper Tiny Multilingual (`WhisperModelCatalog.tiny`).
/// 2. Model dimuat HANYA SEKALI saat `initialize()`, dan TIDAK diload ulang pada setiap attempt.
/// 3. Menggunakan `initialPrompt` dengan target kata (jika disediakan dalam `expectedVocabulary`)
///    untuk memandu pengenalan utterance pendek / kata tunggal bahasa Indonesia.
/// 4. Prioritas mode rendah latensi (`WhisperPerformanceMode.responsive`, `threads: 4`, greedy search).
/// 5. Penanganan izin mikrofon aman melalui [WhisperRecorder.requestPermission()].
/// 6. Menggunakan Silero VAD bawaan untuk segmentasi suara anak secara efisien.
/// 7. Pembersihan sumber daya secara bersih pada `dispose()`.
class WhisperSpeechRecognitionProvider implements SpeechRecognitionProvider {
  WhisperSpeechRecognitionProvider._();

  static final WhisperSpeechRecognitionProvider instance =
      WhisperSpeechRecognitionProvider._();

  WhisperModelManager? _modelManager;
  WhisperEngine? _engine;
  WhisperRecorder? _recorder;
  WhisperVad? _vad;

  StreamSubscription<RecordingChunk>? _recordingSubscription;

  final List<double> _samples = [];
  final List<double> _vadBuffer = [];

  bool _initialized = false;
  bool _isListening = false;
  DateTime? _listeningStartedAt;

  // Latency metrics tracking
  Duration _lastStartLatency = Duration.zero;
  Duration _lastInferenceLatency = Duration.zero;
  Duration _lastTotalResponseTime = Duration.zero;

  Duration get lastStartLatency => _lastStartLatency;
  Duration get lastInferenceLatency => _lastInferenceLatency;
  Duration get lastTotalResponseTime => _lastTotalResponseTime;

  void Function(SpeechRecognitionResultModel result)? _onResult;
  void Function(SpeechRecognitionErrorModel error)? _onError;
  List<String>? _currentExpectedVocabulary;

  @override
  String get providerName => 'whisper_tiny';

  @override
  bool get isInitialized => _initialized && _engine != null;

  @override
  bool get isListening => _isListening;

  @override
  Future<bool> initialize({
    String? locale,
    void Function(String status)? onStatus,
    void Function(SpeechRecognitionErrorModel error)? onError,
  }) async {
    _onError = onError;

    // Jika sudah diinisialisasi dan model sudah aktif di memori, jangan load ulang (Load hanya sekali)
    if (_initialized && _engine != null) {
      onStatus?.call('ready');
      return true;
    }

    try {
      onStatus?.call('loading_model');
      _modelManager ??= WhisperModelManager();

      // 1. Dapatkan model Whisper Tiny Multilingual
      final whisperDescriptor = WhisperModelCatalog.tiny;
      var whisperModel = await _modelManager!.findCatalogModel(whisperDescriptor);

      if (whisperModel == null) {
        onStatus?.call('downloading_model');
        await for (final progress in _modelManager!.downloadCatalogModel(whisperDescriptor)) {
          final fraction = progress.fraction;
          if (fraction != null) {
            onStatus?.call('downloading_model: ${(fraction * 100).toInt()}%');
          }
        }
        whisperModel = await _modelManager!.findCatalogModel(whisperDescriptor);
      }

      if (whisperModel == null) {
        final err = SpeechRecognitionErrorModel(
          code: SpeechRecognitionErrorCode.internalError,
          message: 'Model Whisper Tiny gagal diunduh atau dipasang.',
          provider: providerName,
        );
        _onError?.call(err);
        return false;
      }

      // 2. Load Whisper Engine ke memori (hanya sekali)
      _engine?.dispose();
      _engine = await WhisperEngine.load(
        whisperModel.path,
        config: const WhisperConfig(
          useGpu: false, // Aman di berbagai chipset Android tanpa resiko crash GLES
          useFlashAttention: true,
          useDtw: false,
        ),
      );

      // 3. Siapkan Silero VAD untuk isolasi suara pendek
      final vadDescriptor = WhisperModelCatalog.sileroVad;
      var vadModel = await _modelManager!.findCatalogModel(vadDescriptor);

      if (vadModel == null) {
        await for (final _ in _modelManager!.downloadCatalogModel(vadDescriptor)) {}
        vadModel = await _modelManager!.findCatalogModel(vadDescriptor);
      }

      if (vadModel != null) {
        _vad?.dispose();
        _vad = WhisperVad.load(
          vadModel.path,
          useGpu: false,
          threads: 2,
        );
      }

      _initialized = true;
      onStatus?.call('ready');
      return true;
    } catch (e, st) {
      final err = SpeechRecognitionErrorModel(
        code: SpeechRecognitionErrorCode.internalError,
        message: 'Gagal menginisialisasi Whisper: $e',
        provider: providerName,
        originalError: e,
      );
      _onError?.call(err);
      debugPrint('[WhisperSpeechRecognitionProvider] Inisialisasi error: $e\n$st');
      return false;
    }
  }

  @override
  Future<void> startListening({
    required void Function(SpeechRecognitionResultModel result) onResult,
    Duration? timeout,
    List<String>? expectedVocabulary,
  }) async {
    if (!isInitialized) {
      final err = SpeechRecognitionErrorModel(
        code: SpeechRecognitionErrorCode.notInitialized,
        message: 'Whisper engine belum diinisialisasi.',
        provider: providerName,
      );
      _onError?.call(err);
      throw err;
    }

    if (_isListening) {
      await stopListening();
    }

    _onResult = onResult;
    _currentExpectedVocabulary = expectedVocabulary;

    final recorder = _recorder ??= WhisperRecorder();

    // 1. Permission check
    try {
      final permissionGranted = await recorder.requestPermission();
      if (!permissionGranted) {
        final err = SpeechRecognitionErrorModel(
          code: SpeechRecognitionErrorCode.permissionDenied,
          message: 'Izin mikrofon tidak diberikan oleh pengguna.',
          provider: providerName,
        );
        _onError?.call(err);
        throw err;
      }
    } catch (e) {
      if (e is SpeechRecognitionErrorModel) rethrow;
      final err = SpeechRecognitionErrorModel(
        code: SpeechRecognitionErrorCode.permissionDenied,
        message: 'Gagal meminta izin mikrofon: $e',
        provider: providerName,
        originalError: e,
      );
      _onError?.call(err);
      throw err;
    }

    // 2. Reset buffer rekaman
    _samples.clear();
    _vadBuffer.clear();
    _vad?.reset();
    _listeningStartedAt = DateTime.now();
    // 3. Mulai perekaman audio PCM 16kHz
    try {
      final startCallTime = DateTime.now();
      final stream = await recorder.start(
        sampleRate: 16000,
        chunkMilliseconds: 100,
      );
      _lastStartLatency = DateTime.now().difference(startCallTime);
      _isListening = true;

      await _recordingSubscription?.cancel();
      _recordingSubscription = stream.listen(
        _handleRecordingChunk,
        onError: (Object error, StackTrace stackTrace) {
          final err = SpeechRecognitionErrorModel(
            code: SpeechRecognitionErrorCode.audioRecordingError,
            message: 'Error saat merekam audio: $error',
            provider: providerName,
            originalError: error,
          );
          _onError?.call(err);
          _isListening = false;
        },
        cancelOnError: false,
      );
    } catch (e) {
      _isListening = false;
      final err = SpeechRecognitionErrorModel(
        code: SpeechRecognitionErrorCode.audioRecordingError,
        message: 'Tidak dapat memulai rekaman mikrofon: $e',
        provider: providerName,
        originalError: e,
      );
      _onError?.call(err);
      throw err;
    }
  }

  void _handleRecordingChunk(RecordingChunk chunk) {
    if (!_isListening) return;
    _samples.addAll(chunk.samples);
    _vadBuffer.addAll(chunk.samples);
  }

  @override
  Future<void> stopListening() async {
    if (!_isListening && _samples.isEmpty) {
      return;
    }

    final listeningStart = _listeningStartedAt ?? DateTime.now();

    // Hentikan perekaman mikrofon
    try {
      if (_recorder != null && _isListening) {
        await _recorder!.stop();
      }
    } catch (e) {
      debugPrint('[WhisperSpeechRecognitionProvider] Stop recorder warning: $e');
    } finally {
      _isListening = false;
      await _recordingSubscription?.cancel();
      _recordingSubscription = null;
    }

    if (_samples.isEmpty) {
      final result = SpeechRecognitionResultModel(
        recognizedText: '',
        confidence: 0.0,
        duration: Duration.zero,
        provider: providerName,
        locale: 'id_ID',
        isFinal: true,
      );
      _onResult?.call(result);
      return;
    }

    // 1. Ekstraksi dan amplifikasi sinyal suara anak (Software Automatic Gain)
    // Suara anak usia dini cenderung lembut (low amplitude).
    // Melakukan peak scanning dan gain boost terukur agar Whisper dapat menangkap tanpa anak harus berteriak.
    final rawSamples = Float32List.fromList(_samples);

    double maxAmp = 0.0;
    for (int i = 0; i < rawSamples.length; i++) {
      final abs = rawSamples[i].abs();
      if (abs > maxAmp) maxAmp = abs;
    }

    // Jika suara terdeteksi namun levelnya lembut (< 0.5), lakukan gain normalisasi terukur (max gain 3.0x)
    Float32List amplifiedSamples = rawSamples;
    if (maxAmp > 0.01 && maxAmp < 0.5) {
      final gain = (0.5 / maxAmp).clamp(1.0, 3.0);
      amplifiedSamples = Float32List(rawSamples.length);
      for (int i = 0; i < rawSamples.length; i++) {
        amplifiedSamples[i] = (rawSamples[i] * gain).clamp(-1.0, 1.0);
      }
    }

    Float32List speechSamples = amplifiedSamples;

    // 2. Gunakan VAD dengan threshold yang disesuaikan untuk suara anak lembut (threshold 0.25 bukan 0.35)
    // Threshold lebih rendah memastikan bisikan / suku kata halus tidak terpotong sebagai silence.
    final vad = _vad;
    if (vad != null) {
      vad.reset();
      final segments = vad.segments(
        amplifiedSamples,
        threshold: 0.25, // Disesuaikan untuk suara anak yang lembut
        minSpeechMs: 120, // Tangkap suku kata singkat (misal: "ba", "a")
        minSilenceMs: 180, // Endpointing yang stabil
        maxSpeechSeconds: 3,
        speechPadMs: 150, // Padding lebih lebar agar konsonan awal/akhir tidak terpotong
        samplesOverlap: 0.1,
      );

      if (segments.isNotEmpty) {
        final startSample = (segments.first.start.inMilliseconds * 16).clamp(0, amplifiedSamples.length);
        final endSample = (segments.last.end.inMilliseconds * 16).clamp(0, amplifiedSamples.length);
        if (endSample > startSample) {
          speechSamples = Float32List.fromList(amplifiedSamples.sublist(startSample, endSample));
        }
      }
    }

    // Utterance anak dibatasi maksimal 3 detik untuk latensi rendah
    const maxSpeechSamples = 16000 * 3;
    if (speechSamples.length > maxSpeechSamples) {
      speechSamples = Float32List.fromList(speechSamples.sublist(0, maxSpeechSamples));
    }

    // 3. Siapkan Prompt jika target word tersedia dalam expectedVocabulary
    String? initialPrompt;
    if (_currentExpectedVocabulary != null && _currentExpectedVocabulary!.isNotEmpty) {
      final targets = _currentExpectedVocabulary!.join(' ');
      initialPrompt = 'Kata bahasa Indonesia: $targets';
    }

    // 4. Jalankan Transkripsi Whisper Tiny (Responsif / Rendah Latensi)
    try {
      final engine = _engine;
      if (engine == null) {
        throw StateError('Whisper engine tidak tersedia saat inferensi.');
      }

      final inferenceStart = DateTime.now();

      final options = TranscribeOptions(
        language: 'id',
        translate: false,
        detectLanguage: false,
        noContext: true,
        suppressBlank: true,
        suppressNonSpeechTokens: true,
        tokenTimestamps: false,
        noTimestamps: true,
        singleSegment: true,
        threads: 4,
        initialPrompt: initialPrompt,
      ).withPerformanceMode(
        WhisperPerformanceMode.responsive,
      );

      final task = engine.transcribe(speechSamples, options: options);
      final transcriptionResult = await task.result;

      final now = DateTime.now();
      _lastInferenceLatency = now.difference(inferenceStart);
      _lastTotalResponseTime = now.difference(listeningStart);

      // Bersihkan teks hasil transkripsi
      final recognized = transcriptionResult.text.trim();

      final result = SpeechRecognitionResultModel(
        recognizedText: recognized,
        confidence: recognized.isNotEmpty ? 1.0 : 0.0,
        duration: _lastTotalResponseTime,
        provider: providerName,
        locale: 'id_ID',
        isFinal: true,
      );

      _onResult?.call(result);
    } catch (e) {
      final err = SpeechRecognitionErrorModel(
        code: SpeechRecognitionErrorCode.internalError,
        message: 'Kesalahan saat transkripsi Whisper: $e',
        provider: providerName,
        originalError: e,
      );
      _onError?.call(err);
    } finally {
      _samples.clear();
      _vadBuffer.clear();
    }
  }

  @override
  Future<void> cancelListening() async {
    try {
      if (_recorder != null && _isListening) {
        await _recorder!.stop();
      }
    } catch (_) {}

    _isListening = false;
    await _recordingSubscription?.cancel();
    _recordingSubscription = null;
    _samples.clear();
    _vadBuffer.clear();
    _vad?.reset();
    _onResult = null;
  }

  @override
  Future<void> dispose() async {
    await cancelListening();

    _engine?.dispose();
    _engine = null;

    _vad?.dispose();
    _vad = null;

    _recorder = null;
    _modelManager?.close();
    _modelManager = null;

    _initialized = false;
    _onError = null;
    _onResult = null;
  }
}
