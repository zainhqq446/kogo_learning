# Kogo Voice Learning — Dokumentasi Lengkap Endpoint API Backend

Dokumentasi ini mencakup seluruh endpoint REST API backend Express.js + TypeScript (`D:\KogoBackend`) untuk aplikasi mobile **Kogo Voice Learning**, yang terhubung dengan basis data **PostgreSQL** (`kogo_research`).

---

## 1. Ikhtisar Arsitektur & Konvensi Umum

- **Base URL Pengembangan**: `http://127.0.0.1:4000/api` (Desktop / Web) atau `http://10.0.2.2:4000/api` (Android Emulator)
- **Content-Type**: `application/json` (Kecuali binary audio stream pada TTS/STT)
- **Format Tanggal/Waktu**: ISO 8601 UTC (`YYYY-MM-DDTHH:mm:ss.sssZ`)
- **Format UUID**: UUIDv4 (`xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`)
- **Format Respons Standar**:
  ```json
  {
    "status": "success",
    "message": "Deskripsi singkat hasil (opsional)",
    "data": { ... }
  }
  ```
- **Format Error Standar**:
  ```json
  {
    "status": "fail" | "error",
    "message": "Pesan deskriptif kesalahan",
    "errors": [ ... ]
  }
  ```

---

## 2. Autentikasi & Otorisasi

Sebagian besar rute riset (`/api/research/*`) dan endpoint status diproteksi menggunakan **JSON Web Token (JWT) Bearer Token**.

Header wajib:
```http
Authorization: Bearer <ACCESS_TOKEN>
```

Tiga tingkatan peran pengguna (*roles*):
1. `admin`: Hak akses penuh ke seluruh rute dan data.
2. `researcher`: Mendaftarkan peserta, mencatat & meninjau data sesi riset, ekspor summary, dan batch sync.
3. `teacher`: Melihat data peserta, mendaftarkan perangkat, dan menyinkronkan data percobaan anak.

---

## 3. Daftar Lengkap Endpoint

| Kategori | Metode | Endpoint | Autentikasi | Roles | Deskripsi Singkat |
| :--- | :---: | :--- | :---: | :---: | :--- |
| **Sistem** | `GET` | `/api/health` | Publik | Semua | Health check status server & koneksi database |
| **Auth** | `POST` | `/api/auth/register` | Publik | Semua | Pendaftaran akun peneliti / guru baru |
| **Auth** | `POST` | `/api/auth/login` | Publik | Semua | Login peneliti / guru dan penerbitan JWT token |
| **Auth** | `POST` | `/api/auth/logout` | Wajib | Semua | Mengakhiri sesi peneliti |
| **Auth** | `GET` | `/api/auth/me` | Wajib | Semua | Mengambil informasi akun yang sedang login |
| **Voice** | `GET` | `/api/voice/status` | Wajib | Semua | Status konfigurasi ElevenLabs TTS & STT proxy |
| **Voice** | `POST` | `/api/voice/tts` | Publik / Proxy | Semua | Sintesis suara ElevenLabs TTS (Audio MP3 stream) |
| **Voice** | `POST` | `/api/voice/stt` | Publik / Proxy | Semua | Transkripsi suara ElevenLabs STT (Audio binary / Base64) |
| **Riset** | `GET` | `/api/research/participants` | Wajib | admin, researcher, teacher | Mengambil daftar peserta anak (pseudonim) |
| **Riset** | `POST` | `/api/research/participants` | Wajib | admin, researcher | Mendaftarkan 1 peserta anak baru |
| **Riset** | `POST` | `/api/research/participants/batch` | Wajib | admin, researcher | Batch import peserta anak |
| **Riset** | `GET` | `/api/research/participants/:code` | Wajib | admin, researcher, teacher | Mengambil detail 1 peserta berdasarkan kode |
| **Riset** | `GET` | `/api/research/devices` | Wajib | admin, researcher | Daftar perangkat tablet/ponsel riset |
| **Riset** | `POST` | `/api/research/devices` | Wajib | admin, researcher, teacher | Pendaftaran / registrasi perangkat |
| **Riset** | `GET` | `/api/research/sessions` | Wajib | admin, researcher, teacher | Daftar riwayat sesi penelitian |
| **Riset** | `POST` | `/api/research/sessions` | Wajib | admin, researcher, teacher | Membuat sesi penelitian baru |
| **Riset** | `GET` | `/api/research/attempts` | Wajib | admin, researcher | Daftar riwayat percobaan suara & log evaluasi |
| **Riset** | `POST` | `/api/research/attempts` | Wajib | admin, researcher, teacher | Mencatat percobaan suara individual |
| **Riset** | `GET` | `/api/research/summary` | Wajib | admin, researcher | Statistik agregat penelitian (akurasi, status, dsb) |
| **Sync** | `POST` | `/api/research/sync/batch` | Wajib | admin, researcher, teacher | Sinkronisasi batch tumpukan data offline ke PostgreSQL |

---

## 4. Rincian Spesifikasi Setiap Endpoint

### 4.1 Health Check

