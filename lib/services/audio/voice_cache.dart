import 'dart:typed_data';

/// Cache audio in-memory thread-safe untuk audio statis & dinamis Kogo Voice.
/// Mencegah request TTS baru setiap kali Widget rebuild atau saat kata yang sama dipanggil lagi.
class VoiceCache {
  VoiceCache._internal();
  static final VoiceCache instance = VoiceCache._internal();

  final Map<String, Uint8List> _cache = {};

  /// Menyimpan audio bytes ke cache
  void put(String key, Uint8List bytes) {
    _cache[key] = bytes;
  }

  /// Mengambil audio bytes dari cache
  Uint8List? get(String key) {
    return _cache[key];
  }

  /// Memeriksa apakah key ada dalam cache
  bool contains(String key) {
    return _cache.containsKey(key);
  }

  /// Menghapus cache spesifik atau seluruh cache
  void clear() {
    _cache.clear();
  }

  /// Jumlah item yang di-cache saat ini
  int get size => _cache.length;
}
