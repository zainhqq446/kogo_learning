# Laporan Audit dan Remediasi Kualitas Kode Kogo Learning (SonarQube Cloud)

## 1. Informasi Repository dan Konteks Analisis

| Atribut | Nilai |
|---|---|
| Repository | `https://github.com/zainhqq446/kogo_learning` |
| Branch Dasar | `main` |
| Commit Dasar | `8ccebe2702b6b500dd68e7cd75287287317e8c44` (`feat(voice): bundle 861 Kogo voice clips recorded with ElevenLabs`) |
| Branch Perbaikan | `fix/sonarqube-remediation` |
| Tanggal Audit & Perbaikan | 12 November 2026 |
| Lingkungan Lokal | Windows 11, Flutter `3.47.5` (Dart `3.13.4`), Node.js `v24.16.0`, TypeScript `5.7.2`, Python `3.11.9` |
| Keterbatasan Lingkungan Lokal | Tidak ada Docker daemon lokal, tidak ada perangkat Android fisik / emulator terpasang saat pengujian (`adb devices` kosong), serta kredensial database test PostgreSQL terpisah (`TEST_DATABASE_URL`) tidak dikonfigurasi. |

---

## 2. Kondisi Awal SonarQube Cloud

Hasil pemindaian awal SonarQube Cloud sebelum remediasi:

| Aspek | Rating Awal | Jumlah Issue | Target |
|---|---|---|---|
| Security | D | 11 | A |
| Reliability | D | 12 | A |
| Maintainability | A | 5 | Pertahankan A |
| Dependency Risks | B | 2 | Tidak bertambah |

Pengukuran baseline lokal pada commit dasar `8ccebe2702b6b500dd68e7cd75287287317e8c44`:
- Backend TypeScript unit tests (`npm test`): **90/90 lulus**.
- `flutter analyze`: **0 issues found**.
- `flutter test`: **79 lulus, 2 di-skip**.
- Katalog suara (`dart run tool/voice_catalog.dart` vs `assets/voice/manifest.json`): **861/861 klip cocok**.

---

## 3. Daftar Issue yang Ditemukan (Inventarisasi Awal)

