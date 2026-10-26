/// Alamat backend Kogo (sinkronisasi data penelitian).
///
/// Bawaan: server produksi `https://be-kogo.taro.web.id/api`. Dapat diganti saat
/// build (`--dart-define=KOGO_BACKEND_URL=https://host/api`) atau saat runtime
/// dari Mode Peneliti (disimpan di pengaturan perangkat).
class BackendConfig {
  BackendConfig._();

  static const String defaultApiBaseUrl = String.fromEnvironment('KOGO_BACKEND_URL', defaultValue: 'https://be-kogo.taro.web.id/api');

  /// Kunci pendaftaran perangkat (opsional, `--dart-define=KOGO_ENROLLMENT_KEY=...`).
  /// Bila server memasang `DEVICE_ENROLLMENT_KEY` yang sama, tablet langsung
  /// disetujui; tanpa kunci, peneliti menyetujui perangkat dari server.
  static const String enrollmentKey = String.fromEnvironment('KOGO_ENROLLMENT_KEY');

  /// Menormalkan URL: tanpa garis miring di akhir dan selalu berakhiran `/api`.
  static String normalize(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u.endsWith('/api') ? u : '$u/api';
  }

  /// `true` bila URL valid (http/https dengan host).
  static bool isValid(String url) {
    final uri = Uri.tryParse(url.trim());
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty;
  }
}
