import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/services/audio/openai_tts_service.dart';

void main() {
  group('OpenAiTtsService Tests', () {
    test('1. Returns null when API key is empty on direct OpenAI endpoint', () async {
      final service = OpenAiTtsService(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: '',
        voice: 'marin',
        model: 'gpt-4o-mini-tts',
      );

      final result = await service.synthesizeSpeech('Halo anak pintar!');
      expect(result, isNull);
    });

    test('2. Caches audio bytes successfully and avoids duplicate network requests', () async {
      final mockData = Uint8List.fromList([1, 2, 3, 4, 5]);

      // Mock Http Server
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      int requestCount = 0;

      server.listen((HttpRequest request) async {
        requestCount++;
        expect(request.method, equals('POST'));
        expect(request.uri.path, equals('/audio/speech'));

        final body = await utf8.decodeStream(request);
        final json = jsonDecode(body) as Map<String, dynamic>;
        expect(json['model'], equals('gpt-4o-mini-tts'));
        expect(json['voice'], equals('marin'));
        expect(json['input'], equals('Kucing'));
        expect(json['speed'], equals(0.95));

        request.response.statusCode = HttpStatus.ok;
        request.response.add(mockData);
        await request.response.close();
      });

      final service = OpenAiTtsService(
        baseUrl: 'http://${server.address.address}:${server.port}',
        apiKey: 'test-api-key',
        voice: 'marin',
        model: 'gpt-4o-mini-tts',
      );

      // Request 1: hits server
      final bytes1 = await service.synthesizeSpeech('Kucing');
      expect(bytes1, isNotNull);
      expect(bytes1, equals(mockData));
      expect(requestCount, equals(1));

      // Request 2: hits cache
      final bytes2 = await service.synthesizeSpeech('Kucing');
      expect(bytes2, isNotNull);
      expect(bytes2, equals(mockData));
      expect(requestCount, equals(1)); // No new request made

      await server.close();
      service.dispose();
    });

    test('3. Fallback gracefully returns null on HTTP 500 error', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      server.listen((HttpRequest request) async {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      });

      final service = OpenAiTtsService(
        baseUrl: 'http://${server.address.address}:${server.port}',
        apiKey: 'test-api-key',
        voice: 'cedar',
      );

      final result = await service.synthesizeSpeech('Kata baru');
      expect(result, isNull);

      await server.close();
      service.dispose();
    });
  });
}