| No | Kategori & Severity | File & Baris | Rule ID SonarQube | Deskripsi Temuan |
|---|---|---|---|---|
| 1 | Reliability / High | `backend/src/services/reference_data_service.ts:76` | `typescript:S2871` | Pemanggilan `.sort()` pada array string kategori tanpa comparator `localeCompare`. |
| 2 | Reliability / High | `backend/src/services/tts_cache.ts:22` | `typescript:S2871` | Pemanggilan `.sort()` pada key `settings` pembentuk cache key TTS tanpa comparator `localeCompare`. |
| 3 | Security / High | `android/app/build.gradle.kts:51` | `kotlin:S7204` | `buildTypes.release` belum mengaktifkan `isMinifyEnabled`, `isShrinkResources`, dan `proguardFiles`. |
| 4 | Security / High | `tool/generate_voice.py:45` | `python:S4790` | Penggunaan `hashlib.sha1(...)` pada `clip_name()` tanpa penandaan non-kriptografis / evaluasi algoritma hash. |
| 5 | Security / High | `tool/generate_voice.py:133, 135, 225, 231` | `pythonsecurity:S8707` | Penggunaan path argumen `--catalog`, `--out`, dan nama file keluaran untuk operasi baca/tulis/hapus tanpa pembatasan direktori dan validasi nama file (Path Traversal via CLI arguments). |
| 6 | Reliability / Medium | `backend/src/config/env.ts:266, 363` | `typescript:S8786` | Regex `/\/+$/` untuk memangkas trailing slash pada `API_PREFIX` dan `ELEVENLABS_BASE_URL` berpotensi super-linear backtracking. |
| 7 | Reliability / Medium | `backend/src/controllers/v2_controller.ts:16` | `typescript:S8786` | Regex `/\..+$/` pada `csvFilename()` berpotensi backtracking bila mendapat input bertitik majemuk. |
| 8 | Reliability / Medium | `backend/src/services/auth_service.ts:197-200` | `typescript:S7737` | Parameter default `credentials` memakai object literal (`= { username: ..., password: ... }`). |
| 9 | Reliability / Medium | `backend/src/services/curriculum_service.ts:346-348` | `typescript:S7773` | Penggunaan `parseInt(..., 10)` global alih-alih `Number.parseInt(..., 10)`. |
| 10 | Reliability / Medium | `backend/src/test/helpers/http.ts:54, 72` | `typescript:S7737` | Parameter default pada `testPrincipals()` dan `rawToken()` menggunakan object literal secara langsung. |
| 11 | Reliability / Medium | `backend/src/types/schemas.ts:19` | `typescript:S6324` | Regular expression `NO_NUL = /^[^\u0000]*$/` mengandung karakter kontrol `\u0000` di dalam regex literal. |
| 12 | Reliability / Medium | `web/index.html:2` | `Web:S5254` | Tag `<html>` tidak memiliki atribut bahasa (`lang`). |
| 13 | Security / Medium-Low | `backend/Dockerfile:19, 41` | `docker:S6505` | `npm ci` dijalankan tanpa `--ignore-scripts`. |
| 14 | Security / Medium-Low | `backend/src/test/helpers/db.ts:68` | `typescript:S2245` | `Math.random()` digunakan untuk suffix username pengujian pada `createUserWithToken`. |
| 15 | Security / Medium-Low | `android/app/src/main/AndroidManifest.xml:13`, `android/app/src/main/res/xml/network_security_config.xml:5-9` | `xml:S5332` | `AndroidManifest.xml` belum menyetel `android:usesCleartextTraffic="false"` secara eksplisit dan `network_security_config.xml` di source set `main` mengizinkan `cleartextTrafficPermitted="true"` untuk host lokal sehingga ikut terbawa ke build release. |
| 16 | Security / Medium-Low | `backend/docker/postgres/Dockerfile` | `docker:S6471` | Dockerfile turunan `postgres:16-alpine` berjalan tanpa instruksi `USER` non-root eksplisit. |

---

## 4. Root Cause dan Keputusan Teknis Setiap Issue