#### `GET /api/health`
Mengembalikan status kesiapan server backend dan koneksi pool PostgreSQL.

- **Headers**: Tidak ada
- **Response `200 OK`**:
```json
{
  "status": "healthy",
  "timestamp": "2026-10-20T21:00:00.000Z",
  "uptime": 124.5,
  "database": "connected"
}
```

---

### 4.2 Otentikasi Peneliti / Guru

#### `POST /api/auth/register`
Mendaftarkan akun peneliti atau guru baru.

- **Request Body**:
```json
{
  "username": "dr_sarah",
  "password": "PasswordRiset2026!",
  "fullName": "Dr. Sarah Sp.A",
  "role": "researcher"
}
```
*Catatan:* `role` opsional, default `researcher`. Pilihan: `admin`, `researcher`, `teacher`.

- **Response `201 Created`**:
```json
{
  "status": "success",
  "message": "User registered successfully",
  "data": {
    "id": "e2a3c749-0158-4523-a178-83141f129a01",
    "username": "dr_sarah",
    "fullName": "Dr. Sarah Sp.A",
    "role": "researcher",
    "isActive": true,
    "createdAt": "2026-10-20T21:00:00.000Z"
  }
}
```

#### `POST /api/auth/login`
Mengautentikasi username dan password, mengembalikan JWT Bearer Token.

- **Request Body**:
```json
{
  "username": "dr_sarah",
  "password": "PasswordRiset2026!"
}
```

- **Response `200 OK`**:
```json
{
  "status": "success",
  "message": "Login successful",
  "data": {
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "user": {
      "id": "e2a3c749-0158-4523-a178-83141f129a01",
      "username": "dr_sarah",
      "fullName": "Dr. Sarah Sp.A",
      "role": "researcher"
    }
  }
}
```

#### `GET /api/auth/me`
Mengambil profil akun peneliti/guru berdasarkan access token aktif.

- **Headers**: `Authorization: Bearer <token>`
- **Response `200 OK`**:
```json
{
  "status": "success",
  "data": {
    "id": "e2a3c749-0158-4523-a178-83141f129a01",
    "username": "dr_sarah",
    "fullName": "Dr. Sarah Sp.A",
    "role": "researcher"
  }
}
```

---

### 4.3 Proxy Layanan Suara (ElevenLabs TTS & STT)

#### `POST /api/voice/tts` (Alias: `/api/voice/synthesize`)
Mengonversi teks ke audio suara ramah anak melalui ElevenLabs API di sisi server. Kunci API ElevenLabs tersimpan aman di backend (`.env`).

- **Headers**: `Content-Type: application/json`
- **Request Body**:
```json
{
  "text": "Hebat sekali! Ayo kita sebutkan kata bola!",
  "voiceId": "21m00Tcm4TlvDq8ikWAM",
  "modelId": "eleven_multilingual_v2",
  "settings": {
    "stability": 0.5,
    "similarityBoost": 0.75,
    "speed": 1.0
  }
}
```
- **Response `200 OK`**:
  - `Content-Type: audio/mpeg`
  - Body: Stream biner audio MP3.

#### `POST /api/voice/stt` (Alias: `/api/voice/transcribe`)
Mentranskripsikan audio rekaman ucapan anak ke teks via model pengenal wicara.

- **Headers**:
  - `Content-Type: audio/wav` (Bila mengirim raw binary)
  - ATAU `Content-Type: application/json` (Bila mengirim base64)
- **JSON Request Body (Opsi Base64)**:
```json
{
  "audioBase64": "UklGRiQAAABXQVZFZm10IBAAAAABAAEA...",
  "mimeType": "audio/wav",
  "languageCode": "id"
}
```
- **Response `200 OK`**:
```json
{
  "status": "success",
  "data": {
    "text": "BOLA",
    "languageCode": "id",
    "durationSecs": 1.25
  }
}
```

---

### 4.4 Manajemen Peserta Riset (Pseudonim Anak)

#### `GET /api/research/participants`
Mengambil seluruh peserta riset anak dengan identitas samaran (pseudonim).

- **Headers**: `Authorization: Bearer <token>`
- **Response `200 OK`**:
```json
{
  "status": "success",
  "count": 40,
  "data": [
    {
      "id": "b3e0c0d2-9659-4d64-8395-9273c54c3001",
      "participant_code": "P001",
      "display_alias": "Bintang",
      "age_years": 6,
      "gender": "M",
      "is_active": true,
      "created_at": "2026-10-20T10:00:00.000Z"
    }
  ]
}
```

#### `POST /api/research/participants`
Mendaftarkan 1 peserta riset baru.

- **Request Body**:
```json
{
  "participantCode": "P041",
  "displayAlias": "Awan",
  "ageYears": 5,
  "gender": "M",
  "pin": "1234"
}
```
- **Response `201 Created`**:
```json
{
  "status": "success",
  "message": "Participant created successfully",
  "data": {
    "id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
    "participant_code": "P041",
    "display_alias": "Awan",
    "age_years": 5,
    "gender": "M",
    "is_active": true
  }
}
```

---

### 4.5 Pendaftaran Perangkat (Devices)

