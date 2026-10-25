-- ============================================================================
-- Migration: 003_add_child_profile_fields.sql
-- Description: Menambahkan role 'child'/'student', field umur, dan sekolah pada users/participants
-- ============================================================================

-- 1. Modifikasi constraint role pada tabel users agar mendukung 'child' dan 'student'
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE users ADD CONSTRAINT users_role_check 
  CHECK (role IN ('admin', 'researcher', 'teacher', 'child', 'student'));

-- 2. Tambahkan kolom profil anak pada users
ALTER TABLE users ADD COLUMN IF NOT EXISTS age_years SMALLINT CHECK (age_years >= 2 AND age_years <= 18);
ALTER TABLE users ADD COLUMN IF NOT EXISTS school_name VARCHAR(150);

-- 3. Hubungkan participants dengan user_id jika peserta dibuat dari akun pengguna
ALTER TABLE participants ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES users(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_participants_user_id ON participants(user_id);