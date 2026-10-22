import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/services/audio/eleven_labs_dialogue_session.dart';

void main() {
  group('ElevenLabsDialogueSession Protocol & Short-Utterance Tests', () {
    late HttpServer server;
    late int port;
    final List<Map<String, dynamic>> receivedMessages = [];
    WebSocket? serverSocket;

    setUp(() async {
      receivedMessages.clear();
      // Buka Mock WebSocket Server lokal
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;

      server.transform(WebSocketTransformer()).listen((WebSocket socket) {
        serverSocket = socket;
        socket.listen((message) {
          if (message is String) {
            try {
              final json = jsonDecode(message) as Map<String, dynamic>;
              receivedMessages.add(json);

              // Jika menerima turn inputs dengan flush: true
              if (json.containsKey('inputs')) {
                final base64FakeAudio = base64Encode(Uint8List.fromList([1, 2, 3, 4]));
                // Kirim audio chunk dan event resmi Text-to-Dialogue: is_final_audio_for_turn
                socket.add(jsonEncode({
                  'audio': base64FakeAudio,
                  'is_final_audio_for_turn': true,
                }));
              }
            } catch (_) {}
          }
        });
      });
    });

    tearDown(() async {
      await serverSocket?.close();
      await server.close(force: true);
    });

    test('1. Handshake & Voice Registration connects and sends voice_id', () async {
      final session = ElevenLabsDialogueSession(
        wsUrl: 'ws://127.0.0.1:$port',
        apiKey: 'test-api-key',
        voiceId: 'cgSgspJ2msm6clMCkdW9',
        modelId: 'eleven_v4_turbo',
      );

      final connected = await session.connect();
      expect(connected, isTrue);
      expect(session.isConnected, isTrue);

      // Tunggu hingga server menerima pesan inisialisasi handshake
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(receivedMessages.isNotEmpty, isTrue);
      expect(receivedMessages.first['voices'], contains('cgSgspJ2msm6clMCkdW9'));
      expect(receivedMessages.first['xi_api_key'], equals('test-api-key'));

      await session.dispose();
    });

    test('2. Critical Short-Utterance Test Suite (9 phrases) with flush: true', () async {
      final session = ElevenLabsDialogueSession(
        wsUrl: 'ws://127.0.0.1:$port',
        apiKey: 'test-api-key',
        voiceId: 'cgSgspJ2msm6clMCkdW9',
        modelId: 'eleven_v4_turbo',
      );

      await session.connect();

      final testPhrases = [
        'Wah!',
        'Benar!',
        'Wah, benar!',
        'Yuk lanjut!',
        'Hmm... hampir.',
        'Coba lagi, ya.',
        'Enggak apa-apa. Coba lagi, ya.',
        'Sekarang, coba ucapkan Sepatu!',
        'Yeay! Kamu berhasil!',
      ];

      for (final phrase in testPhrases) {
        final audio = await session.sendTurn(phrase);
        expect(audio, isNotNull, reason: 'Utterance "$phrase" harus menghasilkan audio');
        expect(audio!.isNotEmpty, isTrue);

        final lastTurn = receivedMessages.last;
        expect(lastTurn['flush'], isTrue, reason: 'Flush WAJIB true untuk turn: $phrase');
        final inputs = lastTurn['inputs'] as List;
        expect(inputs.isNotEmpty, isTrue);
        expect(inputs.first['new_turn'], isTrue);
        expect(inputs.first['voice_id'], equals('cgSgspJ2msm6clMCkdW9'));
      }

      await session.dispose();
    });

    test('3. Handles is_final_audio_for_turn completion correctly', () async {
      final session = ElevenLabsDialogueSession(
        wsUrl: 'ws://127.0.0.1:$port',
        apiKey: 'test-api-key',
        voiceId: 'cgSgspJ2msm6clMCkdW9',
        modelId: 'eleven_v4_turbo',
      );

      final audio = await session.sendTurn('Wah, benar!');
      expect(audio, isNotNull);
      expect(audio, equals(Uint8List.fromList([1, 2, 3, 4])));

      await session.dispose();
    });

    test('4. Sanitizes API key by stripping control characters like \\u0016', () async {
      final session = ElevenLabsDialogueSession(
        wsUrl: 'ws://127.0.0.1:$port',
        apiKey: '\u0016clean-key\r\n',
        voiceId: 'cgSgspJ2msm6clMCkdW9',
        modelId: 'eleven_v4_turbo',
      );

      final connected = await session.connect();
      expect(connected, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(receivedMessages.last['xi_api_key'], equals('clean-key'));

      await session.dispose();
    });
  });
}
