import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum ListenError { permissionDenied, notAvailable, noSpeech, network, busy, unknown }

/// Hasil satu sesi mendengarkan.
class ListenOutcome {
  const ListenOutcome({required this.alternates, this.error, this.responseMs, this.confidence});

  /// Semua kemungkinan transkripsi (n-best), terbaik lebih dulu.
  final List<String> alternates;
  final ListenError? error;

  /// Waktu respons sistem (proposal Tabel 3.1): dari akhir ucapan terakhir
  /// yang tertangkap (t_rekam) sampai hasil siap ditampilkan (t_hasil).
  final int? responseMs;
  final double? confidence;

  bool get heardSomething => alternates.any((a) => a.trim().isNotEmpty);
}

/// Pendengar suara yang dipakai aplikasi (diganti implementasi palsu di test).
class SpeechListeners {
  SpeechListeners._();

  static SpeechListener current = GoogleSpeechListener.instance;
}

abstract class SpeechListener {
  /// Inisialisasi & meminta izin mikrofon. `null` bila siap.
  Future<ListenError?> prepare();

  /// Mendengarkan satu ucapan. [accept] dipanggil pada setiap hasil sementara;
  /// bila mengembalikan `true`, sesi langsung diakhiri (respons cepat).
  Future<ListenOutcome> listen({
    required bool Function(List<String> alternates) accept,
    void Function(double level)? onLevel,
    void Function(String partial)? onPartial,
  });

  Future<void> cancel();
}

/// Google Speech-to-Text Android (sesuai proposal BAB III 3.2.2.3) melalui
/// paket `speech_to_text`, locale `id_ID`.
class GoogleSpeechListener implements SpeechListener {
  GoogleSpeechListener._();

  static final GoogleSpeechListener instance = GoogleSpeechListener._();

  /// Anak sering berhenti sejenak di antara suku kata, jadi jeda diam dibuat
  /// longgar sebelum sesi dianggap selesai.
  static const pauseFor = Duration(milliseconds: 1800);
  static const listenFor = Duration(seconds: 7);

  final SpeechToText _speech = SpeechToText();
  bool _ready = false;
  String _localeId = 'id_ID';
  Completer<ListenOutcome>? _active;
  void Function(String status)? _statusHook;
  void Function(SpeechRecognitionError error)? _errorHook;

  @override
  Future<ListenError?> prepare() async {
    if (_ready) return null;
    try {
      _ready = await _speech.initialize(
        onStatus: (s) => _statusHook?.call(s),
        onError: (e) => _errorHook?.call(e),
        finalTimeout: const Duration(milliseconds: 1200),
        debugLogging: kDebugMode,
      );
    } catch (e) {
      debugPrint('[SpeechListener] initialize gagal: $e');
      _ready = false;
    }
    if (!_ready) {
      final permitted = await _speech.hasPermission.catchError((_) => false);
      return permitted ? ListenError.notAvailable : ListenError.permissionDenied;
    }
    try {
      final locales = await _speech.locales();
      final indo = locales.where((l) => l.localeId.toLowerCase().replaceAll('-', '_') == 'id_id' || l.localeId.toLowerCase() == 'in_id');
      if (indo.isNotEmpty) _localeId = indo.first.localeId;
    } catch (_) {}
    return null;
  }

  @override
  Future<ListenOutcome> listen({
    required bool Function(List<String> alternates) accept,
    void Function(double level)? onLevel,
    void Function(String partial)? onPartial,
  }) async {
    final error = await prepare();
    if (error != null) return ListenOutcome(alternates: const [], error: error);
    if (_active != null && !_active!.isCompleted) await cancel();

    final completer = _active = Completer<ListenOutcome>();
    var alternates = <String>[];
    double? confidence;
    var lastHeardAt = DateTime.now();
    Timer? watchdog;
    Timer? grace;

    void finish({ListenError? err}) {
      if (completer.isCompleted) return;
      watchdog?.cancel();
      grace?.cancel();
      _statusHook = null;
      _errorHook = null;
      final heard = alternates.where((a) => a.trim().isNotEmpty).toList();
      completer.complete(
        ListenOutcome(
          alternates: heard,
          error: heard.isEmpty ? (err ?? ListenError.noSpeech) : null,
          responseMs: DateTime.now().difference(lastHeardAt).inMilliseconds,
          confidence: confidence,
        ),
      );
    }

    _statusHook = (status) {
      if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) {
        // Hasil akhir biasanya menyusul sesaat setelah status selesai.
        grace ??= Timer(const Duration(milliseconds: 700), finish);
      }
    };
    _errorHook = (e) => finish(err: _mapError(e.errorMsg));
    watchdog = Timer(listenFor + const Duration(seconds: 4), () {
      unawaited(_speech.stop());
      finish();
    });

    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult r) {
          final list = [r.recognizedWords, ...r.alternates.map((a) => a.recognizedWords)].where((t) => t.trim().isNotEmpty).toSet().toList();
          if (list.isEmpty) return;
          alternates = list;
          lastHeardAt = DateTime.now();
          if (r.hasConfidenceRating) confidence = r.confidence;
          onPartial?.call(r.recognizedWords);
          if (accept(list)) {
            unawaited(_speech.stop());
            finish();
          } else if (r.finalResult) {
            finish();
          }
        },
        onSoundLevelChange: onLevel,
        listenOptions: SpeechListenOptions(
          localeId: _localeId,
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.confirmation,
          autoPunctuation: false,
          pauseFor: pauseFor,
          listenFor: listenFor,
        ),
      );
    } catch (e) {
      debugPrint('[SpeechListener] listen gagal: $e');
      finish(err: ListenError.unknown);
    }
    return completer.future;
  }

  @override
  Future<void> cancel() async {
    final active = _active;
    _statusHook = null;
    _errorHook = null;
    try {
      await _speech.cancel();
    } catch (_) {}
    if (active != null && !active.isCompleted) {
      active.complete(const ListenOutcome(alternates: [], error: ListenError.noSpeech));
    }
  }

  static ListenError _mapError(String code) {
    switch (code) {
      case 'error_no_match':
      case 'error_speech_timeout':
        return ListenError.noSpeech;
      case 'error_network':
      case 'error_network_timeout':
      case 'error_server':
      case 'error_server_disconnected':
        return ListenError.network;
      case 'error_busy':
      case 'error_recognizer_busy':
        return ListenError.busy;
      case 'error_permission':
      case 'error_insufficient_permissions':
        return ListenError.permissionDenied;
      default:
        return ListenError.unknown;
    }
  }
}
