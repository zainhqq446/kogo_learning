-- ============================================================================
-- Migration: 002_create_learning_words_table.sql
-- Description: Tabel materi 300 kata bergambar terstruktur lintas 3 tingkat kesulitan
-- ============================================================================

CREATE TABLE IF NOT EXISTS learning_words (
    id SERIAL PRIMARY KEY,
    word_id VARCHAR(50) NOT NULL UNIQUE,
    stage_id INT NOT NULL,
    stage_name VARCHAR(50) NOT NULL,
    target_text VARCHAR(100) NOT NULL,
    normalized_target VARCHAR(100) NOT NULL,
    syllables VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL,
    difficulty_level VARCHAR(20) NOT NULL CHECK (difficulty_level IN ('easy', 'medium', 'hard')),
    question_order INT NOT NULL,
    image_asset_path VARCHAR(255) NOT NULL,
    audio_asset_path VARCHAR(255) NOT NULL,
    asset_status VARCHAR(50) NOT NULL DEFAULT 'PENDING_ASSET',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_learning_words_stage ON learning_words(stage_id);
CREATE INDEX IF NOT EXISTS idx_learning_words_category ON learning_words(category);
CREATE INDEX IF NOT EXISTS idx_learning_words_normalized ON learning_words(normalized_target);
