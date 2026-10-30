import 'dart:async';

import 'package:kogo_voice_learning/services/audio/prosody_planner.dart';
import 'package:kogo_voice_learning/services/audio/voice_clips.dart';
import 'package:kogo_voice_learning/services/audio/voice_service.dart';
import 'package:kogo_voice_learning/services/speech/speech_listener.dart';

/// Mesin TTS senyap untuk test; mencatat semua potongan ucapan.
/// Pemutar klip palsu: mencatat berkas yang diputar.
class FakeClipPlayer implements ClipPlayer {
  final List<String> played = [];

  @override
  Future<void> play(String file) async => played.add(file);

  @override
  Future<void> stop() async {}
}

class SilentSpeechEngine implements SpeechEngine {
  SilentSpeechEngine({this.available = true});

  final bool available;
  final List<SpeechChunk> spoken = [];

  @override
  Future<bool> init() async => available;

  @override
  Future<void> speak(SpeechChunk chunk) async => spoken.add(chunk);

  @override
  Future<void> stop() async {}
}

/// Pendengar suara palsu: setiap `listen` mengembalikan hasil berikutnya
/// dari antrean [outcomes] (atau "tidak terdengar" bila habis).
class FakeSpeechListener implements SpeechListener {
  FakeSpeechListener({this.prepareError, List<ListenOutcome>? outcomes}) : outcomes = outcomes ?? [];

  ListenError? prepareError;
  final List<ListenOutcome> outcomes;
  int listenCalls = 0;
  int cancelCalls = 0;
  final List<bool> acceptResults = [];

  void say(String text, {int responseMs = 600}) => outcomes.add(ListenOutcome(alternates: [text], responseMs: responseMs));

  @override
  Future<ListenError?> prepare() async => prepareError;

  @override
  Future<ListenOutcome> listen({
    required bool Function(List<String> alternates) accept,
    void Function(double level)? onLevel,
    void Function(String partial)? onPartial,
  }) async {
    listenCalls++;
    if (prepareError != null) return ListenOutcome(alternates: const [], error: prepareError);
    final outcome = outcomes.isEmpty ? const ListenOutcome(alternates: [], error: ListenError.noSpeech) : outcomes.removeAt(0);
    if (outcome.alternates.isNotEmpty) {
      onPartial?.call(outcome.alternates.first);
      acceptResults.add(accept(outcome.alternates));
    }
    return outcome;
  }

  @override
  Future<void> cancel() async => cancelCalls++;
}
