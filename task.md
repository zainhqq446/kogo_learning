# Task Plan — Implementasi Lengkap Kogo Voice Learning PAUD

## 1. Objective & Scope
Menuntaskan perbaikan game, audio, interaksi suara, navigasi, dan identitas visual Kogo Voice Learning sesuai instruksi master goal:
- Komposisi 6 aktivitas per checkpoint kata (Stage 2-4): Listen & Repeat (2), Matching Object (1), Listen Carefully (2), Susun Kata (1).
- Stage 1 khusus huruf: Listen & Repeat huruf + Tebak Gambar Huruf Awal (4 gambar, 1 target).
- Permainan Matching Object sejati (6 gambar vs 6 kata).
- Permainan Susun Kata (`WordAssemblyPage`) dengan huruf diacak, tile ID unik, dan penanganan kata ulang (`lumba-lumba`).
- Centralized Audio & BGM Manager dengan ducking dan SFX lengkap.
- Interaksi suara ElevenLabs kontekstual di seluruh alur (termasuk sapaan nama anak di Home).
- Ice breaking dialog yang interaktif dan ramah anak.
- Navigasi soal dengan tombol Lanjut yang konsisten & anti-double tap.
- Splash screen & App Icon verifikasi.
- Pengujian unit/widget test & verifikasi analitis.

## 2. File Terkait
- `lib/features/activity/presentation/pages/matching_page.dart` (Refaktor menjadi 6 gambar vs 6 kata)
- `lib/features/activity/presentation/pages/word_assembly_page.dart` (Permainan Susun Kata baru dengan huruf diacak & kata ulang)
- `lib/features/activity/presentation/pages/find_object_page.dart` (Dukungan tebak gambar huruf awal untuk Stage 1)
- `lib/features/lesson/presentation/pages/checkpoint_session_page.dart` (Komposisi tepat 6 aktivitas per checkpoint)
- `lib/services/audio/bgm_manager.dart` & `kogo_voice_manager.dart` (Integrasi audio BGM & SFX terpusat)
- `lib/features/home/presentation/pages/home_page.dart` (Sapaan personal nama anak)
- `test/activity/matching_object_test.dart`
- `test/activity/word_assembly_test.dart`
- `test/checkpoint/checkpoint_composition_test.dart`
