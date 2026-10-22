import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/services/audio/eleven_labs_dialogue_session.dart';
import 'package:kogo_voice_learning/services/audio/eleven_labs_tts_service.dart';
import 'package:kogo_voice_learning/services/audio/eleven_labs_voice_provider.dart';
import 'package:kogo_voice_learning/services/audio/speech_output_provider.dart';
import 'package:kogo_voice_learning/services/audio/voice_interaction_controller.dart';

class FakeElevenLabsTtsService extends ElevenLabsTtsService {
  final List<String> synthesizedTexts = [];
  final Uint8List fakeBytes;

  FakeElevenLabsTtsService({required this.fakeBytes, super.apiKey = 'fake-key'});

  @override
  bool get hasApiKey => true;

  @override
  Future<Uint8List?> synthesizeSpeech(
    String text, {
    ElevenLabsVoiceSettings? customSettings,
  }) async {
    synthesizedTexts.add(text);
    return fakeBytes;
  }
}

class FakeAudioPlayer extends AudioPlayer {
  final _completeController = StreamController<void>.broadcast();
  final _stateController = StreamController<PlayerState>.broadcast();
  final List<Source> playedSources = [];

  @override
  Stream<void> get onPlayerComplete => _completeController.stream;

  @override
  Stream<PlayerState> get onPlayerStateChanged => _stateController.stream;

  @override
  Future<void> play(Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    playedSources.add(source);
    _stateController.add(PlayerState.playing);
    // Langsung trigger selesai untuk kebutuhan test
    Future.microtask(() {
      _stateController.add(PlayerState.completed);
      _completeController.add(null);
    });
  }

  @override
  Future<void> stop() async {
    if (!_stateController.isClosed) {
      _stateController.add(PlayerState.stopped);
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await super.dispose();
    } catch (_) {}
    if (!_completeController.isClosed) {
      await _completeController.close();
    }
    if (!_stateController.isClosed) {
      await _stateController.close();
    }
  }
}

class FakeElevenLabsDialogueSession extends ElevenLabsDialogueSession {
  final List<String> sentTurns = [];
  final Uint8List? fakeAudio;
  final bool mockHasApiKey;

  FakeElevenLabsDialogueSession({
    this.fakeAudio,
    this.mockHasApiKey = true,
  }) : super(apiKey: 'fake-ws-key');

  @override
  bool get hasApiKey => mockHasApiKey;

  @override
  bool get isConnected => true;

  @override
  Future<Uint8List?> sendTurn(
    String dialogueText, {
    int? operationId,
    String? customVoiceId,
    String? customInstruction,
  }) async {
    sentTurns.add(dialogueText);
    return fakeAudio;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (MethodCall methodCall) async => 1,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (MethodCall methodCall) async => 1,
    );
  });

  group('ElevenLabsVoiceProvider & Pipeline Architecture Tests', () {
    test('1. ElevenLabsVoiceProvider implements SpeechOutputProvider contract', () {
      final provider = ElevenLabsVoiceProvider();
      expect(provider, isA<SpeechOutputProvider>());
    });

    test('2. VoiceInteractionController defaults to ElevenLabsVoiceProvider', () {
      final controller = VoiceInteractionController.instance;
      expect(controller.provider, isA<ElevenLabsVoiceProvider>());
    });

    test('3. Single conversational thought: playPhraseAndWord produces a single whole utterance with ElevenLabs', () async {
      final fakeBytes = Uint8List.fromList([1, 2, 3]);
      final fakeTts = FakeElevenLabsTtsService(fakeBytes: fakeBytes);
      final fakePlayer = FakeAudioPlayer();
      final provider = ElevenLabsVoiceProvider(
        audioPlayer: fakePlayer,
        elevenLabsTtsService: fakeTts,
      );

      // Harusnya memanggil 1 single dynamic request daripada memotong frasa + kata terpisah
      await provider.playPhraseAndWord(
        phraseAsset: 'assets/audio/prompts/prompt_now_try.mp3',
        word: 'kucing',
        wordAsset: 'assets/audio/words/kucing.mp3',
      );

      // Verifikasi bahwa seluruh pemikiran percakapan disintesis utuh
      expect(fakeTts.synthesizedTexts.length, equals(1));
      expect(fakeTts.synthesizedTexts.first, contains('kucing'));
      expect(fakeTts.synthesizedTexts.first, equals('Sekarang, coba ucapkan kucing!'));

      await provider.dispose();
    });

    test('4. WebSocket Persistent Dialogue Session: speakDynamicText uses sendTurn when dialogue session has API key', () async {
      final fakeBytes = Uint8List.fromList([4, 5, 6]);
      final fakeSession = FakeElevenLabsDialogueSession(fakeAudio: fakeBytes);
      final fakeTts = FakeElevenLabsTtsService(fakeBytes: fakeBytes);
      final fakePlayer = FakeAudioPlayer();
      final provider = ElevenLabsVoiceProvider(
        audioPlayer: fakePlayer,
        elevenLabsTtsService: fakeTts,
        dialogueSession: fakeSession,
      );

      await provider.speakDynamicText('[excited] Wah, hebat sekali!');

      // WebSocket sendTurn harus diprioritaskan
      expect(fakeSession.sentTurns.length, equals(1));
      expect(fakeSession.sentTurns.first, equals('[excited] Wah, hebat sekali!'));
      // HTTP TTS tidak boleh dipanggil jika WebSocket berhasil
      expect(fakeTts.synthesizedTexts, isEmpty);

      await provider.dispose();
    });

    test('5. No Silent Fallback: speakDynamicText stops and does NOT fall back to Flash HTTP TTS when v4 Turbo dialogue session returns null', () async {
      final fakeBytes = Uint8List.fromList([7, 8, 9]);
      final fakeSession = FakeElevenLabsDialogueSession(fakeAudio: null); // WebSocket gagal mengembalikan audio
      final fakeTts = FakeElevenLabsTtsService(fakeBytes: fakeBytes);
      final fakePlayer = FakeAudioPlayer();
      final provider = ElevenLabsVoiceProvider(
        audioPlayer: fakePlayer,
        elevenLabsTtsService: fakeTts,
        dialogueSession: fakeSession,
      );

      await provider.speakDynamicText('Coba lagi, ya!');

      expect(fakeSession.sentTurns.length, equals(1));
      // Sesuai requirement: TIDAK BOLEH fallback diam-diam ke Flash
      expect(fakeTts.synthesizedTexts, isEmpty);
      expect(fakePlayer.playedSources, isEmpty);

      await provider.dispose();
    });

    test('6. Concurrency Control: stop with outdated operationId does NOT cancel current operation', () async {
      final controller = VoiceInteractionController.instance;
      final currentOp = controller.currentOperationId;

      // Stop dengan stale operationId (currentOp - 1)
      await controller.stop(currentOp - 1);
      // OperationId tidak boleh berubah karena request kadaluwarsa diabaikan
      expect(controller.currentOperationId, equals(currentOp));

      // Stop dengan matching operationId harus dieksekusi
      await controller.stop(currentOp);
      expect(controller.currentOperationId, equals(currentOp + 1));
    });
  });
}
