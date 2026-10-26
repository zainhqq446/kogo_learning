import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Efek suara non-verbal (dibuat oleh `tool/generate_sfx.py`).
enum Sfx {
  tap('tap'),
  pop('pop'),
  correct('correct'),
  wrong('wrong'),
  star('star'),
  complete('complete'),
  whoosh('whoosh'),
  unlock('unlock'),
  micOn('mic_on'),
  micOff('mic_off');

  const Sfx(this.file);
  final String file;
  String get asset => 'audio/sfx/$file.mp3';
}

/// Musik latar & efek suara. Pemutar memakai mode `mixWithOthers` sehingga
/// tidak merebut audio focus dari suara Kogo (TTS); musik diredam (ducking)
/// saat Kogo berbicara dan dijeda total saat mikrofon mendengarkan.
class AudioService {
  AudioService._();

  static final AudioService instance = AudioService._();

  static const _musicAsset = 'audio/bgm/playful_loop.mp3';
  static const _musicVolume = 0.35;
  static const _duckedVolume = 0.08;

  /// Dimatikan pada widget test (plugin audio tidak tersedia).
  static bool disabled = false;

  bool soundOn = true;
  bool musicOn = true;

  final List<AudioPlayer> _sfxPool = [];
  int _nextSfx = 0;
  AudioPlayer? _music;
  bool _musicWanted = false;
  bool _appPaused = false;
  bool _listening = false;
  int _duckCount = 0;

  AudioContext get _mixContext => AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build();

  Future<AudioPlayer> _sfxPlayer() async {
    if (_sfxPool.length < 3) {
      final p = AudioPlayer();
      await p.setAudioContext(_mixContext);
      await p.setPlayerMode(PlayerMode.lowLatency);
      await p.setReleaseMode(ReleaseMode.stop);
      _sfxPool.add(p);
      return p;
    }
    final p = _sfxPool[_nextSfx];
    _nextSfx = (_nextSfx + 1) % _sfxPool.length;
    return p;
  }

  void play(Sfx sfx, {double volume = 0.9}) {
    if (disabled || !soundOn || _appPaused) return;
    unawaited(_play(sfx, volume));
  }

  Future<void> _play(Sfx sfx, double volume) async {
    try {
      final p = await _sfxPlayer();
      await p.stop();
      await p.play(AssetSource(sfx.asset), volume: volume);
    } catch (e) {
      debugPrint('[AudioService] sfx ${sfx.file} gagal: $e');
    }
  }

  /// Musik latar halaman peta & permainan.
  Future<void> startMusic() async {
    _musicWanted = true;
    await _syncMusic();
  }

  Future<void> stopMusic() async {
    _musicWanted = false;
    await _syncMusic();
  }

  /// Saat Kogo berbicara musik diredam; dapat bertumpuk (ref-count).
  void duck() {
    _duckCount++;
    unawaited(_applyVolume());
  }

  void unduck() {
    if (_duckCount > 0) _duckCount--;
    unawaited(_applyVolume());
  }

  /// Saat mikrofon aktif musik dijeda total agar tidak ikut terekam.
  Future<void> setListening(bool listening) async {
    _listening = listening;
    await _syncMusic();
  }

  Future<void> setAppPaused(bool paused) async {
    _appPaused = paused;
    await _syncMusic();
  }

  Future<void> setMusicOn(bool on) async {
    musicOn = on;
    await _syncMusic();
  }

  Future<void> _syncMusic() async {
    if (disabled) return;
    final shouldPlay = _musicWanted && musicOn && !_appPaused && !_listening;
    try {
      if (shouldPlay) {
        final music = _music ??= await _createMusicPlayer();
        if (music.state != PlayerState.playing) {
          await music.setVolume(_currentVolume);
          if (music.state == PlayerState.paused) {
            await music.resume();
          } else {
            await music.play(AssetSource(_musicAsset), volume: _currentVolume);
          }
        }
      } else if (_music?.state == PlayerState.playing) {
        await _music!.pause();
      }
    } catch (e) {
      debugPrint('[AudioService] musik gagal: $e');
    }
  }

  Future<AudioPlayer> _createMusicPlayer() async {
    final p = AudioPlayer();
    await p.setAudioContext(_mixContext);
    await p.setReleaseMode(ReleaseMode.loop);
    return p;
  }

  double get _currentVolume => _duckCount > 0 ? _duckedVolume : _musicVolume;

  Future<void> _applyVolume() async {
    if (disabled) return;
    try {
      await _music?.setVolume(_currentVolume);
    } catch (_) {}
  }
}
