import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../core/curriculum/vocabulary.dart';
import 'audio_service.dart';
import 'indonesian_text.dart';
import 'prosody_planner.dart';
import 'voice_clips.dart';
import 'voice_keys.dart';

/// Mesin TTS yang dapat diganti (diuji dengan implementasi palsu).
abstract class SpeechEngine {
  /// Mengembalikan `true` bila suara bahasa Indonesia tersedia.
  Future<bool> init();

  /// Mengucapkan satu potongan dan selesai ketika suara berhenti.
  Future<void> speak(SpeechChunk chunk);
  Future<void> stop();
}

/// Text-to-Speech Android (Google TTS) — sesuai rancangan proposal
/// (BAB III 3.2.2.3: Google Text-to-Speech untuk contoh pelafalan).
class FlutterTtsEngine implements SpeechEngine {
  final FlutterTts _tts = FlutterTts();

  @override
  Future<bool> init() async {
    try {
      await _tts.awaitSpeakCompletion(true);
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _tts.setQueueMode(0);
        final engines = await _tts.getEngines;
        if (engines is List && engines.contains('com.google.android.tts')) {
          await _tts.setEngine('com.google.android.tts');
        }
      }
      final available = await _tts.isLanguageAvailable('id-ID') == true;
      await _tts.setLanguage('id-ID');
      await _tts.setVolume(1);
      await _pickIndonesianVoice();
      return available;
    } catch (e) {
      debugPrint('[VoiceService] init TTS gagal: $e');
      return false;
    }
  }

  /// Memilih suara perempuan id-ID lokal (offline) bila tersedia; suara
  /// lokal tidak membutuhkan internet dan mulai bicara lebih cepat.
  Future<void> _pickIndonesianVoice() async {
    try {
      final voices = await _tts.getVoices;
      if (voices is! List) return;
      final indo = voices.whereType<Map>().where((v) => '${v['locale']}'.toLowerCase().replaceAll('_', '-') == 'id-id').toList();
      if (indo.isEmpty) return;
      indo.sort((a, b) => _voiceScore(b).compareTo(_voiceScore(a)));
      final best = indo.first;
      await _tts.setVoice({'name': '${best['name']}', 'locale': '${best['locale']}'});
    } catch (_) {}
  }

  int _voiceScore(Map v) {
    final name = '${v['name']}'.toLowerCase();
    var score = 0;
    if (name.contains('local')) score += 4;
    if (!'${v['network_required']}'.contains('1') && !'${v['network_required']}'.contains('true')) score += 2;
    if (name.contains('idc') || name.contains('female')) score += 1;
    return score;
  }

  @override
  Future<void> speak(SpeechChunk chunk) async {
    await _tts.setPitch(chunk.pitch);
    await _tts.setSpeechRate(chunk.rate);
    await _tts.speak(chunk.text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }
}

/// Suara Kogo: TTS bahasa Indonesia dengan intonasi per kalimat.
///
/// Setiap panggilan [say] membatalkan ucapan sebelumnya ("terbaru menang")
/// sehingga suara tidak pernah bertumpuk. Status [speaking] dipakai maskot
/// untuk animasi berbicara.
class VoiceService extends ChangeNotifier {
  VoiceService(this._engine);

  static VoiceService instance = VoiceService(FlutterTtsEngine());

  SpeechEngine _engine;
  VoiceClips _clips = VoiceClips.empty;
  ClipPlayer? _clipPlayer;
  Future<bool>? _initializing;
  bool _available = true;
  int _generation = 0;
  bool _speaking = false;

  bool get speaking => _speaking;

  /// `false` bila perangkat belum memiliki suara bahasa Indonesia.
  bool get indonesianAvailable => _available;

  /// Kalimat yang belum memiliki rekaman sehingga diucapkan TTS perangkat.
  @visibleForTesting
  final Set<String> missingClips = {};

  /// Jumlah klip rekaman yang tersedia (0 = memakai TTS perangkat).
  int get clipCount => _clips.length;

  @visibleForTesting
  void useEngine(SpeechEngine engine) {
    _engine = engine;
    _initializing = null;
  }

  /// Memakai rekaman suara Kogo; kalimat tanpa rekaman tetap memakai TTS.
  void useClips(VoiceClips clips, ClipPlayer player) {
    _clips = clips;
    _clipPlayer = player;
  }

  Future<bool> init() => _initializing ??= _engine.init().then((ok) => _available = ok);

