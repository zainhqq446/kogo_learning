# Kogo Voice Learning — Panduan Deployment & Konfigurasi Hosting Server

Dokumen ini merupakan panduan komprehensif untuk penggelaran (deployment), konfigurasi lingkungan (environment), pemeliharaan database, serta integrasi Flutter dan Backend Express API untuk lingkungan produksi/staging.

---

## 1. Arsitektur & Topologi Jaringan

```
[ Mobile App (Flutter) ]
          │  (HTTPS / WSS)
          ▼
[ Reverse Proxy: NGINX / Cloudflare ]
  ├── SSL Termination (Certbot / Cloudflare Origin CA)
  ├── Rate Limiting (100 req/min general, 30 req/min /api/voice/*)
  ├── File Size Limit (client_max_body_size 15M)
  └── CORS Policy
          │  (Internal Network: 127.0.0.1:4000)
          ▼
[ Express + TypeScript Service (Node.js LTS / PM2) ]
  ├── Voice Proxy (/api/voice/tts, /api/voice/stt)
  ├── Research Data Sync (/api/research/sync/batch)
  ├── Curriculum Catalog (/api/curriculum/*)
  └── Auth & Session Handling
          │  (Unix Domain Socket / Private Subnet)
          ▼
[ PostgreSQL Database (kogo_research) ]
  ├── Tidak diekspos ke publik (listen_addresses = 'localhost')
  ├── Automatic WAL Archiving & Daily pg_dump
  └── Connection Pooling (max_connections = 100, pool = 20)
```

---

## 2. Environment Variables Backend

Buat file `.env` pada direktori backend (contoh: `/var/www/kogo-backend/.env`).

> **PENTING**: Jangan pernah commit file `.env` ke Git repository. Gunakan template `.env.example`.

```ini
# Node Server Configuration
PORT=4000
NODE_ENV=production
LOG_LEVEL=info

# PostgreSQL Database Configuration
DB_HOST=127.0.0.1
DB_PORT=5432
DB_NAME=kogo_research
DB_USER=kogo_user
DB_PASSWORD=<SECURE_STRONG_PASSWORD>

# JWT Authentication
JWT_SECRET=<MINIMUM_32_CHARACTERS_SECURE_RANDOM_SECRET>
JWT_EXPIRES_IN=7d

# ElevenLabs AI Integration (Server-Side Proxy)
# Kredensial provider disimpan hanya di backend (zero client leak)
ELEVENLABS_API_KEY=<ELEVENLABS_API_KEY_HERE>
ELEVENLABS_DEFAULT_VOICE_ID=pNInz6obpgDQGcFmaJgB
ELEVENLABS_MODEL_ID=eleven_multilingual_v2
ELEVENLABS_STT_MODEL_ID=scribe_v1

# Security & Rate Limiting
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_REQUESTS=100
MAX_AUDIO_UPLOAD_BYTES=10485760 # 10 MB limit
```

---

## 3. Konfigurasi URL API Flutter (Mobile Client)

Pada aplikasi Flutter, tidak boleh ada hardcoded URL IP lokal (LAN) untuk produksi:

1. Konfigurasi default di [backend_config.dart](file:///c:/Projects/kogo_voice_learning/lib/config/backend_config.dart):
   ```dart
   class BackendConfig {
     static const String baseUrl = String.fromEnvironment(
       'BACKEND_URL',
       defaultValue: 'https://api.kogolearning.id/api',
     );
   }
   ```
2. Build Android Release APK/Bundle:
   ```bash
   flutter build appbundle --release --dart-define=BACKEND_URL=https://api.kogolearning.id/api
   ```
3. Build iOS:
   ```bash
   flutter build ipa --release --dart-define=BACKEND_URL=https://api.kogolearning.id/api
   ```

---

## 4. Konfigurasi NGINX & SSL (Reverse Proxy)

Contoh blok konfigurasi NGINX (`/etc/nginx/sites-available/kogo-backend`):

```nginx
# Rate limiting zone untuk voice proxy
limit_req_zone $binary_remote_addr zone=voice_limit:10m rate=30r/m;
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=100r/m;

server {
    listen 80;
    server_name api.kogolearning.id;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name api.kogolearning.id;

    ssl_certificate /etc/letsencrypt/live/api.kogolearning.id/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.kogolearning.id/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    client_max_body_size 15M;

    # Voice Proxy Endpoint Rate Limiting & Proxying
    location /api/voice/ {
        limit_req zone=voice_limit burst=10 nodelay;
        proxy_pass http://127.0.0.1:4000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
    }

    # General API Endpoint
    location / {
        limit_req zone=api_limit burst=20 nodelay;
        proxy_pass http://127.0.0.1:4000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

---

## 5. Migrasi Database & Seeding Kurikulum

Jalankan perintah berikut di server backend untuk menerapkan skema lengkap dan konten 300 kata:

```bash
# 1. Masuk ke direktori backend
cd /var/www/kogo-backend

# 2. Pastikan dependensi terpasang
npm ci --production=false

# 3. Jalankan migrasi dan seeding kurikulum awal
npx tsx src/scripts/seed_curriculum.ts

# 4. Jalankan seeding 300 kata bergambar
npx tsx src/scripts/seed_300_words.ts

# 5. Build aplikasi TypeScript untuk produksi
npm run build
```

---

## 6. Manajemen Proses dengan PM2

Gunakan PM2 untuk menjaga proses backend tetap aktif:

```bash
# Inisialisasi proses produksi
pm2 start dist/server.js --name "kogo-backend" -i max --env production

# Simpan konfigurasi agar auto-restart saat reboot server
pm2 save
pm2 startup
```

---

## 7. Kebijakan Backup & Disaster Recovery PostgreSQL

### Backup Harian Otomatis (Cron Job)
Tambahkan ke crontab (`crontab -e`):
```bash
# Backup otomatis setiap jam 02:00 pagi
0 2 * * * pg_dump -U kogo_user -h 127.0.0.1 -Fc kogo_research > /var/backups/kogo/kogo_research_$(date +\%Y\%m\%d_\%H\%M\%S).dump
# Hapus backup yang lebih lama dari 14 hari
0 3 * * * find /var/backups/kogo/ -name "*.dump" -mtime +14 -delete
```

### Prosedur Pemulihan (Restore)
```bash
pg_restore -U kogo_user -h 127.0.0.1 -d kogo_research -c /var/backups/kogo/kogo_research_YYYYMMDD_HHMMSS.dump
```

---

## 8. Prinsip Perlindungan Data Anak & Keamanan

1. **Zero Secret Leakage**:
   - API Key ElevenLabs dan token akses penyedia kecerdasan buatan hanya disimpan di `.env` server backend.
   - Klien Flutter tidak pernah memiliki akses atau menyimpan key ElevenLabs.
2. **Minimisasi Data (PII Free)**:
   - Identitas anak hanya menggunakan alias/pseudonim (misal: `P001`, `Anak 1`).
   - Tidak ada rekaman audio mentah yang disimpan permanen di database penelitian kecuali jika disetujui dalam protokol penelitian.
3. **Audit Log & Observability**:
   - Setiap sinkronisasi sesi penelitian dicatat ke tabel `audit_logs` dan `similarity_evaluations`.
   - Health check endpoint `/health` dapat di-monitor secara berkala oleh Uptime Kuma atau Prometheus.
