import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Rekaman suara Kogo (ElevenLabs) yang dibuat sekali oleh
/// `tool/generate_voice.py` dan dibundel di `assets/voice/`.
///
/// Setiap kalimat disimpan sebagai satu klip; kuncinya adalah teks kalimat
/// yang dinormalkan. Aplikasi tidak pernah memanggil ElevenLabs saat
/// dijalankan, sehingga kuota tidak terpakai dan suara tetap ada tanpa internet.
class VoiceClips {
  VoiceClips(this._files);

  static const manifestAsset = 'assets/voice/manifest.json';
  static final VoiceClips empty = VoiceClips(const {});

  final Map<String, String> _files;

  bool get isEmpty => _files.isEmpty;
  int get length => _files.length;

  /// Membaca manifest; bila belum ada rekaman, hasilnya kosong (aplikasi
  /// memakai TTS perangkat).
  static Future<VoiceClips> load(AssetBundle bundle) async {
    try {
      final json = jsonDecode(await bundle.loadString(manifestAsset)) as Map<String, dynamic>;
      final clips = (json['clips'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as String));
      return VoiceClips(clips);
    } catch (e) {
      debugPrint('[VoiceClips] rekaman tidak tersedia: $e');
      return empty;
    }
  }

  /// Berkas untuk setiap kunci, atau `null` bila ada yang belum direkam.
  List<String>? lookup(Iterable<String> keys) {
    final out = <String>[];
    for (final k in keys) {
      final file = _files[k];
      if (file == null) return null;
      out.add(file);
    }
    return out.isEmpty ? null : out;
  }
}

/// Pemutar klip suara Kogo.
abstract class ClipPlayer {
  /// Memutar satu klip dan selesai ketika klip berakhir.
  Future<void> play(String file);
  Future<void> stop();
}

class AudioClipPlayer implements ClipPlayer {
  AudioPlayer? _player;
  Completer<void>? _done;

  Future<AudioPlayer> _ready() async {
    final existing = _player;
    if (existing != null) return existing;
    final p = AudioPlayer();
    await p.setAudioContext(AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build());
    await p.setReleaseMode(ReleaseMode.stop);
    p.onPlayerComplete.listen((_) => _finish());
    return _player = p;
  }

  void _finish() {
    final done = _done;
    _done = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  @override
  Future<void> play(String file) async {
    final p = await _ready();
    _finish();
    final done = _done = Completer<void>();
    await p.play(AssetSource('voice/$file'));
    // Pengaman bila sinyal selesai tidak pernah datang.
    await done.future.timeout(const Duration(seconds: 15), onTimeout: () {});
  }

  @override
  Future<void> stop() async {
    _finish();
    await _player?.stop();
  }
}