1. **`reference_data_service.ts:76` (`typescript:S2871`)**: `.sort()` tanpa comparator mengurutkan string berdasarkan UTF-16 code units. Perbaikan menggunakan `(a, b) => a.localeCompare(b)`. Semua kode kategori adalah lowercase ASCII pendek (`benda`, dll.) dan dimasukkan via `ON CONFLICT DO UPDATE` ke `word_types`, sehingga seed tetap idempoten.
2. **`tts_cache.ts:22` (`typescript:S2871`)**: Pengurutan key `settings` digunakan untuk membentuk string material cache SHA-256. Pemakaian `.localeCompare(b)` tanpa locale berisiko menghasilkan urutan berbeda di locale sistem tertentu (mis. Estonia/Turki atau aturan tanda baca). Dipilih `.sort((a, b) => a.localeCompare(b, 'en'))` yang deterministik lintas mesin dan menghasilkan hash `efd69447b01668c015ccb601ab5a58e9b52cf8fc014bbf08f3963a086b414c8a` yang identik dengan keluaran awal.
3. **`android/app/build.gradle.kts:51` (`kotlin:S7204`)**: `buildTypes.release` hanya mengatur `signingConfig`. Mengaktifkan `isMinifyEnabled = true` dan `isShrinkResources = true` dengan `android/app/proguard-rules.pro` menjaga kelas refleksi/JNI Flutter dan plugin (`io.flutter.**`, `audioplayers`, `flutter_tts`, `speech_to_text`, `sqflite`, `jni`), serta menambahkan `-dontwarn` untuk referensi opsional `com.google.android.play.core.*` dari Flutter PlayStoreDeferredComponentManager yang tidak digunakan aplikasi. Catatan: obfuscation simbol Dart (`flutter build apk --obfuscate --split-debug-info=...`) tetap menjadi opsi flag build CLI terpisah di luar konfigurasi Gradle ini.
4. **`tool/generate_voice.py:45` (`python:S4790`)**: Hash hanya memetakan metadata kalimat menjadi nama file 16-hex pada `assets/voice/<hash>.mp3` dan `assets/voice/manifest.json` (861 aset suara offline ElevenLabs sudah terbundel di repositori). Mengubah algoritma ke SHA-256 akan mengubah seluruh 861 kunci pada `manifest.json` tanpa perubahan fungsional dan berisiko memutus cache/diff biner masif. Oleh karena itu, dipanggil `hashlib.sha1(..., usedforsecurity=False)` yang didukung Python >= 3.9 dan dikenali oleh penganalisis Python modern untuk penggunaan non-kriptografis. *Catatan verifikasi*: jika SonarQube Cloud versi aturan tertentu tetap menandai `python:S4790` pasca-push, opsi tindak lanjut yang aman adalah migrasi serentak `manifest.json` + rename 861 file `.mp3` ke prefiks SHA-256.
5. **`tool/generate_voice.py:133, 135, 225, 231` (`pythonsecurity:S8707`)**: `--catalog` dan `--out` sebelumnya diteruskan langsung ke `open()`, `os.makedirs()`, `os.path.join()`, dan `os.remove()`. Ditambahkan `resolve_workspace_path()` (`Path.resolve()` + `is_relative_to()` terhadap `os.getcwd()` dan target junction `build/`), serta `resolve_output_file()` dengan regex ketat `^[a-f0-9]{16}\.mp3$` sebelum baca/tulis/hapus file clip maupun `manifest.json`.
6. **`backend/src/config/env.ts:266, 363` (`typescript:S8786`)**: Pola `/\/+$/` diganti helper `stripTrailingSlashes(value)` dengan loop `O(n)` berbasis `charCodeAt(end - 1) === 47` (`'/'`), nol regex backtracking.
7. **`backend/src/controllers/v2_controller.ts:16` (`typescript:S8786`)**: Pola `.replace(/\..+$/, '')` pada ISO timestamp diganti slicing linear berdasarkan `iso.indexOf('.')`, mempertahankan format filename `kogo-<kind>-YYYYMMDD-HHMMSS.csv`.
8. **`backend/src/services/auth_service.ts` (`typescript:S7737`)**: `credentials` diubah menjadi parameter opsional `credentials?: { username?: string; password?: string }` dengan destructuring fallback `{ username = config.auth.adminUsername, password = config.auth.adminPassword } = credentials ?? {}`. Proses bootstrap admin tetap identik.
9. **`backend/src/services/curriculum_service.ts` (`typescript:S7773`)**: Tiga pemanggilan `parseInt(..., 10)` diubah menjadi `Number.parseInt(..., 10)`.
10. **`backend/src/test/helpers/http.ts` (`typescript:S7737`)**: Parameter default object literal di `testPrincipals` dan `rawToken` diubah menjadi parameter opsional dengan fallback internal (`overrides?.users ?? {}` dan `DEFAULT_RAW_TOKEN_OPTIONS`), menjaga kompatibilitas seluruh helper JWT test.
11. **`backend/src/types/schemas.ts` (`typescript:S6324`)**: `NO_NUL = /^[^\u0000]*$/` dihapus dan diganti Zod `.refine((value) => !value.includes('\u0000'), 'must not contain NUL (U+0000) characters')`. Penolakan karakter NUL (`U+0000`) sebelum menyentuh PostgreSQL (`22021`) tetap identik.
12. **`web/index.html:2` (`Web:S5254`)**: Elemen akar diubah menjadi `<html lang="id">` sesuai bahasa antarmuka aplikasi.
13. **`backend/Dockerfile` (`docker:S6505`)**: `npm ci` diaudit terhadap dependensi di `backend/package.json`. Satu-satunya dependensi dengan skrip install adalah `bcrypt@6.0.0` (`install: node-gyp-build`), yang sudah menyertakan prebuilt N-API binary di `prebuilds/linux-{x64,arm64,arm}/bcrypt.{glibc,musl}.node`, serta `npm run build` memakai `tsc` (bukan `esbuild`/`tsx`). Penambahan `--ignore-scripts` pada kedua stage (`build` dan `runtime`) aman dilakukan dan sudah diverifikasi bahwa binding prebuilt `bcrypt` bekerja (`bcrypt_ok=true`).
14. **`backend/src/test/helpers/db.ts` (`typescript:S2245`)**: `Math.random().toString(36).slice(2, 10)` diganti `crypto.randomBytes(4).toString('hex')` agar tidak menggunakan PRNG non-kriptografis.
15. **`android/app/src/main/AndroidManifest.xml` & `network_security_config.xml` (`xml:S5332`)**: Atribut `android:usesCleartextTraffic="false"` ditambahkan pada `<application>` di `src/main/AndroidManifest.xml` untuk memenuhi aturan `xml:S5332`, dan `network_security_config.xml` di `main` hanya menetapkan `<base-config cleartextTrafficPermitted="false" />`. Konfigurasi debug dipisahkan ke `android/app/src/debug/res/xml/network_security_config.xml` (di Android API >= 24, `networkSecurityConfig` mengambil prioritas di atas `usesCleartextTraffic`) sehingga APK debug tetap dapat berkomunikasi dengan `127.0.0.1`, `localhost`, dan `10.0.2.2`, sementara APK release hanya mengizinkan HTTPS (`https://be-kogo.taro.web.id/api`).
16. **`backend/docker/postgres/Dockerfile` (`docker:S6471`)**: **Dipertahankan tanpa perubahan `USER`**. Image resmi `postgres:16-alpine` memang berjalan sebagai `root` pada fase entrypoint awal untuk inisialisasi kepemilikan direktori `/var/lib/postgresql/data` serta mengeksekusi `10-kogo-app-role.sh`, lalu menurunkan hak akses ke user `postgres` melalui `su-exec` sebelum daemon PostgreSQL menerima koneksi. Memaksa `USER postgres` di Dockerfile tanpa mengubah tata kelola volume akan berisiko menggagalkan bind-mount/volume init di Coolify/Docker Compose.

