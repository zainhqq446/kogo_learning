import 'dart:async';

import 'package:kogo_voice_learning/core/motion/motion.dart';
import 'package:kogo_voice_learning/services/audio/audio_service.dart';
import 'package:kogo_voice_learning/services/audio/voice_service.dart';
import 'package:kogo_voice_learning/services/sync/sync_service.dart';

import 'helpers/fakes.dart';

/// Konfigurasi global semua test: animasi berulang dimatikan (agar
/// `pumpAndSettle` selesai), plugin audio dinonaktifkan, dan TTS diganti
/// mesin senyap yang mencatat ucapan.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Motion.enabled = false;
  AudioService.disabled = true;
  VoiceService.instance = VoiceService(SilentSpeechEngine());
  // Tanpa jaringan di test: server dianggap tidak tersedia.
  SyncService.instance = SyncService(post: (url, body, {bearer}) async => const HttpResult(503, {}));
  await testMain();
}
