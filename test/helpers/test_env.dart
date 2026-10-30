import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/app/app_session.dart';
import 'package:kogo_voice_learning/services/audio/voice_clips.dart';
import 'package:kogo_voice_learning/services/audio/voice_service.dart';
import 'package:kogo_voice_learning/services/speech/speech_listener.dart';
import 'package:kogo_voice_learning/services/sync/sync_service.dart';

import 'fakes.dart';
import '../../tool/voice_catalog.dart';
import 'test_database.dart';

/// Lingkungan bersih per test: database in-memory baru dan singleton baru.
///
/// Singleton harus dibuat ulang karena Future yang di-cache dari zona
/// FakeAsync test sebelumnya tidak akan pernah selesai di test berikutnya.
Future<({SilentSpeechEngine voice, FakeSpeechListener listener})> resetTestEnv() async {
  await useFreshTestDatabase();
  final voice = SilentSpeechEngine();
  final listener = FakeSpeechListener();
  VoiceService.instance = VoiceService(voice)..useClips(catalogClips, FakeClipPlayer());
  // Setiap kalimat yang diucapkan selama test harus ada di daftar rekaman.
  addTearDown(() => expect(VoiceService.instance.missingClips, isEmpty, reason: 'tambahkan kalimat ini ke tool/voice_catalog.dart'));
  SpeechListeners.current = listener;
  SyncService.instance = SyncService(post: (url, body, {bearer, headers}) async => const HttpResult(503, {}));
  AppSession.instance = AppSession();
  return (voice: voice, listener: listener);
}

/// Semua kunci di daftar rekaman, seolah-olah seluruh klip sudah dibuat.
final VoiceClips catalogClips = VoiceClips({for (final e in buildVoiceCatalog()) e.key: '${e.key}.mp3'});