---

## 5. Daftar File dan Perubahan Kode

| File | Jenis Perubahan | Ringkasan |
|---|---|---|
| `backend/src/services/reference_data_service.ts` | Dimodifikasi | Tambah comparator `(a, b) => a.localeCompare(b)` pada `.sort()`. |
| `backend/src/services/tts_cache.ts` | Dimodifikasi | Tambah comparator `(a, b) => a.localeCompare(b, 'en')` pada `.sort()`. |
| `backend/src/config/env.ts` | Dimodifikasi | Tambah helper `stripTrailingSlashes()` O(n), ganti `.replace(/\/+$/, '')`. |
| `backend/src/controllers/v2_controller.ts` | Dimodifikasi | Ekspor `csvFilename(kind, now)` bebas regex `/\..+$/`. |
| `backend/src/services/auth_service.ts` | Dimodifikasi | Ubah parameter `credentials` di `ensureAdminUser()` menjadi opsional tanpa object literal default. |
| `backend/src/services/curriculum_service.ts` | Dimodifikasi | Ganti `parseInt(..., 10)` ke `Number.parseInt(..., 10)`. |
| `backend/src/test/helpers/http.ts` | Dimodifikasi | Hilangkan object literal pada default parameter `testPrincipals` dan `rawToken`. |
| `backend/src/test/helpers/db.ts` | Dimodifikasi | Ganti `Math.random()` ke `crypto.randomBytes(4).toString('hex')`. |
| `backend/src/types/schemas.ts` | Dimodifikasi | Ganti regex `NO_NUL` ke `.refine((value) => !value.includes('\u0000'), ...)`. |
| `backend/Dockerfile` | Dimodifikasi | Tambah `--ignore-scripts` pada kedua perintah `npm ci`. |
| `backend/src/test/unit/voice.test.ts` | Dimodifikasi (Test) | Tambah verifikasi determinisme urutan properti settings dan hash SHA-256 `ttsCacheKey`. |
| `backend/src/test/unit/config.test.ts` | Dimodifikasi (Test) | Tambah uji `stripTrailingSlashes` untuk `API_PREFIX` dan `ELEVENLABS_BASE_URL` panjang. |
| `backend/src/test/unit/csv.test.ts` | Dimodifikasi (Test) | Tambah uji format deterministik `csvFilename()`. |
| `backend/src/test/unit/auth_tokens.test.ts` | Dimodifikasi (Test) | Tambah uji `ensureAdminUser()` mode `skipped` dan `created` dengan mock `PoolClient`. |
| `android/app/build.gradle.kts` | Dimodifikasi | Aktifkan `isMinifyEnabled = true`, `isShrinkResources = true`, dan `proguardFiles`. |
| `android/app/proguard-rules.pro` | Dibuat | Aturan keep Flutter/plugin + `-dontwarn` kelas Play Core deferred components opsional. |
| `android/app/src/main/AndroidManifest.xml` | Dimodifikasi | Tambah `android:usesCleartextTraffic="false"` pada `<application>` untuk release. |
| `android/app/src/main/res/xml/network_security_config.xml` | Dimodifikasi | Hapus pengecualian cleartext HTTP dari konfigurasi `main` (hanya HTTPS). |
| `android/app/src/debug/res/xml/network_security_config.xml` | Dibuat | Tempatkan pengecualian cleartext `127.0.0.1`, `localhost`, `10.0.2.2` khusus build debug. |
| `tool/generate_voice.py` | Dimodifikasi | Tambah `resolve_workspace_path()`, `resolve_output_file()`, validasi `CLIP_FILENAME_RE`, dan `usedforsecurity=False` pada SHA-1. |
| `tool/test_generate_voice.py` | Dibuat (Test) | 4 unit test keamanan path traversal dan konsistensi `manifest.json`. |
| `web/index.html` | Dimodifikasi | Tambah `lang="id"` pada tag `<html>`. |

