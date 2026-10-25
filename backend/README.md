# Kogo Voice Learning — Backend Foundation

Fondasi backend produksi untuk aplikasi **Kogo Voice Learning** (Platform pembelajaran pengenalan kata anak usia dini dan pengumpulan data penelitian).

---

## 1. Prasyarat Sistem

- **Node.js**: LTS versi 20.x atau 22.x+ (teruji pada Node v24.16.0).
- **NPM**: Versi 10.x atau 11.x+.
- **PostgreSQL**: Versi 15 atau 16+ (Opsional saat tahap awal pengembangan; backend menggunakan pengecekan koneksi *lazy-check* sehingga server tetap dapat berjalan untuk testing/mocking meskipun database belum aktif).

---

## 2. Struktur Direktori

```text
D:\KogoBackend\
├── src\
│   ├── config\             # Konfigurasi environment (env.ts) & pool PostgreSQL (database.ts)
│   ├── controllers\        # Handler endpoint (health_controller.ts)
│   ├── middlewares\        # Error handling, 404, Zod validation
│   ├── routes\             # Definisi router Express (health_routes.ts)
│   ├── services\           # Business logic layer (untuk fase berikutnya)
│   ├── test\               # Test suite mandiri (node:test & assert)
│   ├── types\              # Error classes & model interface
│   ├── utils\              # Logger aman (anti bocor token/rahasia)
│   ├── app.ts              # Konfigurasi aplikasi Express & middleware
│   └── index.ts            # Entrypoint server & graceful shutdown
├── dist\                   # Hasil kompilasi TypeScript
├── .env.example            # Template variabel lingkungan (bebas rahasia)
├── .gitignore              # Daftar pengabaian git
├── package.json            # Dependensi dan skrip proyek
├── tsconfig.json           # Konfigurasi TypeScript
└── README.md               # Dokumentasi instalasi dan penggunaan
```

---

## 3. Instalasi dan Setup

1. Buka terminal PowerShell di folder backend:
   ```powershell
   cd D:\KogoBackend
   ```

2. Instal dependensi:
   ```powershell
   npm install
   ```

3. Salin konfigurasi environment dari template:
   ```powershell
   copy .env.example .env
   ```

4. Sesuaikan variabel pada file `.env` jika PostgreSQL lokal sudah terpasang.

---

## 4. Cara Menjalankan

### Mode Pengembangan (Live Reload)
```powershell
npm run dev
```

### Mode Kompilasi & Produksi
```powershell
# 1. Kompilasi TypeScript ke folder dist/
npm run build

# 2. Jalankan bundle produksi
npm run start
```

---

## 5. Cara Menguji Endpoint

### Jalankan Automated Test Suite
Backend dilengkapi test suite menggunakan modul bawaan `node:test`:
```powershell
# Menjalankan pengujian TypeScript langsung via tsx
npm run test:ts

# Atau uji setelah build
npm run test
```

### Uji Manual via cURL / PowerShell

- **Pemeriksaan Health Endpoint:**
  ```powershell
  Invoke-RestMethod -Uri "http://localhost:4000/api/health" -Method Get | ConvertTo-Json -Depth 5
  ```

  Contoh respons jika PostgreSQL belum dinyalakan (server tetap aman, status 200 OK):
  ```json
  {
    "status": "ok",
    "timestamp": "2026-10-14T14:55:00.000Z",
    "uptimeSeconds": 12,
    "environment": "development",
    "service": "kogo-voice-learning-backend",
    "version": "1.0.0",
    "database": {
      "provider": "postgresql",
      "connected": false,
      "latencyMs": null,
      "status": "disconnected (lazy check - not blocking)",
      "message": "connect ECONNREFUSED 127.0.0.1:5432"
    }
  }
  ```

- **Uji Route Tidak Dikenal (404 Error Handler):**
  ```powershell
  Invoke-RestMethod -Uri "http://localhost:4000/api/non-existent" -Method Get
  ```

---

## 6. Standar Keamanan & Perlindungan Data Anak

- **Zero PII Leakage**: Logger pada `src/utils/logger.ts` secara otomatis menyensor kata kunci sensitif (`password`, `pin`, `token`, `secret`, `api_key`, `bearer`).
- **No Hardcoded Secrets**: Kredensial ElevenLabs dan JWT tidak disimpan di dalam source code, melainkan melalui environment variables server backend.
- **Lazy PostgreSQL Connection**: Koneksi basis data tidak memblokir atau mematikan proses saat server dihidupkan, mencegah restart-loop jika database sedang maintenance.
- **CORS Protection**: Dibungkus secara ketat berdasarkan konfigurasi `CORS_ORIGIN` di `.env`.

