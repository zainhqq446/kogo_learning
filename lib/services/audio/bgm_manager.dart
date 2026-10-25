import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Pengelola Background Music (BGM) ceria ramah anak.
/// Mendukung:
/// - Looping audio latar instrumental
/// - Kontrol volume & toggle Mute / Play / Pause
/// - Audio ducking (penurunan volume otomatis) saat mikrofon aktif merekam suara anak
class BgmManager {
  BgmManager._internal();
  static final BgmManager instance = BgmManager._internal();

  AudioPlayer? _player;
  bool _disabledForTesting = false;

  void setDisabledForTesting(bool disabled) {
    _disabledForTesting = disabled;
  }

  bool get _isDisabled {
    if (_disabledForTesting) return true;
    // Deteksi jika binding saat ini adalah flutter_test binding
    final bindingStr = WidgetsBinding.instance.runtimeType.toString();
    if (bindingStr.contains('TestWidgetsFlutterBinding')) {
      return true;
    }
    return false;
  }

  AudioPlayer get _effectivePlayer => _player ??= AudioPlayer();

  bool _isMuted = false;
  double _volume = 0.25; // default volume ceria lembut (25%)
  bool _isPlaying = false;
  bool _isDucked = false;

  bool get isMuted => _isMuted;
  double get volume => _volume;
  bool get isPlaying => _isPlaying;

  /// Memulai BGM instrumental lembut looping (default)
  Future<void> startBgm({String? assetPath}) async {
    if (_isDisabled || _isMuted) return;

    try {
      await _effectivePlayer.setReleaseMode(ReleaseMode.loop);
      await _effectivePlayer.setVolume(_isDucked ? (_volume * 0.2) : _volume);

      // Gunakan audio game intro/transition lembut jika tersedia
      final effectivePath = assetPath ?? 'audio/games/transition_next_01.mp3';
      await _effectivePlayer.play(AssetSource(effectivePath));
      _isPlaying = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BgmManager] Gagal memulai BGM: $e');
      }
    }
  }

  /// Menghentikan pemutaran BGM
  Future<void> stopBgm() async {
    if (_isDisabled) return;
    try {
      await _effectivePlayer.stop();
      _isPlaying = false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BgmManager] Gagal menghentikan BGM: $e');
      }
    }
  }

  /// Pause BGM
  Future<void> pauseBgm() async {
    if (_isDisabled) return;
    try {
      await _effectivePlayer.pause();
      _isPlaying = false;
    } catch (_) {}
  }

  /// Resume BGM
  Future<void> resumeBgm() async {
    if (_isDisabled || _isMuted) return;
    try {
      await _effectivePlayer.resume();
      _isPlaying = true;
    } catch (_) {}
  }

  /// Mengatur volume BGM (0.0 sampai 1.0)
  Future<void> setVolume(double newVolume) async {
    _volume = newVolume.clamp(0.0, 1.0);
    if (!_isMuted && !_isDisabled) {
      await _effectivePlayer.setVolume(_isDucked ? (_volume * 0.2) : _volume);
    }
  }

  /// Toggle Mute / Unmute
  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    if (_isDisabled) return;
    if (_isMuted) {
      await _effectivePlayer.setVolume(0.0);
    } else {
      await _effectivePlayer.setVolume(_isDucked ? (_volume * 0.2) : _volume);
      if (!_isPlaying) {
        await resumeBgm();
      }
    }
  }

  /// Menurunkan volume BGM (ducking) saat anak mulai berbicara ke mikrofon
  Future<void> duckForSpeech() async {
    if (_isDisabled || _isMuted || !_isPlaying) return;
    _isDucked = true;
    try {
      await _effectivePlayer.setVolume(_volume * 0.15); // Turunkan ke 15% dari volume asal
    } catch (_) {}
  }

  /// Mengembalikan volume BGM setelah anak selesai berbicara
  Future<void> restoreAfterSpeech() async {
    if (_isDisabled || _isMuted || !_isPlaying) return;
    _isDucked = false;
    try {
      await _effectivePlayer.setVolume(_volume);
    } catch (_) {}
  }

  AudioPlayer? _sfxPlayer;
  AudioPlayer get _effectiveSfxPlayer => _sfxPlayer ??= AudioPlayer();

  /// Memainkan efek suara (SFX) instan ramah anak (benar, salah, klik, selebrasi)
  Future<void> playSfx(String assetPath) async {
    if (_isDisabled || _isMuted) return;
    try {
      final effectivePath = assetPath.startsWith('assets/')
          ? assetPath.replaceFirst('assets/', '')
          : (assetPath.startsWith('audio/') ? assetPath : 'audio/$assetPath');
      await _effectiveSfxPlayer.stop();
      await _effectiveSfxPlayer.play(AssetSource(effectivePath));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BgmManager] Gagal memutar SFX: $e');
      }
    }
  }

  void dispose() {
    _player?.dispose();
    _sfxPlayer?.dispose();
  }
}
