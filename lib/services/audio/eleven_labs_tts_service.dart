import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../core/constants/backend_config.dart';

/// Konfigurasi parameter sintesis vokal ElevenLabs yang disesuaikan
/// untuk persona teman belajar anak (Kogo) dalam Bahasa Indonesia.
class ElevenLabsVoiceSettings {
  final double stability;
  final double similarityBoost;
  final double style;
  final double speed;
  final bool useSpeakerBoost;

  const ElevenLabsVoiceSettings({
    this.stability = 0.40,
    this.similarityBoost = 0.80,
    this.style = 0.45,
    this.speed = 0.98,
    this.useSpeakerBoost = true,
  });

  Map<String, dynamic> toJson() => {
        'stability': stability,
        'similarity_boost': similarityBoost,
        'style': style,
        'speed': speed,
        'use_speaker_boost': useSpeakerBoost,
      };

  @override
  String toString() =>
      'stability=$stability similarity=$similarityBoost style=$style speed=$speed speaker_boost=$useSpeakerBoost';
}

/// Service client resmi untuk ElevenLabs Text-to-Speech API.
/// Mendukung model low-latency conversational `eleven_flash_v2_5` dan `eleven_multilingual_v2`
/// dengan dukungan aksen dan pelafalan Bahasa Indonesia natural.
class ElevenLabsTtsService {
  final HttpClient _httpClient;
  final String _baseUrl;
  final String _apiKey;
  final String _voiceId;
  final String _modelId;
  final ElevenLabsVoiceSettings _settings;

  // In-memory cache Uint8List untuk meminimalkan latensi dan konsumsi kuota
  final Map<String, Uint8List> _audioCache = {};

  ElevenLabsTtsService({
    HttpClient? httpClient,
    String? baseUrl,
    String? apiKey,
    String? voiceId,
    String? modelId,
    ElevenLabsVoiceSettings? settings,
  })  : _httpClient = httpClient ?? HttpClient(),
        _baseUrl = baseUrl ??
            (const String.fromEnvironment('ELEVENLABS_BASE_URL', defaultValue: '').isNotEmpty
                ? const String.fromEnvironment('ELEVENLABS_BASE_URL')
                : BackendConfig.apiBaseUrl),

        _apiKey = _cleanHeaderValue(
            const String.fromEnvironment('ELEVENLABS_API_KEY', defaultValue: '').isNotEmpty
                ? const String.fromEnvironment('ELEVENLABS_API_KEY')
                : (apiKey ?? '')),
        _voiceId = const String.fromEnvironment('ELEVENLABS_VOICE_ID', defaultValue: '').isNotEmpty
            ? const String.fromEnvironment('ELEVENLABS_VOICE_ID')
            : (voiceId ?? 'cgSgspJ2msm6clMCkdW9'), // Friendly, youthful voice suitable for children
        _modelId = const String.fromEnvironment('ELEVENLABS_MODEL_ID', defaultValue: '').isNotEmpty
            ? const String.fromEnvironment('ELEVENLABS_MODEL_ID')
            : (modelId ?? 'eleven_flash_v2_5'),
        _settings = settings ?? const ElevenLabsVoiceSettings();

  static String _cleanHeaderValue(String val) {
    return val.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
  }

  String get voiceId => _voiceId;
  String get modelId => _modelId;
  String get baseUrl => _baseUrl;
  ElevenLabsVoiceSettings get settings => _settings;
  bool get hasApiKey => _apiKey.isNotEmpty;

  /// Mensintesis teks menjadi audio MP3 bytes via ElevenLabs Text-to-Speech endpoint.
  Future<Uint8List?> synthesizeSpeech(
    String text, {
    ElevenLabsVoiceSettings? customSettings,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return null;

    final effectiveSettings = customSettings ?? _settings;
    final cacheKey = '$cleanText:$_voiceId:$_modelId:${effectiveSettings.stability}:${effectiveSettings.style}:${effectiveSettings.speed}';

    final stopwatch = Stopwatch()..start();

    if (_audioCache.containsKey(cacheKey)) {
      stopwatch.stop();
      _logDevelopment(
        response: cleanText,
        latencyMs: stopwatch.elapsedMilliseconds,
        isCacheHit: true,
        settings: effectiveSettings,
      );
      return _audioCache[cacheKey];
    }

    // Jika API key tidak dikonfigurasi pada endpoint resmi, hindari HTTP 401
    final isDirectElevenLabs = _baseUrl.contains('api.elevenlabs.io');
    if (isDirectElevenLabs && _apiKey.isEmpty) {
      if (kDebugMode) {
        debugPrint('[ElevenLabsTtsService] ELEVENLABS_API_KEY is not configured.');
      }
      return null;
    }

    try {
      final isBackendProxy = _baseUrl.contains('/api');
      final uri = isBackendProxy
          ? Uri.parse('$_baseUrl/voice/tts')
          : Uri.parse('$_baseUrl/text-to-speech/$_voiceId?output_format=mp3_44100_128');

      final request = await _httpClient.postUrl(uri).timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw SocketException('Voice provider connection timeout'),
      );

      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'audio/mpeg');
      if (_apiKey.isNotEmpty) {
        request.headers.set('xi-api-key', _apiKey);
      }

      final payload = isBackendProxy
          ? <String, dynamic>{
              'text': cleanText,
              'voiceId': _voiceId,
              'modelId': _modelId,
              'settings': {
                'stability': effectiveSettings.stability,
                'similarityBoost': effectiveSettings.similarityBoost,
                'style': effectiveSettings.style,
                'speed': effectiveSettings.speed,
                'useSpeakerBoost': effectiveSettings.useSpeakerBoost,
              },
            }
          : <String, dynamic>{
              'text': cleanText,
              'model_id': _modelId,
              'voice_settings': effectiveSettings.toJson(),
            };

      final bodyBytes = utf8.encode(jsonEncode(payload));
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response = await request.close().timeout(
        const Duration(seconds: 6),
        onTimeout: () => throw SocketException('ElevenLabs response timeout'),
      );

      stopwatch.stop();

      if (response.statusCode == HttpStatus.ok) {
        final bytesBuilder = BytesBuilder(copy: false);
        await for (final chunk in response) {
          bytesBuilder.add(chunk);
        }
        final audioBytes = bytesBuilder.toBytes();
        if (audioBytes.isNotEmpty) {
          _audioCache[cacheKey] = audioBytes;
          _logDevelopment(
            response: cleanText,
            latencyMs: stopwatch.elapsedMilliseconds,
            isCacheHit: false,
            settings: effectiveSettings,
          );
          return audioBytes;
        }
      } else {
        if (kDebugMode) {
          debugPrint('[ElevenLabsTtsService] HTTP Error: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ElevenLabsTtsService] synthesizeSpeech error: $e');
      }
    }

    return null;
  }

  void _logDevelopment({
    required String response,
    required int latencyMs,
    required bool isCacheHit,
    required ElevenLabsVoiceSettings settings,
  }) {
    if (!kDebugMode) return;
    debugPrint(
      '[KOGO VOICE]\n'
      'model=$_modelId\n'
      'voice=$_voiceId\n'
      'stability=${settings.stability}\n'
      'similarity=${settings.similarityBoost}\n'
      'style=${settings.style}\n'
      'speed=${settings.speed}\n'
      'response="$response"\n'
      'latency=${latencyMs}ms\n'
      'cache_hit=$isCacheHit',
    );
  }

  void clearCache() {
    _audioCache.clear();
  }

  void dispose() {
    _httpClient.close(force: true);
    _audioCache.clear();
  }
}
