import 'package:flutter/services.dart';

/// Membuka layar pengaturan Android (izin mikrofon, data suara TTS).
/// Diimplementasikan di `MainActivity.kt` (channel `kogo/system`).
class SystemSettings {
  SystemSettings._();

  static const _channel = MethodChannel('kogo/system');

  static Future<bool> openAppSettings() => _invoke('openAppSettings');

  /// Pengaturan Text-to-Speech, untuk memasang suara Bahasa Indonesia.
  static Future<bool> openTtsSettings() => _invoke('openTtsSettings');

  static Future<bool> _invoke(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
