import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'eleven_labs_tts_service.dart';

/// Status koneksi sesi WebSocket ElevenLabs Text-to-Dialogue
enum DialogueSessionState {
  disconnected,
  connecting,
  connected,
  streaming,
  error,
}

/// Sesi persistent WebSocket untuk ElevenLabs Text-to-Dialogue streaming API.
/// Menggunakan `wss://api.elevenlabs.io/v1/text-to-dialogue/stream-input`
/// dengan model interaktif (`eleven_v4_turbo` / `eleven_multilingual_v2`).
/// Mempertahankan koneksi terbuka untuk multi-turn conversation tanpa overhead reconnect setiap kata.
class ElevenLabsDialogueSession {
  final String _wsUrl;
  final String _apiKey;
  final String _voiceId;
  final String _modelId;
  final ElevenLabsVoiceSettings _settings;

  WebSocket? _webSocket;
  StreamSubscription? _socketSubscription;
  DialogueSessionState _state = DialogueSessionState.disconnected;

  // Controller untuk memancarkan potongan byte audio secara real-time
  final _audioChunkController = StreamController<Uint8List>.broadcast();

  // Completer untuk giliran dialog (turn) saat ini
  Completer<Uint8List?>? _currentTurnCompleter;
  BytesBuilder _currentTurnBuffer = BytesBuilder(copy: false);
  int _activeOperationId = 0;

  ElevenLabsDialogueSession({
    String? wsUrl,
    String? apiKey,
    String? voiceId,
    String? modelId,
    ElevenLabsVoiceSettings? settings,
  })  : _wsUrl = wsUrl ??
            const String.fromEnvironment(
              'ELEVENLABS_WS_URL',
              defaultValue: 'wss://api.elevenlabs.io/v1/text-to-dialogue/stream-input',
            ),
        _apiKey = _cleanHeaderValue(
            const String.fromEnvironment('ELEVENLABS_API_KEY', defaultValue: '').isNotEmpty
                ? const String.fromEnvironment('ELEVENLABS_API_KEY')
                : (apiKey ?? '')),
        _voiceId = const String.fromEnvironment('ELEVENLABS_VOICE_ID', defaultValue: '').isNotEmpty
            ? const String.fromEnvironment('ELEVENLABS_VOICE_ID')
            : (voiceId ?? 'cgSgspJ2msm6clMCkdW9'),
        _modelId = const String.fromEnvironment('ELEVENLABS_MODEL_ID', defaultValue: '').isNotEmpty
            ? const String.fromEnvironment('ELEVENLABS_MODEL_ID')
            : (modelId ?? 'eleven_v4_turbo'),
        _settings = settings ?? const ElevenLabsVoiceSettings();

  static String _cleanHeaderValue(String val) {
    return val.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
  }

  DialogueSessionState get state => _state;
  bool get isConnected => _state == DialogueSessionState.connected || _state == DialogueSessionState.streaming;
  bool get hasApiKey => _apiKey.isNotEmpty;
  Stream<Uint8List> get audioStream => _audioChunkController.stream;
  String get voiceId => _voiceId;
  String get modelId => _modelId;
  ElevenLabsVoiceSettings get settings => _settings;

  int? _lastConnectMs;
  int? _firstAudioMs;
  final Stopwatch _turnStopwatch = Stopwatch();
  Timer? _keepAliveTimer;

