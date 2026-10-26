/**
 * Parse durasi sederhana menjadi detik.
 *
 * Format yang didukung: angka murni (detik) atau angka + satuan
 * `s` (detik), `m` (menit), `h` (jam), `d` (hari). Contoh: `900`, `15m`, `180d`.
 * Sengaja dibuat ketat agar kesalahan konfigurasi terdeteksi saat startup.
 */
export function parseDurationSeconds(value: string): number {
  const trimmed = value.trim().toLowerCase();
  const match = /^(\d+)\s*([smhd]?)$/.exec(trimmed);
  if (!match) {
    throw new Error(`Invalid duration "${value}". Use a number of seconds or <n>s|m|h|d (e.g. 15m, 180d).`);
  }

  const amount = Number(match[1]);
  const unit = match[2] || 's';
  const multiplier = unit === 's' ? 1 : unit === 'm' ? 60 : unit === 'h' ? 3600 : 86400;
  const seconds = amount * multiplier;

  if (!Number.isSafeInteger(seconds) || seconds <= 0) {
    throw new Error(`Invalid duration "${value}": must be a positive amount of time.`);
  }
  return seconds;
}
