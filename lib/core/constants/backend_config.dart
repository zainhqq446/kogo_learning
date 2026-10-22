import 'dart:io';

/// Konfigurasi terpusat untuk komunikasi dengan backend server Kogo Voice Learning.
/// Mendukung deteksi otomatis alamat IP / hostname yang sesuai untuk:
/// - Windows Desktop / macOS / Linux: http://127.0.0.1:4000/api
/// - Android Emulator: http://10.0.2.2:4000/api
/// - Device Fisik / Custom Host: dapat disesuaikan via setter atau environment variable `KOGO_BACKEND_URL`
class BackendConfig {
  BackendConfig._();

  static String? _customBaseUrl;

  /// Mengatur backend base URL kustom saat runtime (misalnya dari pengaturan IP guru/peneliti).
  static void setBaseUrl(String url) {
    _customBaseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// Base URL endpoint API backend Kogo (selalu berakhiran `/api`)
  static String get apiBaseUrl {
    if (_customBaseUrl != null && _customBaseUrl!.isNotEmpty) {
      return _customBaseUrl!.endsWith('/api') ? _customBaseUrl! : '$_customBaseUrl/api';
    }

    // Periksa apakah didefinisikan melalui Dart environment variable
    const envUrl = String.fromEnvironment('KOGO_BACKEND_URL', defaultValue: '');
    if (envUrl.isNotEmpty) {
      return envUrl.endsWith('/api') ? envUrl : '$envUrl/api';
    }

    try {
      if (Platform.isAndroid) {
        // Pada perangkat fisik Android dengan adb reverse (tcp:4000), 127.0.0.1:4000 dapat diakses langsung.
        // Jika tidak disetel secara eksplisit, gunakan 127.0.0.1 agar kompatibel dengan adb reverse di perangkat fisik
        // dan tetap mengizinkan custom IP melalui setter atau KOGO_BACKEND_URL.
        return 'http://127.0.0.1:4000/api';
      }
    } catch (_) {}

    // Default untuk Windows, Web, Linux, macOS
    return 'http://127.0.0.1:4000/api';
  }

  /// URL akar server backend (tanpa akhiran `/api`)
  static String get serverRootUrl {
    final api = apiBaseUrl;
    if (api.endsWith('/api')) {
      return api.substring(0, api.length - 4);
    }
    return api;
  }
}
