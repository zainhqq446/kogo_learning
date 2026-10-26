import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);

/**
 * Root direktori backend (folder yang berisi `package.json` dan `migrations/`).
 *
 * File ini berada di `src/utils` (tsx) atau `dist/utils` (build), sehingga root
 * selalu dua tingkat di atasnya. Path dihitung dari `import.meta.url`, bukan
 * `process.cwd()`, agar tetap benar ketika proses dijalankan dari folder lain
 * (misalnya di dalam container Docker).
 */
export const BACKEND_ROOT = path.resolve(path.dirname(__filename), '..', '..');

export const MIGRATIONS_DIR = path.join(BACKEND_ROOT, 'migrations');

export const DEFAULT_TTS_CACHE_DIR = path.join(BACKEND_ROOT, 'data', 'tts-cache');