#### `POST /api/research/devices`
Mendaftarkan perangkat tablet/ponsel yang digunakan anak untuk latihan.

- **Request Body**:
```json
{
  "deviceIdentifier": "TAB-LAB-01",
  "deviceLabel": "Samsung Galaxy Tab A9 Lab 1",
  "platform": "android",
  "appVersion": "1.0.0"
}
```
*Platform yang didukung:* `android`, `ios`, `windows`, `macos`, `linux`.

- **Response `200 OK` / `201 Created`**:
```json
{
  "status": "success",
  "message": "Device registered successfully",
  "data": {
    "id": "c1f7a4e8-8b92-491b-944d-16a2476b7e12",
    "device_identifier": "TAB-LAB-01",
    "device_label": "Samsung Galaxy Tab A9 Lab 1",
    "platform": "android",
    "app_version": "1.0.0"
  }
}
```

---

### 4.6 Sinkronisasi Otomatis Batch (`POST /api/research/sync/batch`)

Endpoint utama yang digunakan oleh `SyncService` Flutter untuk mengunggah tumpukan data offline saat aplikasi online. Bersifat **idempoten** berdasarkan `clientSessionUuid` dan `clientAttemptUuid`.

- **Headers**:
  ```http
  Authorization: Bearer <token>
  Content-Type: application/json
  ```

- **Request Body**:
```json
{
  "sessions": [
    {
      "clientSessionUuid": "550e8400-e29b-41d4-a716-446655440000",
      "participantCode": "P001",
      "deviceIdentifier": "TAB-LAB-01",
      "sessionSequenceNumber": 1,
      "startedAt": "2026-10-20T08:00:00.000Z",
      "endedAt": "2026-10-20T08:15:00.000Z",
      "notes": "Sesi pengujian modul vokal & konsonan"
    }
  ],
  "attempts": [
    {
      "clientAttemptUuid": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
      "clientSessionUuid": "550e8400-e29b-41d4-a716-446655440000",
      "participantCode": "P001",
      "deviceIdentifier": "TAB-LAB-01",
      "questionId": 1,
      "attemptNumber": 1,
      "targetText": "MATA",
      "recognizedText": "MATA",
      "asrProvider": "whisper_onnx",
      "locale": "id_ID",
      "asrConfidence": 0.98,
      "durationMs": 450,
      "attemptedAt": "2026-10-20T08:02:15.000Z",
      "evaluation": {
        "normalizedTarget": "mata",
        "normalizedRecognized": "mata",
        "editDistance": 0,
        "similarityScore": 1.0,
        "similarityPercent": 100.0,
        "isCorrect": true,
        "evaluationStatus": "EXACT_MATCH",
        "thresholdUsed": 1.0,
        "evaluationMethod": "levenshtein_normalized_v1",
        "feedbackText": "Hebat!"
      }
    }
  ]
}
```

- **Response `200 OK`**:
```json
{
  "status": "success",
  "message": "Batch synchronization completed",
  "data": {
    "sessions": [
      {
        "clientSessionUuid": "550e8400-e29b-41d4-a716-446655440000",
        "status": "created"
      }
    ],
    "attempts": [
      {
        "clientAttemptUuid": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
        "status": "created"
      }
    ],
    "summary": {
      "totalSessions": 1,
      "syncedSessions": 1,
      "totalAttempts": 1,
      "syncedAttempts": 1,
      "failedItems": 0
    }
  }
}
```

---

### 4.7 Agregasi Ringkasan Riset (`GET /api/research/summary`)

Mengembalikan metrik statistik penelitian untuk dashboard visualisasi peneliti.

- **Headers**: `Authorization: Bearer <token>`
- **Response `200 OK`**:
```json
{
  "status": "success",
  "data": {
    "total_participants": 40,
    "total_sessions": 85,
    "total_attempts": 420,
    "avg_similarity_score": 0.8842,
    "avg_similarity_percent": 88.42,
    "accuracy_rate_percent": 82.50,
    "exact_matches": 310,
    "accepted_similar": 36,
    "incorrect_attempts": 60,
    "unrecognized_attempts": 14
  }
}
```

---

## 5. Contoh Perintah cURL untuk Pengujian Manual

### 1. Registrasi Akun Peneliti
```bash
curl -X POST http://127.0.0.1:4000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"dr_andi","password":"PasswordRiset123!","fullName":"Dr. Andi","role":"researcher"}'
```

### 2. Login & Mendapatkan Token
```bash
curl -X POST http://127.0.0.1:4000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"dr_andi","password":"PasswordRiset123!"}'
```

### 3. Menguji Proxy TTS ElevenLabs
```bash
curl -X POST http://127.0.0.1:4000/api/voice/tts \
  -H "Content-Type: application/json" \
  -d '{"text":"Ayo kita belajar membaca bersama Kogo!"}' \
  --output instruksi_kogo.mp3
```

### 4. Menjalankan Batch Sync
```bash
curl -X POST http://127.0.0.1:4000/api/research/sync/batch \
  -H "Authorization: Bearer <JWT_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "sessions": [],
    "attempts": []
  }'
```