  /// Mengucapkan teks dengan suasana [mood]. [emphasize] = kata target yang
  /// diucapkan pelan & jelas sebagai contoh pelafalan.
  Future<void> say(String text, {SpeechMood mood = SpeechMood.warm, String? emphasize}) {
    final files = _lookup(VoiceKeys.sentences(text).map(VoiceKeys.key));
    if (files != null) return _runClips(files);
    return _run(ProsodyPlanner.plan(text, mood: mood, emphasize: emphasize));
  }

  /// Contoh pelafalan per suku kata: "ke … lin … ci … kelinci!".
  Future<void> spell(VocabItem item) {
    if (item.isLetter) return sayLetter(item.text);
    final files = _lookup([VoiceKeys.spell(item)]);
    if (files != null) return _runClips(files);
    return _run(ProsodyPlanner.syllables(item.syllables, item.text));
  }

  /// Mengucapkan nama huruf dalam bahasa Indonesia (contoh "be", "ce").
  Future<void> sayLetter(String letter) {
    final files = _lookup([VoiceKeys.letter(letter)]);
    if (files != null) return _runClips(files);
    final name = IndonesianText.letterNames[letter.toLowerCase()] ?? letter;
    return _run([SpeechChunk(name, pitch: ProsodyPlanner.targetPitch, rate: ProsodyPlanner.targetRate, pauseAfterMs: 200)]);
  }

  /// Ucapan kata target saja (lambat & jelas).
  Future<void> sayWord(VocabItem item) {
    if (item.isLetter) return sayLetter(item.text);
    final files = _lookup([VoiceKeys.word(item)]);
    if (files != null) return _runClips(files);
    return _run([SpeechChunk('${item.text}.', pitch: ProsodyPlanner.targetPitch, rate: ProsodyPlanner.targetRate, pauseAfterMs: 200)]);
  }

  Future<void> stop() async {
    _generation++;
    await _safeStop();
    _setSpeaking(false);
  }

  List<String>? _lookup(Iterable<String> keys) {
    if (_clips.isEmpty || _clipPlayer == null) return null;
    final list = keys.toList();
    final files = _clips.lookup(list);
    if (files == null) missingClips.addAll(list.where((k) => _clips.lookup([k]) == null));
    return files;
  }

  /// Memutar rekaman kalimat demi kalimat dengan jeda pendek.
  Future<void> _runClips(List<String> files) async {
    final generation = ++_generation;
    final player = _clipPlayer!;
    await _safeStop();
    if (generation != _generation) return;
    _setSpeaking(true);
    AudioService.instance.duck();
    try {
      for (var i = 0; i < files.length; i++) {
        if (generation != _generation) return;
        await player.play(files[i]);
        if (generation != _generation) return;
        if (i < files.length - 1) await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    } catch (e) {
      debugPrint('[VoiceService] gagal memutar rekaman: $e');
    } finally {
      AudioService.instance.unduck();
      if (generation == _generation) _setSpeaking(false);
    }
  }

  Future<void> _run(List<SpeechChunk> chunks) async {
    final generation = ++_generation;
    await _safeStop();
    if (chunks.isEmpty) return;
    await init();
    if (generation != _generation) return;
    _setSpeaking(true);
    AudioService.instance.duck();
    try {
      for (final chunk in chunks) {
        if (generation != _generation) return;
        try {
          await _engine.speak(chunk).timeout(_timeoutFor(chunk));
        } on TimeoutException {
          await _safeStop();
        }
        if (generation != _generation) return;
        if (chunk.pauseAfterMs > 0) await Future<void>.delayed(Duration(milliseconds: chunk.pauseAfterMs));
      }
    } catch (e) {
      debugPrint('[VoiceService] gagal berbicara: $e');
    } finally {
      AudioService.instance.unduck();
      if (generation == _generation) _setSpeaking(false);
    }
  }

  /// Batas aman bila mesin TTS tidak pernah mengirim sinyal selesai.
  Duration _timeoutFor(SpeechChunk chunk) => Duration(milliseconds: 4000 + chunk.text.length * 160);

  Future<void> _safeStop() async {
    try {
      await _engine.stop();
    } catch (_) {}
    try {
      await _clipPlayer?.stop();
    } catch (_) {}
  }

  void _setSpeaking(bool value) {
    if (_speaking == value) return;
    _speaking = value;
    notifyListeners();
  }
}
