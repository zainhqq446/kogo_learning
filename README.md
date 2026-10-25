# Kogo Learning Platform

Repositori resmi untuk proyek pembelajaran kata berbasis suara anak usia dini (PAUD) **Kogo Voice Learning** dan layanan sinkronisasi data penelitian **Kogo Backend**.

---

## 📁 Struktur Monorepo Proyek

Repositori ini memisahkan secara modular antara aplikasi mobile klien (*frontend*) dan layanan server (*backend*):

```text
kogo_learning/
├── backend/                  # RESTful API, PostgreSQL Migrations, Telemetri Penelitian & Proxy Suara
│   ├── migrations/           # Skrip migrasi skema database PostgreSQL
│   ├── src/                  # Kode sumber TypeScript (Express, Controllers, Services)
│   ├── .env.example          # Template environment variable backend
│   ├── package.json          # Manajemen dependensi backend
│   └── README.md             # Dokumentasi teknis & endpoint API lengkap
├── kogo/                     # Aplikasi Mobile Pembelajaran PAUD (Flutter)
│   ├── assets/               # Gambar (450 kata/gambar), Model Phoneme Whisper, Audio SFX & Voice
│   ├── lib/                  # Arsitektur Flutter (Clean Architecture, Riverpod, SQLite Offline-first)
│   ├── test/                 # Test suites (Activity, Stage Locking, Navigation, Audio, DB)
│   └── pubspec.yaml          # Spesifikasi paket & aset Flutter
└── README.md                 # Petunjuk utama repositori & dokumentasi API
```

---

## 🚀 Panduan Memulai Cepat

### 1. Backend Service (`backend/`)

Backend berbasis Node.js & TypeScript untuk mengelola autentikasi, proksifikasi suara TTS/STT, serta sinkronisasi data offline-to-online.

```bash
# Masuk ke direktori backend
cd backend

# Instal dependensi
npm install

# Setup environment
cp .env.example .env

# Jalankan dalam mode pengembangan
npm run dev
```

### 2. Mobile App Client (`kogo/`)

Aplikasi Flutter multi-platform untuk anak usia dini dengan pengenalan suara offline (Whisper lokal) dan suara interaktif Kogo.

```bash
# Masuk ke direktori frontend kogo
cd kogo

# Ambil paket dependensi
flutter pub get

# Jalankan unit & widget test
flutter test

# Jalankan aplikasi ke perangkat / emulator
flutter run
```

---

## 🌐 Dokumentasi API Backend (`backend`)

Backend berjalan secara default pada port `4000` (Base URL: `http://localhost:4000/api`).

### 1. Health & Server Status
| Method | Endpoint | Auth | Deskripsi |
| :--- | :--- | :--- | :--- |
| `GET` | `/api/health` | Public | Pengecekan status server, uptime, dan status koneksi database PostgreSQL (non-blocking). |

### 2. Autentikasi Pengguna & Peneliti (`/api/auth`)
| Method | Endpoint | Auth | Deskripsi |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/auth/register` | Public | Pendaftaran akun peneliti/guru baru. |
| `POST` | `/api/auth/register/child` | Public | Pendaftaran profil anak (kode anak, PIN, grup usia). |
| `POST` | `/api/auth/login` | Public | Login akun untuk memperoleh JWT Bearer token. |
| `POST` | `/api/auth/logout` | Bearer Token | Logout dan invalidasi sesi token. |
| `GET` | `/api/auth/me` | Bearer Token | Mengambil data profil dan role pengguna aktif. |

### 3. Voice Proxy & Speech Service (`/api/voice`)
Endpoint proksi suara aman untuk mencegah kebocoran kredensial API key suara pada sisi klien.
| Method | Endpoint | Auth | Deskripsi |
| :--- | :--- | :--- | :--- |
| `GET` | `/api/voice/status` | Bearer Token | Cek status ketersediaan provider suara (ElevenLabs / Whisper). |
| `POST` | `/api/voice/tts` | Public / Bearer | Sintesis teks ke audio suara Kogo yang ramah anak. |
| `POST` | `/api/voice/synthesize` | Public / Bearer | Alias endpoint untuk sintesis suara TTS ElevenLabs. |
| `POST` | `/api/voice/stt` | Public / Bearer | Transkripsi audio ucapan anak menjadi teks. |
| `POST` | `/api/voice/transcribe` | Public / Bearer | Alias endpoint untuk transkripsi audio STT. |

### 4. Data Penelitian & Telemetri PAUD (`/api/...`)
Seluruh endpoint penelitian dilindungi verifikasi JWT Bearer Token dengan otorisasi berbasis peran (`admin`, `researcher`, `teacher`).
| Method | Endpoint | Role | Deskripsi |
| :--- | :--- | :--- | :--- |
| `GET` | `/api/participants` | admin, researcher, teacher | Mengambil daftar partisipan anak (kode pseudonim). |
| `POST` | `/api/participants` | admin, researcher | Mendaftarkan partisipan anak baru. |
| `POST` | `/api/participants/batch` | admin, researcher | Impor data batch partisipan penelitian. |
| `GET` | `/api/participants/:code` | admin, researcher, teacher | Mengambil detail riwayat & profil partisipan tertentu. |
| `GET` | `/api/devices` | admin, researcher | Mengambil daftar tablet/device yang terdaftar. |
| `POST` | `/api/devices` | admin, researcher, teacher | Mendaftarkan device ID tablet yang digunakan anak. |
| `GET` | `/api/sessions` | admin, researcher, teacher | Mengambil daftar sesi belajar yang telah dicatat. |
| `POST` | `/api/sessions` | admin, researcher, teacher | Membuat catatan sesi pembelajaran baru. |
| `GET` | `/api/attempts` | admin, researcher | Mengambil log rekaman suara & akurasi kemiripan fonem. |
| `POST` | `/api/attempts` | admin, researcher, teacher | Mencatat hasil pengucapan suara anak per kata. |
| `GET` | `/api/summary` | admin, researcher | Ringkasan agregasi metrik pengenalan suara penelitian. |
| `POST` | `/api/sync/batch` | admin, researcher, teacher | Sinkronisasi batch data sesi & progres offline dari SQLite ke PostgreSQL. |

---

## 🔒 Standar Keamanan & Perlindungan Privasi Anak
- **Zero PII Exposure**: Data anak diidentifikasi melalui pseudonim anonim (`participant_code`).
- **Sanitized Logging**: Kredensial, token, dan PIN secara otomatis disensor dari log server.
- **Offline-First Resilience**: Aplikasi mobile tetap berfungsi penuh tanpa koneksi internet dengan database SQLite lokal, dan melakukan sinkronisasi otomatis ketika terhubung kembali ke backend.

---

## 📄 Lisensi & Kontributor
Dikembangkan untuk pengujian interaksi suara dan edukasi anak usia dini (PAUD).