  /// Membuka koneksi WebSocket persistent dan mengirimkan initial registration handshake
  Future<bool> connect() async {
    if (isConnected) return true;
    if (_apiKey.isEmpty) {
      _logError(
        operationId: _activeOperationId,
        stage: 'connect',
        event: 'missing_api_key',
        error: 'ELEVENLABS_API_KEY is not configured',
      );
      _state = DialogueSessionState.disconnected;
      return false;
    }

    _state = DialogueSessionState.connecting;
    final connectStopwatch = Stopwatch()..start();

    try {
      final uri = Uri.parse('$_wsUrl?model_id=$_modelId&output_format=mp3_44100_128');
      
      final headers = <String, dynamic>{
        'xi-api-key': _apiKey,
      };

      _webSocket = await WebSocket.connect(
        uri.toString(),
        headers: headers,
      ).timeout(
        const Duration(seconds: 6),
        onTimeout: () => throw const SocketException('ElevenLabs dialogue WebSocket connection timeout'),
      );

      connectStopwatch.stop();
      _lastConnectMs = connectStopwatch.elapsedMilliseconds;
      _state = DialogueSessionState.connected;

      // Kirim initial message handshake untuk meregistrasikan voice
      final initMessage = jsonEncode({
        'voices': [_voiceId],
        'xi_api_key': _apiKey,
      });
      _webSocket?.add(initMessage);

      // Mulai mendengarkan response stream dari ElevenLabs
      _socketSubscription = _webSocket?.listen(
        _handleServerMessage,
        onError: _handleSocketError,
        onDone: _handleSocketDone,
        cancelOnError: false,
      );

      _startKeepAlive();
      return true;
    } catch (e) {
      connectStopwatch.stop();
      _lastConnectMs = null;
      _logError(
        operationId: _activeOperationId,
        stage: 'connect',
        event: 'handshake_failed',
        error: e.toString(),
      );
      _state = DialogueSessionState.error;
      await cancel();
      return false;
    }
  }

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    // Kirim keep_alive setiap 12 detik untuk mencegah server inactivity timeout (20 detik)
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (isConnected && _state != DialogueSessionState.streaming) {
        try {
          _webSocket?.add(jsonEncode({'keep_alive': true}));
        } catch (_) {}
      }
    });
  }

  /// Mengirim satu conversational turn (dialogue input) dan menunggu seluruh audio turn tersebut
  Future<Uint8List?> sendTurn(
    String dialogueText, {
    int? operationId,
    String? customVoiceId,
    String? customInstruction,
  }) async {
    var cleanText = dialogueText.trim();
    if (cleanText.isEmpty) return null;

    if (customInstruction != null && customInstruction.isNotEmpty && !cleanText.startsWith('[')) {
      final lower = customInstruction.toLowerCase();
      String tag = '';
      if (lower.contains('excitement') || lower.contains('celebrate') || lower.contains('energetic')) {
        tag = '[excited]';
      } else if (lower.contains('gentle') || lower.contains('reassuring') || lower.contains('patient')) {
        tag = '[gently]';
      } else if (lower.contains('curious') || lower.contains('optimistic')) {
        tag = '[curious]';
      } else if (lower.contains('cheerful') || lower.contains('playful') || lower.contains('proud')) {
        tag = '[cheerfully]';
      }
      if (tag.isNotEmpty) {
        cleanText = '$tag $cleanText';
      }
    }

    final currentOpId = operationId ?? ++_activeOperationId;
    _activeOperationId = currentOpId;

    if (!isConnected) {
      final success = await connect();
      if (!success) return null;
    }

    // Reset buffer untuk turn baru
    _currentTurnBuffer = BytesBuilder(copy: false);
    final completer = Completer<Uint8List?>();
    _currentTurnCompleter = completer;
    _firstAudioMs = null;
    _state = DialogueSessionState.streaming;

    _turnStopwatch.reset();
    _turnStopwatch.start();
    final sendStopwatch = Stopwatch()..start();
    int? sendMs;

    try {
      final effectiveVoiceId = customVoiceId ?? _voiceId;

      final turnPayload = {
        'inputs': [
          {
            'text': cleanText,
            'voice_id': effectiveVoiceId,
            'new_turn': true,
          }
        ],
        'flush': true,
      };

      _webSocket?.add(jsonEncode(turnPayload));
      sendStopwatch.stop();
      sendMs = sendStopwatch.elapsedMilliseconds;

      // Tunggu respons audio turn selesai diterima
      // Timeout diperlakukan sebagai ERROR nyata, bukan flow control biasa
      final resultBytes = await completer.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          _turnStopwatch.stop();
          _logError(
            operationId: currentOpId,
            stage: 'sendTurn',
            event: 'timeout',
            error: 'Audio synthesis turn timed out (server did not return final turn event)',
            text: cleanText,
          );
          if (kDebugMode) {
            debugPrint(
              '[V4 TURBO ERROR]\n'
              'stage=sendTurn\n'
              'operation_id=$currentOpId\n'
              'message=Audio synthesis turn timed out without receiving final event\n'
              'text="$cleanText"',
            );
          }
          throw TimeoutException('ElevenLabs v4 Turbo turn timed out for: $cleanText');
        },
      );

      _turnStopwatch.stop();
      final totalAudioMs = _turnStopwatch.elapsedMilliseconds;

      if (kDebugMode && resultBytes != null) {
        debugPrint(
          '[KOGO V4 TURBO]\n'
          'operation_id=$currentOpId\n'
          'connect_ms=${_lastConnectMs ?? 0}\n'
          'send_ms=$sendMs\n'
          'first_audio_ms=${_firstAudioMs ?? totalAudioMs}\n'
          'total_audio_ms=$totalAudioMs\n'
          'flush_sent=true\n'
          'final_turn_received=true',
        );
      }

      return resultBytes;
    } catch (e) {
      _turnStopwatch.stop();
      _logError(
        operationId: currentOpId,
        stage: 'sendTurn',
        event: 'send_failed',
        error: e.toString(),
        text: cleanText,
      );
      return null;
    } finally {
      if (_state == DialogueSessionState.streaming) {
        _state = DialogueSessionState.connected;
      }
    }
  }

  /// Mengalirkan stream audio chunk
  Stream<Uint8List> streamAudio() => _audioChunkController.stream;

  /// Memproses pesan JSON yang diterima dari WebSocket
  void _handleServerMessage(dynamic message) {
    if (message is List<int>) {
      final bytes = Uint8List.fromList(message);
      if (_firstAudioMs == null && _turnStopwatch.isRunning) {
        _firstAudioMs = _turnStopwatch.elapsedMilliseconds;
      }
      _currentTurnBuffer.add(bytes);
      _audioChunkController.add(bytes);
      return;
    }
    if (message is! String) return;

    try {
      final Map<String, dynamic> data = jsonDecode(message);

      // Cek error dari ElevenLabs
      if (data.containsKey('error') || (data.containsKey('message') && data['status'] == 'error')) {
        final errMsg = data['error']?.toString() ?? data['message']?.toString() ?? 'Unknown error';
        _logError(
          operationId: _activeOperationId,
          stage: 'streaming',
          event: 'server_error',
          error: errMsg,
        );
        if (kDebugMode) {
          debugPrint(
            '[V4 TURBO ERROR]\n'
            'stage=streaming\n'
            'operation_id=$_activeOperationId\n'
            'message=$errMsg',
          );
        }
        if (!(_currentTurnCompleter?.isCompleted ?? true)) {
          _currentTurnCompleter?.complete(null);
        }
        return;
      }

      // Format respons audio ElevenLabs Text-to-Dialogue
      String? base64Chunk;
      if (data.containsKey('audio')) {
        base64Chunk = data['audio'] as String?;
      } else if (data.containsKey('audio_base64')) {
        base64Chunk = data['audio_base64'] as String?;
      }

      if (base64Chunk != null && base64Chunk.isNotEmpty) {
        if (_firstAudioMs == null && _turnStopwatch.isRunning) {
          _firstAudioMs = _turnStopwatch.elapsedMilliseconds;
        }
        final bytes = base64Decode(base64Chunk);
        _currentTurnBuffer.add(bytes);
        _audioChunkController.add(bytes);
      }

      // Deteksi event turn selesai: is_final_audio_for_turn (resmi Text-to-Dialogue)
      // serta backward-compatible isFinal, is_final, flush_done
      final isFinalTurn = data['is_final_audio_for_turn'] == true ||
          data['isFinal'] == true ||
          data['is_final'] == true ||
          data['flush_done'] == true;

      if (isFinalTurn) {
        final completedBytes = _currentTurnBuffer.takeBytes();
        if (!(_currentTurnCompleter?.isCompleted ?? true)) {
          _currentTurnCompleter?.complete(completedBytes);
        }
      }
    } catch (e) {
      _logError(
        operationId: _activeOperationId,
        stage: 'handleServerMessage',
        event: 'json_decode_error',
        error: e.toString(),
      );
    }
  }

  void _handleSocketError(dynamic error) {
    _logError(
      operationId: _activeOperationId,
      stage: 'socket',
      event: 'connection_error',
      error: error.toString(),
    );
    _state = DialogueSessionState.error;
    if (!(_currentTurnCompleter?.isCompleted ?? true)) {
      _currentTurnCompleter?.complete(null);
    }
  }

  void _handleSocketDone() {
    _state = DialogueSessionState.disconnected;
    if (!(_currentTurnCompleter?.isCompleted ?? true)) {
      _currentTurnCompleter?.complete(_currentTurnBuffer.takeBytes());
    }
  }

  /// Menghentikan streaming dan mereset giliran aktif
  Future<void> stop({int? operationId}) async {
    if (operationId != null && operationId != _activeOperationId) {
      return;
    }
    _currentTurnBuffer = BytesBuilder(copy: false);
    if (!(_currentTurnCompleter?.isCompleted ?? true)) {
      _currentTurnCompleter?.complete(null);
    }
    if (_state == DialogueSessionState.streaming) {
      _state = DialogueSessionState.connected;
    }
  }

  /// Membatalkan koneksi secara langsung
  Future<void> cancel() async {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    await stop();
    try {
      await _socketSubscription?.cancel();
      _socketSubscription = null;
      await _webSocket?.close(WebSocketStatus.normalClosure);
      _webSocket = null;
    } catch (_) {}
    _state = DialogueSessionState.disconnected;
  }

  /// Reconnect ke sesi baru jika terjadi pemutusan koneksi
  Future<bool> reconnect() async {
    await cancel();
    return await connect();
  }

  /// Log error terstruktur sesuai pedoman kogo voice
  void _logError({
    required int operationId,
    required String stage,
    required String event,
    required String error,
    String? text,
  }) {
    if (!kDebugMode) return;
    debugPrint(
      '[KOGO VOICE ERROR]\n'
      'operation_id=$operationId\n'
      'model=$_modelId\n'
      'voice=$_voiceId\n'
      'status=${_state.name}\n'
      'stage=$stage\n'
      'event=$event\n'
      'error=$error\n'
      '${text != null ? 'text="$text"\n' : ''}',
    );
  }

  /// Membersihkan seluruh resources sesi
  Future<void> dispose() async {
    await cancel();
    await _audioChunkController.close();
  }
}