---

## 6. Metode dan Bukti Pengujian Lokal

Seluruh log asli eksekusi tersimpan pada `docs/quality-testing/sonarqube/logs/`:

| Pemeriksaan | Perintah | Hasil Aktual | File Log |
|---|---|---|---|
| TypeScript Typecheck | `cd backend && npm run lint` (`tsc --noEmit`) | **Lulus** (exit code `0`) | `logs/backend_lint.log` |
| Backend Build | `cd backend && npm run build` | **Lulus** (exit code `0`) | `logs/backend_build.log` |
| Backend Unit Tests | `cd backend && npm test` | **Lulus: 93/93 passed** (90 eksisting + 3 unit test baru) | `logs/backend_unit_test.log` |
| Backend Integration Tests | `npm run test:integration` | **Belum Diverifikasi** (database test PostgreSQL `kogo_research_test` dan kredensial `TEST_DATABASE_URL` tidak dikonfigurasi pada sesi lokal) | — |
| Docker Build Image | `docker build ...` | **Belum Diverifikasi** (`docker` CLI/daemon tidak terpasang di Windows host) | — |
| Prebuilt `bcrypt` Node Check | `node -e "require('./backend/node_modules/bcrypt')..."` | **Lulus** (`bcrypt_ok=true`, prebuilds Linux `musl`/`glibc` `x64`/`arm64` terverifikasi ada) | — |
| Python Voice Generator Tests | `python -m unittest tool/test_generate_voice.py -v` & `--dry-run` | **Lulus: 4/4 passed** + dry-run `generate_voice.py` terhadap `build/voice_catalog` menghasilkan `catalog: 861 clips, to generate: 0 (0 characters)` | `logs/python_voice_test.log` |
| Voice Catalog Integrity | `dart run tool/voice_catalog.dart` vs `assets/voice/manifest.json` | **Lulus: 861/861 klip cocok**, tidak ada mismatch | — |
| Flutter Static Analysis | `flutter analyze` | **Lulus: No issues found** (exit code `0`) | `logs/flutter_analyze.log` |
| Flutter Unit & Widget Tests | `flutter test` | **Lulus: 79 passed, 2 skipped, 0 failed** | `logs/flutter_test.log` |
| Android APK Debug Build | `flutter build apk --debug` | **Lulus** (`build/app/outputs/flutter-apk/app-debug.apk`, `173,062,361` bytes; `packageDebugResources` memakai config cleartext lokal debug) | `logs/flutter_build_apk_debug.log` |
| Android APK Release Build | `flutter build apk --release` | **Lulus** (`build/app/outputs/flutter-apk/app-release.apk`, `66,458,648` bytes / `63.4MB`; R8 minification & resource shrinking sukses; `packageReleaseResources` enforce `cleartextTrafficPermitted="false"`) | `logs/flutter_build_apk_release.log` |
| APK Smoke Test di Perangkat/Emulator | — | **Belum Diverifikasi** (tidak ada perangkat Android fisik/emulator aktif terhubung pada `adb devices`) | — |
| SonarQube Cloud Post-Fix Scan | — | **Belum Diverifikasi** (branch `fix/sonarqube-remediation` belum di-push karena menunggu persetujuan pengguna) | — |

