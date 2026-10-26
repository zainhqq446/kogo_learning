-- ============================================================================
-- Migration: 005_device_trust_and_voice_budget.sql
-- Description:
--   1. Kepercayaan perangkat (API v2):
--      - secret_hash : SHA-256 dari deviceSecret yang diterbitkan sekali saat
--                      registrasi pertama (bukti kepemilikan saat registrasi ulang).
--      - approved_at : perangkat disetujui peneliti; hanya data perangkat yang
--                      disetujui yang masuk metrik/ekspor secara default dan hanya
--                      perangkat ini yang boleh memakai proxy suara berbayar.
--      - revoked_at  : perangkat dicabut (token ditolak, data dikecualikan).
--      - label       : nama ramah untuk peneliti (mis. "Tablet TK Pelita").
--   2. voice_usage_daily: anggaran harian ElevenLabs (karakter TTS, detik STT).
-- ============================================================================

ALTER TABLE app_devices ADD COLUMN IF NOT EXISTS secret_hash CHAR(64);
ALTER TABLE app_devices ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;
ALTER TABLE app_devices ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE app_devices ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ;
ALTER TABLE app_devices ADD COLUMN IF NOT EXISTS label VARCHAR(60);

-- Perangkat yang sudah terdaftar sebelum migrasi ini dianggap disetujui agar
-- data lama tetap muncul di metrik (tidak ada perubahan perilaku untuk data lama).
UPDATE app_devices SET approved_at = created_at WHERE approved_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_app_devices_trust ON app_devices(approved_at, revoked_at);

CREATE TABLE IF NOT EXISTS voice_usage_daily (
    day DATE NOT NULL,
    metric VARCHAR(32) NOT NULL CHECK (metric IN ('tts_chars', 'stt_seconds')),
    amount NUMERIC(14, 2) NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (day, metric)
);
