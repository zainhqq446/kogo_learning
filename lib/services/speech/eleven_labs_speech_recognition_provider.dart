import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/constants/backend_config.dart';
import 'speech_recognition_error_model.dart';
import 'speech_recognition_provider.dart';
import 'speech_recognition_result_model.dart';


/// Implementasi [SpeechRecognitionProvider] menggunakan ElevenLabs STT (Scribe)
/// yang diarahkan melalui backend proxy aman tanpa mengekspos API key di client.
class ElevenLabsSpeechRecognitionProvider implements SpeechRecognitionProvider {
  ElevenLabsSpeechRecognitionProvider({
    AudioRecorder? audioRecorder,
    HttpClient? httpClient,
    String? backendBaseUrl,
  })  : _audioRecorder = audioRecorder ?? AudioRecorder(),
        _httpClient = httpClient ?? HttpClient(),
        _backendBaseUrl = backendBaseUrl ?? BackendConfig.apiBaseUrl;


  static final ElevenLabsSpeechRecognitionProvider instance =
      ElevenLabsSpeechRecognitionProvider();

  final AudioRecorder _audioRecorder;
  final HttpClient _httpClient;
  String _backendBaseUrl;

  bool _initialized = false;
  bool _isListening = false;
  DateTime? _listeningStartedAt;
  String? _currentRecordingPath;

  void Function(SpeechRecognitionErrorModel error)? _onError;
  void Function(SpeechRecognitionResultModel result)? _activeResultCallback;

  @override
  String get providerName => 'elevenlabs_backend_proxy';

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isListening => _isListening;

  void updateBackendBaseUrl(String url) {
    _backendBaseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  @override
  Future<bool> initialize({
    String? locale,
    void Function(String status)? onStatus,
    void Function(SpeechRecognitionErrorModel error)? onError,
  }) async {
    _onError = onError;
    try {
      onStatus?.call('checking_permissions');
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        final err = SpeechRecognitionErrorModel(
          code: SpeechRecognitionErrorCode.permissionDenied,
          message: 'Izin akses mikrofon ditolak',
          provider: providerName,
        );
        _onError?.call(err);
        return false;
      }

      _initialized = true;
      onStatus?.call('ready');
      return true;
    } catch (e) {
      final err = SpeechRecognitionErrorModel(
        code: SpeechRecognitionErrorCode.notAvailable,
        message: 'Gagal menginisialisasi perekam: $e',
        provider: providerName,
      );
      _onError?.call(err);
      return false;
    }
  }

  @override
  Future<void> startListening({
    required void Function(SpeechRecognitionResultModel result) onResult,
    Duration? timeout,
    List<String>? expectedVocabulary,
  }) async {
    if (!_initialized) {
      final ready = await initialize();
      if (!ready) {
        throw SpeechRecognitionErrorModel(
          code: SpeechRecognitionErrorCode.notInitialized,
          message: 'Provider belum diinisialisasi',
          provider: providerName,
        );
      }
    }

    try {
      _activeResultCallback = onResult;
      _listeningStartedAt = DateTime.now();

      final tempDir = await getTemporaryDirectory();
      _currentRecordingPath =
          '${tempDir.path}/elevenlabs_stt_${DateTime.now().millisecondsSinceEpoch}.m4a';

      const recordConfig = RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
        numChannels: 1,
      );

      await _audioRecorder.start(
        recordConfig,
        path: _currentRecordingPath!,
      );

      _isListening = true;

      if (timeout != null && timeout > Duration.zero) {
        Timer(timeout, () {
          if (_isListening) {
            stopListening();
          }
        });
      }
    } catch (e) {
      _isListening = false;
      final err = SpeechRecognitionErrorModel(
        code: SpeechRecognitionErrorCode.audioRecordingError,
        message: 'Gagal memulai perekaman audio: $e',
        provider: providerName,
      );
      _onError?.call(err);
      throw err;
    }
  }

  @override
  Future<void> stopListening() async {
    if (!_isListening) return;
    _isListening = false;

    final duration = _listeningStartedAt != null
        ? DateTime.now().difference(_listeningStartedAt!)
        : Duration.zero;

    try {
      final path = await _audioRecorder.stop();
      final recordedPath = path ?? _currentRecordingPath;

      if (recordedPath == null || !File(recordedPath).existsSync()) {
        _activeResultCallback?.call(
          SpeechRecognitionResultModel(
            recognizedText: '',
            isFinal: true,
            provider: providerName,
            duration: duration,
          ),
        );
        return;
      }

      final fileBytes = await File(recordedPath).readAsBytes();

      // Kirim rekaman ke backend ElevenLabs STT proxy
      final transcription = await _sendToBackendStt(fileBytes);

      try {
        await File(recordedPath).delete();
      } catch (_) {}

      _activeResultCallback?.call(
        SpeechRecognitionResultModel(
          recognizedText: transcription,
          isFinal: true,
          confidence: transcription.isNotEmpty ? 0.95 : 0.0,
          provider: providerName,
          duration: duration,
        ),
      );
    } catch (e) {
      debugPrint('[ElevenLabsSTT] Error transcribing: $e');
      _activeResultCallback?.call(
        SpeechRecognitionResultModel(
          recognizedText: '',
          isFinal: true,
          provider: providerName,
          duration: duration,
        ),
      );
    }
  }

  Future<String> _sendToBackendStt(List<int> audioBytes) async {
    try {
      final uri = Uri.parse('$_backendBaseUrl/voice/stt?language_code=id');
      final request = await _httpClient.postUrl(uri).timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw TimeoutException('ElevenLabs STT timeout'),
      );

      request.headers.set(HttpHeaders.contentTypeHeader, 'audio/m4a');
      request.add(audioBytes);
      final response = await request.close();

      if (response.statusCode == 200) {
        final respBody = await response.transform(utf8.decoder).join();
        final json = jsonDecode(respBody) as Map<String, dynamic>;
        final data = json['data'] as Map<String, dynamic>?;
        final text = (data?['text'] as String?)?.trim() ?? '';
        return text;
      } else {
        debugPrint('[ElevenLabsSTT] Backend returned HTTP ${response.statusCode}');
        return '';
      }
    } catch (e) {
      debugPrint('[ElevenLabsSTT] Network request failed: $e');
      return '';
    }
  }

  @override
  Future<void> cancelListening() async {
    if (!_isListening) return;
    _isListening = false;
    try {
      await _audioRecorder.cancel();
      if (_currentRecordingPath != null) {
        final f = File(_currentRecordingPath!);
        if (f.existsSync()) await f.delete();
      }
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    await cancelListening();
    await _audioRecorder.dispose();
    _httpClient.close(force: true);
    _initialized = false;
  }
}