---

## 7. Troubleshooting

1. **Port 4000 sudah terpakai (`EADDRINUSE`)**:
   Ubah variabel `PORT=4001` pada file `.env`.
2. **Koneksi database gagal (`ECONNREFUSED`)**:
   Pastikan PostgreSQL service aktif pada sistem Anda. Jika belum terpasang, backend tetap dapat digunakan untuk pengujian endpoint lainnya.

---

## 8. Manajemen Database & Migrasi

Backend dilengkapi runner migrasi mandiri berbasis transaksi atomik dan pelacak tabel `schema_migrations`.

### Memeriksa Koneksi Database
Jalankan perintah berikut untuk menguji konektivitas ke PostgreSQL tanpa membocorkan password:
```powershell
npm run db:check
```

### Menjalankan Migrasi Skema
Untuk mengaplikasikan seluruh file SQL yang ada pada folder `migrations/` ke PostgreSQL:
```powershell
npm run db:migrate
```

### Daftar File Migrasi:
1. `migrations/001_create_kogo_research_schema.sql`:
   - Inisialisasi ekstensi `uuid-ossp`.
   - Entitas: `users`, `participants` (pseudonim tanpa PII), `devices`, `stages`, `lessons`, `questions`, `research_sessions`, `speech_attempts`, `similarity_evaluations`, dan `audit_logs`.
   - DDL bersifat idempoten dengan `IF NOT EXISTS` dan indeks teroptimasi.
---

## 9. Dokumentasi API Autentikasi & Penelitian

Seluruh endpoint penelitian terproteksi dengan JSON Web Token (JWT) pada header `Authorization: Bearer <token>` dan otorisasi berbasis peran (RBAC: `admin`, `researcher`, `teacher`).

### A. Autentikasi (`/api/auth`)

| Method | Endpoint | Akses | Deskripsi |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/auth/register` | Publik / Admin | Mendaftarkan akun peneliti/guru baru dengan bcrypt hash (min 8 karakter) |
| `POST` | `/api/auth/login` | Publik | Login dengan `username` dan `password`, menghasilkan access token (15m) & refresh token (7d) |
| `GET` | `/api/auth/me` | Bearer Token | Mengambil profil user yang sedang aktif |
| `POST` | `/api/auth/logout` | Bearer Token | Mengakhiri sesi (stateless invalidation) |

### B. Penelitian & Sesi Belajar (`/api/research`)

| Method | Endpoint | Akses (Role) | Deskripsi |
| :--- | :--- | :--- | :--- |
| `GET` | `/api/research/participants` | `admin`, `researcher`, `teacher` | Daftar peserta penelitian (hanya kode pseudonim, bebas PII) |
| `POST` | `/api/research/participants` | `admin`, `researcher` | Mendaftarkan peserta anak baru dengan kode pseudonim (misal: `P001`) dan PIN 4 digit |
| `GET` | `/api/research/participants/:code` | `admin`, `researcher`, `teacher` | Detail peserta berdasarkan kode |
| `GET` | `/api/research/devices` | `admin`, `researcher` | Daftar perangkat mobile yang terdaftar |
| `POST` | `/api/research/devices` | `admin`, `researcher`, `teacher` | Registrasi / heartbeat perangkat |
| `GET` | `/api/research/sessions` | `admin`, `researcher`, `teacher` | Riwayat sesi pembelajaran dan penelitian |
| `POST` | `/api/research/sessions` | `admin`, `researcher`, `teacher` | Merekam sesi penelitian secara idempoten via `clientSessionUuid` |
| `GET` | `/api/research/attempts` | `admin`, `researcher` | Riwayat percobaan suara anak beserta skor evaluasi Levenshtein |
| `POST` | `/api/research/attempts` | `admin`, `researcher`, `teacher` | Merekam percobaan ucapan anak dan evaluasi kemiripan secara idempoten |
| `GET` | `/api/research/summary` | `admin`, `researcher` | Agregasi statistik penelitian (total peserta, sesi, akurasi, rerata kemiripan vokal) |