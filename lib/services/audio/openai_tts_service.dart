import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Service client untuk Text-to-Speech berkualitas tinggi OpenAI (gpt-4o-mini-tts).
/// Menggunakan backend proxy atau endpoint langsung dengan konfigurasi runtime aman
/// tanpa hardcoded secret key di codebase.
class OpenAiTtsService {
  final HttpClient _httpClient;
  final String _baseUrl;
  final String _voice;
  final String _model;
  final String _instructions;
  final String? _apiKey;

  // In-memory audio byte cache untuk menghemat bandwidth & latensi (kata berulang)
  final Map<String, Uint8List> _audioCache = {};

  OpenAiTtsService({
    HttpClient? httpClient,
    String? baseUrl,
    String voice = 'marin',
    String model = 'gpt-4o-mini-tts',
    String? instructions,
    String? apiKey,
  })  : _httpClient = httpClient ?? HttpClient(),
        _baseUrl = baseUrl ??
            const String.fromEnvironment(
              'OPENAI_TTS_BASE_URL',
              defaultValue: 'https://api.openai.com/v1',
            ),
        _voice = const String.fromEnvironment('OPENAI_TTS_VOICE', defaultValue: '').isNotEmpty
            ? const String.fromEnvironment('OPENAI_TTS_VOICE')
            : voice,
        _model = const String.fromEnvironment('OPENAI_TTS_MODEL', defaultValue: '').isNotEmpty
            ? const String.fromEnvironment('OPENAI_TTS_MODEL')
            : model,
        _instructions = instructions ??
            'Speak natural Indonesian to a young child around 5–6 years old. Sound like a warm, cheerful, playful learning companion speaking directly to the child, not like a text-to-speech system reading a script. Use natural conversational Indonesian pronunciation, varied intonation, subtle emotional expression, realistic pauses, gentle emphasis, and a relaxed speaking rhythm. React naturally to success and mistakes. Be genuinely excited when the child succeeds, gently encouraging when the child struggles, and calm when the child needs another attempt. Keep phrases short and easy for a young child to understand. Never sound like an announcer, GPS, audiobook narrator, customer-service agent, or robotic assistant.',
        _apiKey = const String.fromEnvironment('OPENAI_API_KEY', defaultValue: '').isNotEmpty
            ? const String.fromEnvironment('OPENAI_API_KEY')
            : apiKey;

  String get voice => _voice;
  String get model => _model;
  String get baseUrl => _baseUrl;
  String get instructions => _instructions;

  /// Mensintesis teks menjadi audio MP3 bytes via OpenAI TTS API atau Proxy.
  /// Menghasilkan null jika API key/proxy tidak dikonfigurasi atau jaringan gagal,
  /// sehingga provider dapat fallback secara aman dan graceful.
  Future<Uint8List?> synthesizeSpeech(String text, {String? customInstructions}) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return null;

    final effectiveInstructions = customInstructions ?? _instructions;
    final cacheKey = '$cleanText:$_voice:$_model:$effectiveInstructions';
    if (_audioCache.containsKey(cacheKey)) {
      return _audioCache[cacheKey];
    }

    // Jika tidak ada apiKey dan endpoint adalah default OpenAI langsung,
    // jangan lakukan request yang pasti 401 Unauthorized; kembalikan null untuk fallback
    final isDirectOpenAi = _baseUrl.contains('api.openai.com');
    if (isDirectOpenAi && (_apiKey == null || _apiKey.isEmpty)) {
      return null;
    }

    try {
      final uri = Uri.parse('$_baseUrl/audio/speech');
      final request = await _httpClient.postUrl(uri).timeout(
        const Duration(seconds: 4),
        onTimeout: () => throw SocketException('TTS connection timeout'),
      );

      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      if (_apiKey != null && _apiKey.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_apiKey');
      }

      // Payload OpenAI Audio Speech (steerable via instructions/prompt where supported)
      final payload = <String, dynamic>{
        'model': _model,
        'input': cleanText,
        'voice': _voice,
        'response_format': 'mp3',
        'speed': 0.95,
      };

      if (effectiveInstructions.isNotEmpty) {
        payload['instructions'] = effectiveInstructions;
      }

      final bodyBytes = utf8.encode(jsonEncode(payload));
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response = await request.close().timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw SocketException('TTS response timeout'),
      );

      if (response.statusCode == HttpStatus.ok) {
        final bytesBuilder = BytesBuilder(copy: false);
        await for (final chunk in response) {
          bytesBuilder.add(chunk);
        }
        final audioBytes = bytesBuilder.toBytes();
        if (audioBytes.isNotEmpty) {
          _audioCache[cacheKey] = audioBytes;
          return audioBytes;
        }
      } else {
        debugPrint('[OpenAiTtsService] Error ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[OpenAiTtsService] synthesizeSpeech error: $e');
    }

    return null;
  }

  void clearCache() {
    _audioCache.clear();
  }

  void dispose() {
    _httpClient.close(force: true);
    _audioCache.clear();
  }
}
