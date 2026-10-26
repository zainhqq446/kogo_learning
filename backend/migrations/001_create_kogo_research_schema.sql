-- ============================================================================
-- Migration: 001_create_kogo_research_schema.sql
-- Description: Inisialisasi skema inti Kogo Voice Learning untuk penelitian
-- Reference: docs/BACKEND_ARCHITECTURE.md & lib/data/database/app_database.dart
-- ============================================================================

-- 1. UUID: memakai gen_random_uuid() bawaan PostgreSQL 13+ sehingga tidak
--    membutuhkan ekstensi "uuid-ossp" (sering tidak tersedia / butuh superuser
--    di layanan PostgreSQL terkelola).

-- 2. Tabel Users (Guru & Peneliti)
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(50) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    role VARCHAR(20) NOT NULL CHECK (role IN ('admin', 'researcher', 'teacher')),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);

-- 3. Tabel Participants (Peserta Didik / Anak - Menggunakan Pseudonim, Tanpa PII)
CREATE TABLE IF NOT EXISTS participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    participant_code VARCHAR(50) NOT NULL UNIQUE, -- Contoh: P001, P002 (sesuai seed SQLite)
    display_alias VARCHAR(50) NOT NULL,          -- Contoh: "Anak 1" (ramah anak, bebas PII)
    age_years SMALLINT CHECK (age_years >= 2 AND age_years <= 12),
    gender VARCHAR(15) DEFAULT 'unspecified',
    pin_hash VARCHAR(255) NOT NULL,
    created_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_participants_code ON participants(participant_code);

-- 4. Tabel Devices (Pencatatan Perangkat Fisik Mobile)
CREATE TABLE IF NOT EXISTS devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_identifier VARCHAR(100) NOT NULL UNIQUE, -- Device ID stabil dari aplikasi
    device_label VARCHAR(100),
    platform VARCHAR(20) NOT NULL CHECK (platform IN ('android', 'ios', 'windows', 'macos', 'linux')),
    app_version VARCHAR(20),
    registered_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_devices_identifier ON devices(device_identifier);

-- 5. Tabel Kurikulum & Aktivitas Belajar (Stages, Lessons, Questions)
CREATE TABLE IF NOT EXISTS stages (
    id SERIAL PRIMARY KEY,
    title VARCHAR(100) NOT NULL,
    description TEXT,
    order_index INT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS lessons (
    id SERIAL PRIMARY KEY,
    stage_id INT NOT NULL REFERENCES stages(id) ON DELETE CASCADE,
    title VARCHAR(100) NOT NULL,
    description TEXT,
    lesson_type VARCHAR(50) NOT NULL, -- listen_repeat, find_object, matching, listen_carefully, missing_letter
    order_index INT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE INDEX IF NOT EXISTS idx_lessons_stage ON lessons(stage_id);

CREATE TABLE IF NOT EXISTS questions (
    id SERIAL PRIMARY KEY,
    lesson_id INT NOT NULL REFERENCES lessons(id) ON DELETE CASCADE,
    target_text VARCHAR(100) NOT NULL,
    normalized_target VARCHAR(100) NOT NULL,
    hint_text TEXT,
    image_asset_key VARCHAR(255),
    audio_asset_key VARCHAR(255),
    order_index INT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE INDEX IF NOT EXISTS idx_questions_lesson ON questions(lesson_id);

-- 6. Tabel Research Sessions (Sesi Belajar & Penelitian)
CREATE TABLE IF NOT EXISTS research_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_session_uuid UUID NOT NULL UNIQUE, -- UUID v4 dari SQLite klien untuk idempotensi sinkronisasi
    participant_id UUID NOT NULL REFERENCES participants(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE RESTRICT,
    session_sequence_number INT NOT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ,
    notes TEXT,
    synced_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_sessions_client_uuid ON research_sessions(client_session_uuid);
CREATE INDEX IF NOT EXISTS idx_sessions_participant ON research_sessions(participant_id);
CREATE INDEX IF NOT EXISTS idx_sessions_device ON research_sessions(device_id);

-- 7. Tabel Speech Attempts (Setiap Percobaan Suara Anak)
CREATE TABLE IF NOT EXISTS speech_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_attempt_uuid UUID NOT NULL UNIQUE, -- UUID v4 dari SQLite klien untuk idempotensi sinkronisasi
    session_id UUID NOT NULL REFERENCES research_sessions(id) ON DELETE CASCADE,
    participant_id UUID NOT NULL REFERENCES participants(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE RESTRICT,
    question_id INT NOT NULL REFERENCES questions(id) ON DELETE RESTRICT,
    attempt_number INT NOT NULL,
    target_text VARCHAR(100) NOT NULL,
    recognized_text VARCHAR(255) NOT NULL,
    asr_provider VARCHAR(50) DEFAULT 'whisper_onnx',
    locale VARCHAR(20) DEFAULT 'id_ID',
    asr_confidence NUMERIC(5,4),
    duration_ms INT,
    attempted_at TIMESTAMPTZ NOT NULL,
    synced_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_attempts_client_uuid ON speech_attempts(client_attempt_uuid);
CREATE INDEX IF NOT EXISTS idx_attempts_session ON speech_attempts(session_id);
CREATE INDEX IF NOT EXISTS idx_attempts_participant_question ON speech_attempts(participant_id, question_id);

-- 8. Tabel Similarity Evaluations (Hasil Komputasi Jarak Levenshtein & Kemiripan)
CREATE TABLE IF NOT EXISTS similarity_evaluations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attempt_id UUID NOT NULL UNIQUE REFERENCES speech_attempts(id) ON DELETE CASCADE,
    normalized_target VARCHAR(100) NOT NULL,
    normalized_recognized VARCHAR(255) NOT NULL,
    edit_distance INT NOT NULL,
    similarity_score NUMERIC(5,4) NOT NULL, -- Rentang 0.0000 - 1.0000
    similarity_percent NUMERIC(5,2) NOT NULL, -- Rentang 0.00 - 100.00
    is_correct BOOLEAN NOT NULL,
    evaluation_status VARCHAR(30) NOT NULL CHECK (
        evaluation_status IN ('EXACT_MATCH', 'ACCEPTED_SIMILAR', 'INCORRECT', 'UNRECOGNIZED')
    ),
    threshold_used NUMERIC(5,4) NOT NULL DEFAULT 1.0000,
    evaluation_method VARCHAR(50) NOT NULL DEFAULT 'levenshtein_normalized_v1',
    feedback_text TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_evaluations_status ON similarity_evaluations(evaluation_status);
CREATE INDEX IF NOT EXISTS idx_evaluations_score ON similarity_evaluations(similarity_score);
CREATE INDEX IF NOT EXISTS idx_evaluations_correct ON similarity_evaluations(is_correct);

-- 9. Tabel Audit Logs (Jejak Akses Data Penelitian & Ekspor)
CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(50) NOT NULL, -- LOGIN, EXPORT_RESEARCH_DATA, VIEW_PARTICIPANTS
    resource_affected VARCHAR(100),
    ip_address VARCHAR(45),
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_audit_user_action ON audit_logs(user_id, action);