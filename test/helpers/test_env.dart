import 'package:kogo_voice_learning/app/app_session.dart';
import 'package:kogo_voice_learning/services/audio/voice_service.dart';
import 'package:kogo_voice_learning/services/speech/speech_listener.dart';
import 'package:kogo_voice_learning/services/sync/sync_service.dart';

import 'fakes.dart';
import 'test_database.dart';

/// Lingkungan bersih per test: database in-memory baru dan singleton baru.
///
/// Singleton harus dibuat ulang karena Future yang di-cache dari zona
/// FakeAsync test sebelumnya tidak akan pernah selesai di test berikutnya.
Future<({SilentSpeechEngine voice, FakeSpeechListener listener})> resetTestEnv() async {
  await useFreshTestDatabase();
  final voice = SilentSpeechEngine();
  final listener = FakeSpeechListener();
  VoiceService.instance = VoiceService(voice);
  SpeechListeners.current = listener;
  SyncService.instance = SyncService(post: (url, body, {bearer, headers}) async => const HttpResult(503, {}));
  AppSession.instance = AppSession();
  return (voice: voice, listener: listener);
}
