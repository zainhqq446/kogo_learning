# Kogo Belajar

Voice-based word exploration app for early-childhood learners (ages 5–6), built for the
undergraduate thesis *"Pengembangan Media Pembelajaran Eksplorasi Kata Berbasis Voice Recognition
untuk Anak Usia Dini"* (Zain M Haqqo, 2207112580). The repository contains the Android app
(Flutter) and the research sync backend (Node.js + PostgreSQL).

```text
kogo_learning/
├── lib/        # Flutter app (Android)
├── test/       # Unit + widget tests (flutter test)
├── assets/     # Picture vocabulary, sound effects, background music
├── android/    # Android host project (minSdk 26 = Android 8.0)
├── tool/       # Asset/vocabulary generators
├── backend/    # Research sync API (Express + TypeScript + PostgreSQL, Docker)
└── docs/       # API reference and Coolify deployment guide
```

## Thesis scope (Batasan Masalah)

| Scope item | How the app satisfies it |
| :--- | :--- |
| Learners aged 5–6 | Biodata form only accepts age 5 or 6; large touch targets, voice guidance on every screen, no reading required to navigate. |
| Android 8.0 (Oreo) minimum | `minSdk = 26`, portrait-only, tested layouts at 360×740 dp. |
| Voice recognition for simple words, no custom ASR | Uses the device's Google speech recognizer (`speech_to_text`, `id_ID`) and evaluates pronunciation with a lightweight phonetic matcher (`lib/services/speech/pronunciation_evaluator.dart`). |
| Word exploration and pronunciation, not advanced reading | Four materials: letters, two-syllable words, three-syllable words, short color phrases. |
| Everyday vocabulary (fruit, animals, objects) | 87 picture words, 20 color phrases and 22 letters in `lib/core/curriculum/vocabulary.dart`. |

## App features

- **Onboarding** – splash, child biodata (name, school, age, avatar) with validation, microphone
  permission and Indonesian TTS check. Several children can share one device.
- **Home / Rewards / Profile tabs** following the Figma design (bear mascot, gradient cards,
  progress chips, reward tiers Perunggu 10 ⭐, Perak 50 ⭐, Emas 150 ⭐, Berlian 300 ⭐, learning streak).
- **Stage map** per material: units of up to four words, five games per unit, sequential unlocking,
  1–3 stars per game based on first-try accuracy.
- **Games**
  - *Dengar & Ulangi* (listen and repeat, voice recognition): up to three tries, "almost" feedback,
    silence does not cost a try, the word is revealed after three misses.
  - *Cari Objek* (find the object starting with a letter), *Huruf Hilang* (missing letter),
    *Permainan Cocokkan* (match word to picture), *Dengar & Pilih* (listen and choose),
    *Isi Huruf Kosong* (fill the blanks).
- **Kogo's recorded voice** – every sentence, example word, letter name and syllable spelling
  (861 clips) is recorded once with ElevenLabs in Indonesian and bundled in `assets/voice/`.
  The app never calls ElevenLabs at runtime, so playing costs no credits and works offline.
- **Indonesian device voice with intonation** – fallback when a sentence has no recording:
  Google TTS (`id-ID`) driven by a prosody planner that adjusts pitch, rate and pauses per mood.
  See `lib/services/audio/prosody_planner.dart`.
- **Child-friendly motion and sound** – entrance/loop/press animations, confetti, star reveals,
  synthesized sound effects, background music that ducks while Kogo speaks or listens; all
  animations respect the system "remove animations" setting.
- **Research mode** (behind a parental gate) – field-test metrics from Table 3.1 of the thesis:
  STT accuracy rate, task completion rate, system response time and system error rate, per
  child and per device, plus backend URL and manual sync.

## Data model

Local SQLite (`kogo_voice_learning.db`, schema v11) maps the thesis ERD:

| Thesis entity | Storage |
| :--- | :--- |
| Users | `learners` |
| GameSessions | `game_sessions` |
| Stars | `stars` (best result per game node) |
| Rewards | `rewards` |
| AnswerLogs | `answer_attempts` (target, recognized text, alternatives, score, response time, STT error) |
| Materi / Stages / WordType / Words | static curriculum in `lib/core/curriculum/` |

The app is fully offline-first. Completed sessions are synced in the background to the backend
(`POST /api/v2/sync`, idempotent by client UUID) when a connection is available.

## Development

Requirements: Flutter 3.47 (Dart 3.13), Android SDK, JDK 17.

```bash
flutter pub get
flutter analyze
flutter test
flutter run                       # device or emulator with Google app + Indonesian TTS data
flutter build apk --release       # build/app/outputs/flutter-apk/app-release.apk
```

The backend URL defaults to `https://be-kogo.taro.web.id/api` and can be overridden at build time
(`--dart-define=KOGO_BACKEND_URL=https://host/api`) or at runtime in Research mode.

Release signing uses `android/key.properties` when present (not committed); otherwise the debug
key is used so the APK can be installed for testing.

Optional visual check of every screen with real fonts:

```bash
KOGO_SCREENSHOTS=/tmp/shots flutter test test/screenshots/screenshots_test.dart
```

### Regenerating Kogo's voice

The clip list is built from the same sentence functions the app uses, and the widget tests fail
if the app says a sentence that is not in it. After changing any text in
`lib/services/audio/voice_lines.dart` or the vocabulary:

```bash
dart run tool/voice_catalog.dart > build/voice_catalog.json
python3 tool/generate_voice.py --voice cgSgspJ2msm6clMCkdW9 --dry-run   # characters to be billed
ELEVENLABS_API_KEY=<key with Text to Speech permission> \
  python3 tool/generate_voice.py --voice cgSgspJ2msm6clMCkdW9
```

Only new or changed sentences are sent to ElevenLabs; unused clips are removed. Never commit the
API key or put it in the app. Model `eleven_turbo_v2_5` with `language_code=id`, voice "Jessica".

### Device requirements

- Android 8.0+ with the Google app (speech recognition) and Google Text-to-Speech.
- Indonesian voice data installed in Google TTS (Settings → Text-to-speech). The app checks this
  during setup and offers a shortcut to the TTS settings.
- Internet is only needed for speech recognition on devices without offline Indonesian
  recognition, and for syncing research data.

## Backend

See [`backend/README.md`](backend/README.md), [`docs/API_DOCUMENTATION.md`](docs/API_DOCUMENTATION.md)
and [`docs/DEPLOYMENT_COOLIFY.md`](docs/DEPLOYMENT_COOLIFY.md) for running the API locally,
the v2 sync contract and deployment to Coolify at `be-kogo.taro.web.id`.

## Privacy

- Children are stored only on the device by name, school and age; the backend receives these
  records for research analysis over HTTPS and never receives audio recordings.
- Research mode and biodata changes are protected by a parental gate.
- No secrets are stored in the repository; backend secrets are provided via environment variables.
