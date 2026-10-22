import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/services/audio/eleven_labs_tts_service.dart';

void main() {
  group('ElevenLabsTtsService Tests', () {
    test('1. Returns null when API key is empty on direct ElevenLabs endpoint', () async {
      final service = ElevenLabsTtsService(
        baseUrl: 'https://api.elevenlabs.io/v1',
        apiKey: '',
        voiceId: 'test-voice',
        modelId: 'eleven_flash_v2_5',
      );

      final result = await service.synthesizeSpeech('Halo anak pintar!');
      expect(result, isNull);
    });

    test('2. Caches audio bytes and validates child-friendly conversational parameters', () async {
      final mockData = Uint8List.fromList([10, 20, 30, 40, 50]);

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      int requestCount = 0;

      server.listen((HttpRequest request) async {
        requestCount++;
        expect(request.method, equals('POST'));
        expect(request.uri.path, equals('/text-to-speech/kogo-child-voice'));
        expect(request.uri.queryParameters['output_format'], equals('mp3_44100_128'));
        expect(request.headers.value('xi-api-key'), equals('test-eleven-key'));

        final body = await utf8.decodeStream(request);
        final json = jsonDecode(body) as Map<String, dynamic>;
        expect(json['model_id'], equals('eleven_flash_v2_5'));
        expect(json['text'], equals('Ayo semangat belajar!'));

        final settings = json['voice_settings'] as Map<String, dynamic>;
        expect(settings['stability'], equals(0.40));
        expect(settings['similarity_boost'], equals(0.80));
        expect(settings['style'], equals(0.45));
        expect(settings['speed'], equals(0.98));
        expect(settings['use_speaker_boost'], equals(true));

        request.response.statusCode = HttpStatus.ok;
        request.response.add(mockData);
        await request.response.close();
      });

      final service = ElevenLabsTtsService(
        baseUrl: 'http://${server.address.address}:${server.port}',
        apiKey: 'test-eleven-key',
        voiceId: 'kogo-child-voice',
        modelId: 'eleven_flash_v2_5',
        settings: const ElevenLabsVoiceSettings(
          stability: 0.40,
          similarityBoost: 0.80,
          style: 0.45,
          speed: 0.98,
          useSpeakerBoost: true,
        ),
      );

      // Request 1: hits mock server
      final bytes1 = await service.synthesizeSpeech('Ayo semangat belajar!');
      expect(bytes1, isNotNull);
      expect(bytes1, equals(mockData));
      expect(requestCount, equals(1));

      // Request 2: hits cache
      final bytes2 = await service.synthesizeSpeech('Ayo semangat belajar!');
      expect(bytes2, isNotNull);
      expect(bytes2, equals(mockData));
      expect(requestCount, equals(1));

      await server.close();
      service.dispose();
    });

    test('3. Returns null gracefully on HTTP error status', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      server.listen((HttpRequest request) async {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
      });

      final service = ElevenLabsTtsService(
        baseUrl: 'http://${server.address.address}:${server.port}',
        apiKey: 'test-eleven-key',
        voiceId: 'kogo-child-voice',
      );

      final result = await service.synthesizeSpeech('Coba lagi');
      expect(result, isNull);

      await server.close();
      service.dispose();
    });

    test('4. Seamlessly routes to backend proxy /voice/tts when baseUrl contains /api without API key', () async {
      final mockData = Uint8List.fromList([99, 88, 77]);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      int proxyRequestCount = 0;

      server.listen((HttpRequest request) async {
        proxyRequestCount++;
        expect(request.method, equals('POST'));
        expect(request.uri.path, equals('/api/voice/tts'));
        expect(request.headers.value('xi-api-key'), isNull);

        final body = await utf8.decodeStream(request);
        final json = jsonDecode(body) as Map<String, dynamic>;
        expect(json['text'], equals('Bagus sekali!'));
        expect(json['voiceId'], equals('cgSgspJ2msm6clMCkdW9'));
        expect(json['modelId'], equals('eleven_flash_v2_5'));
        expect(json['settings'], isNotNull);

        request.response.statusCode = HttpStatus.ok;
        request.response.add(mockData);
        await request.response.close();
      });

      final service = ElevenLabsTtsService(
        baseUrl: 'http://${server.address.address}:${server.port}/api',
        // Tidak perlu apiKey di Flutter karena disembunyikan di backend
        apiKey: '',
      );

      final bytes = await service.synthesizeSpeech('Bagus sekali!');
      expect(bytes, isNotNull);
      expect(bytes, equals(mockData));
      expect(proxyRequestCount, equals(1));

      await server.close();
      service.dispose();
    });
  });
}