---

## 7. Status Hasil SonarQube Cloud & Issue Tersisa

- **Rating Security, Reliability, Maintainability, Dependency Risks pasca-perbaikan**: **Belum Diverifikasi** di SonarQube Cloud hingga pengguna menyetujui commit dan push branch `fix/sonarqube-remediation`.
- **Issue yang berpotensi tetap muncul / memerlukan keputusan lanjutan setelah push**:
  1. `backend/docker/postgres/Dockerfile` (`docker:S6471`): Sengaja tidak diubah demi menjaga kompatibilitas inisialisasi volume PostgreSQL resmi.
  2. `tool/generate_voice.py` (`python:S4790`): Sudah diberi `usedforsecurity=False`; apabila profil SonarCloud tetap menandai `SHA-1`, dapat dilanjutkan dengan migrasi hash nama file ke SHA-256 beserta pembaruan 861 file `.mp3` di `assets/voice/`.
  3. `android/app/build.gradle.kts`: R8 + `isMinifyEnabled` + `isShrinkResources` aktif di level Android Gradle. Bila aturan SonarQube memeriksa obfuscation Dart, build rilis produksi dapat menambahkan flag `--obfuscate --split-debug-info=build/symbols`.

---

## 8. Kesimpulan Teknis Aspek Supportability (FURPS+)

Berdasarkan standar kualitas **FURPS+** pada dimensi **Supportability** (*testability, maintainability, configurability, compatibility, installability*):
1. **Maintainability & Reliability**: Penghapusan regex berisiko ReDoS (`env.ts`, `v2_controller.ts`), penertiban comparator pengurutan (`reference_data_service.ts`, `tts_cache.ts`), penghapusan control character di regex (`schemas.ts`), serta peniadaan object literal default pada parameter fungsi (`auth_service.ts`, `http.ts`) mengurangi bug terselubung lintas locale maupun input ekstrem tanpa mengubah kontrak REST API atau skema PostgreSQL.
2. **Security & Compatibility**: Pemisahan `network_security_config.xml` antara source set `main` (HTTPS-only) dan `debug` (localhost/emulator), aktivasi R8/ProGuard release pada `minSdk = 26`, serta sanitasi argumen path di `tool/generate_voice.py` memperkuat postur keamanan sambil mempertahankan seluruh fitur STT, TTS, 861 klip ElevenLabs, permainan edukasi, autentikasi JWT, dan sinkronisasi offline-first.
3. **Testability**: Penambahan 3 skenario regresi unit test Node.js (`config.test.ts`, `csv.test.ts`, `auth_tokens.test.ts`, serta asersi hash di `voice.test.ts`) dan 4 unit test keamanan Python (`tool/test_generate_voice.py`) memastikan setiap perbaikan memiliki bukti uji otomatis yang dapat dijalankan ulang secara deterministik.
