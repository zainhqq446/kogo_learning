/**
 * Mengaktifkan DEVICE_ENROLLMENT_KEY untuk satu file test. Harus diimpor tepat
 * setelah `test_env.js` dan sebelum modul aplikasi (config dibaca saat import).
 */
export const TEST_ENROLLMENT_KEY = 'kogo-field-test-enrollment-key-2026';

process.env.DEVICE_ENROLLMENT_KEY = TEST_ENROLLMENT_KEY;
