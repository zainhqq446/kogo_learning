-- ============================================================================
-- Migration: 004_thesis_erd.sql
-- Description: Skema riset "Kogo Belajar" sesuai ERD proposal (Gambar 3.20):
--   Materi, WordType, Words, Rewards (tier), GameSessions, Stars, Rewards,
--   AnswerLogs (answer_attempts), ditambah app_devices dan learners untuk
--   sinkronisasi offline-first dari aplikasi Android (API v2).
-- Requires: PostgreSQL 13+ (gen_random_uuid() bawaan, tanpa ekstensi).
-- ============================================================================

-- Konten 300 kata lama berada di luar cakupan penelitian (kata abstrak/ilmiah)
-- dan digantikan oleh tabel `words` yang di-seed dari src/data/vocabulary.json.
DROP TABLE IF EXISTS learning_words;

-- ----------------------------------------------------------------------------
-- 1. Data referensi kurikulum (di-seed ulang secara idempoten saat startup)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS materi (
    code VARCHAR(32) PRIMARY KEY,
    title VARCHAR(100) NOT NULL,
    order_index SMALLINT NOT NULL,
    node_count INT NOT NULL DEFAULT 0 CHECK (node_count >= 0)
);

CREATE TABLE IF NOT EXISTS word_types (
    code VARCHAR(32) PRIMARY KEY,
    title VARCHAR(100) NOT NULL
);

CREATE TABLE IF NOT EXISTS words (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    materi_code VARCHAR(32) NOT NULL REFERENCES materi(code) ON DELETE CASCADE,
    order_index INT NOT NULL,
    text VARCHAR(60) NOT NULL,
    syllables TEXT[] NOT NULL DEFAULT '{}',
    word_type VARCHAR(32) REFERENCES word_types(code) ON DELETE SET NULL,
    example_text VARCHAR(60),
    image_path VARCHAR(255),
    CONSTRAINT words_materi_text_unique UNIQUE (materi_code, text)
);

CREATE INDEX IF NOT EXISTS idx_words_materi_order ON words(materi_code, order_index);

CREATE TABLE IF NOT EXISTS reward_tiers (
    code VARCHAR(32) PRIMARY KEY,
    title VARCHAR(50) NOT NULL,
    min_stars INT NOT NULL UNIQUE CHECK (min_stars > 0)
);

-- ----------------------------------------------------------------------------
-- 2. Perangkat & peserta (anak usia 5-6 tahun, tanpa PII selain nama & sekolah)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS app_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_uuid UUID NOT NULL UNIQUE,
    platform VARCHAR(16) NOT NULL CHECK (platform IN ('android')),
    app_version VARCHAR(32) NOT NULL,
    model VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS learners (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_uuid UUID NOT NULL UNIQUE,
    device_id UUID NOT NULL REFERENCES app_devices(id) ON DELETE RESTRICT,
    name VARCHAR(40) NOT NULL,
    school VARCHAR(60) NOT NULL,
    age SMALLINT NOT NULL CHECK (age BETWEEN 5 AND 6),
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    synced_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_learners_device ON learners(device_id);

-- ----------------------------------------------------------------------------
-- 3. Sesi permainan, log jawaban, bintang, dan hadiah
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS game_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_uuid UUID NOT NULL UNIQUE,
    learner_id UUID NOT NULL REFERENCES learners(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES app_devices(id) ON DELETE RESTRICT,
    materi_code VARCHAR(32) NOT NULL REFERENCES materi(code) ON DELETE RESTRICT,
    node_index INT NOT NULL CHECK (node_index >= 0),
    game_type VARCHAR(20) NOT NULL CHECK (
        game_type IN ('speaking', 'find-object', 'missing-letter', 'matching', 'listening', 'fill-blank')
    ),
    status VARCHAR(12) NOT NULL CHECK (status IN ('started', 'completed', 'abandoned')),
    total_items SMALLINT NOT NULL CHECK (total_items BETWEEN 0 AND 20),
    first_try_correct SMALLINT NOT NULL CHECK (first_try_correct BETWEEN 0 AND 20),
    stars SMALLINT NOT NULL CHECK (stars BETWEEN 0 AND 3),
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ,
    synced_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT game_sessions_first_try_le_total CHECK (first_try_correct <= total_items)
);

CREATE INDEX IF NOT EXISTS idx_game_sessions_learner ON game_sessions(learner_id, materi_code, node_index);
CREATE INDEX IF NOT EXISTS idx_game_sessions_device ON game_sessions(device_id);
CREATE INDEX IF NOT EXISTS idx_game_sessions_started_at ON game_sessions(started_at);
CREATE INDEX IF NOT EXISTS idx_game_sessions_materi_game ON game_sessions(materi_code, game_type);

CREATE TABLE IF NOT EXISTS answer_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_uuid UUID NOT NULL UNIQUE,
    session_id UUID NOT NULL REFERENCES game_sessions(id) ON DELETE CASCADE,
    learner_id UUID NOT NULL REFERENCES learners(id) ON DELETE CASCADE,
    game_type VARCHAR(20) NOT NULL CHECK (
        game_type IN ('speaking', 'find-object', 'missing-letter', 'matching', 'listening', 'fill-blank')
    ),
    target_text VARCHAR(60) NOT NULL,
    answer_text VARCHAR(200) NOT NULL,
    is_correct BOOLEAN NOT NULL,
    attempt_number INT NOT NULL CHECK (attempt_number >= 1),
    similarity NUMERIC(5,4) CHECK (similarity IS NULL OR (similarity >= 0 AND similarity <= 1)),
    response_ms INT CHECK (response_ms IS NULL OR response_ms >= 0),
    stt_error VARCHAR(40),
    created_at TIMESTAMPTZ NOT NULL,
    synced_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_answer_attempts_session ON answer_attempts(session_id);
CREATE INDEX IF NOT EXISTS idx_answer_attempts_learner ON answer_attempts(learner_id, game_type);
CREATE INDEX IF NOT EXISTS idx_answer_attempts_game_created ON answer_attempts(game_type, created_at);
CREATE INDEX IF NOT EXISTS idx_answer_attempts_created_at ON answer_attempts(created_at);

-- Bintang terbaik per peserta + materi + node peta (hanya dari sesi completed).
CREATE TABLE IF NOT EXISTS stars (
    learner_id UUID NOT NULL REFERENCES learners(id) ON DELETE CASCADE,
    materi_code VARCHAR(32) NOT NULL REFERENCES materi(code) ON DELETE RESTRICT,
    node_index INT NOT NULL CHECK (node_index >= 0),
    stars SMALLINT NOT NULL CHECK (stars BETWEEN 0 AND 3),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (learner_id, materi_code, node_index)
);

-- Tingkatan hadiah yang telah diraih (earned_at = pertama kali tercapai).
CREATE TABLE IF NOT EXISTS rewards (
    learner_id UUID NOT NULL REFERENCES learners(id) ON DELETE CASCADE,
    tier_code VARCHAR(32) NOT NULL REFERENCES reward_tiers(code) ON DELETE RESTRICT,
    earned_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (learner_id, tier_code)
);
