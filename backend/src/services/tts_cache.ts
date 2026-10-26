import crypto from 'crypto';
import fs from 'fs/promises';
import path from 'path';
import { logger } from '../utils/logger.js';

export interface TtsCacheKeyInput {
  text: string;
  voiceId: string;
  modelId: string;
  settings: Record<string, number | boolean>;
  languageCode: string | null;
  outputFormat: string;
  textNormalization: string;
}

/**
 * Kunci cache deterministik: sha256(text|voice|model|settings|language|format).
 * Settings diurutkan berdasarkan nama agar urutan properti tidak memengaruhi kunci.
 */
export function ttsCacheKey(input: TtsCacheKeyInput): string {
  const sortedSettings = Object.keys(input.settings)
    .sort()
    .map((k) => `${k}=${input.settings[k]}`)
    .join(',');
  const material = [
    input.text,
    input.voiceId,
    input.modelId,
    sortedSettings,
    input.languageCode ?? '',
    input.outputFormat,
    input.textNormalization,
  ].join('|');
  return crypto.createHash('sha256').update(material, 'utf8').digest('hex');
}

interface CacheFile {
  file: string;
  size: number;
  mtimeMs: number;
}

/**
 * Cache audio TTS di disk (volume /app/data di Docker). Kegagalan baca/tulis
 * tidak pernah menggagalkan request; cache hanya dilewati.
 *
 * Ukuran total dibatasi `maxBytes` (TTS_CACHE_MAX_MB): bila terlampaui, file
 * yang paling lama tidak dipakai (mtime, diperbarui saat cache hit) dihapus
 * sampai ukuran turun ke 90% batas.
 */
export class TtsDiskCache {
  private totalBytes: number | null = null;
  private evicting: Promise<void> | null = null;

  constructor(
    private readonly dir: string,
    private readonly enabled = true,
    private readonly maxBytes = Number.POSITIVE_INFINITY
  ) {}

  private fileFor(key: string): string {
    if (!/^[a-f0-9]{64}$/.test(key)) {
      throw new Error('Invalid cache key');
    }
    return path.join(this.dir, key.slice(0, 2), `${key}.mp3`);
  }

  async get(key: string): Promise<Buffer | null> {
    if (!this.enabled) return null;
    try {
      const file = this.fileFor(key);
      const data = await fs.readFile(file);
      if (data.length === 0) return null;
      // Tandai sebagai baru dipakai (LRU berbasis mtime).
      const now = new Date();
      await fs.utimes(file, now, now).catch(() => undefined);
      return data;
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== 'ENOENT' && (err as Error).message !== 'Invalid cache key') {
        logger.warn(`TTS cache read failed: ${(err as Error).message}`);
      }
      return null;
    }
  }

  async set(key: string, audio: Buffer): Promise<void> {
    if (!this.enabled || audio.length === 0) return;
    const file = this.fileFor(key);
    const tmp = `${file}.${process.pid}.${crypto.randomBytes(6).toString('hex')}.tmp`;
    try {
      await fs.mkdir(path.dirname(file), { recursive: true });
      await fs.writeFile(tmp, audio);
      await fs.rename(tmp, file);
    } catch (err) {
      logger.warn(`TTS cache write failed: ${(err as Error).message}`);
      await fs.rm(tmp, { force: true }).catch(() => undefined);
      return;
    }
    await this.enforceLimit(audio.length);
  }

  /** Ukuran total file cache saat ini (byte). */
  async sizeBytes(): Promise<number> {
    const files = await this.listFiles();
    return files.reduce((sum, f) => sum + f.size, 0);
  }

  private async enforceLimit(addedBytes: number): Promise<void> {
    if (!Number.isFinite(this.maxBytes)) return;
    try {
      if (this.totalBytes === null) this.totalBytes = await this.sizeBytes();
      else this.totalBytes += addedBytes;
      if (this.totalBytes <= this.maxBytes) return;
      if (!this.evicting) {
        this.evicting = this.evict().finally(() => {
          this.evicting = null;
        });
      }
      await this.evicting;
    } catch (err) {
      logger.warn(`TTS cache eviction failed: ${(err as Error).message}`);
    }
  }

  private async evict(): Promise<void> {
    const files = (await this.listFiles()).sort((a, b) => a.mtimeMs - b.mtimeMs);
    let total = files.reduce((sum, f) => sum + f.size, 0);
    const target = Math.floor(this.maxBytes * 0.9);
    let removed = 0;
    for (const f of files) {
      if (total <= target) break;
      await fs.rm(f.file, { force: true });
      total -= f.size;
      removed += 1;
    }
    this.totalBytes = total;
    if (removed > 0) logger.info(`TTS cache: evicted ${removed} file(s) to stay under ${this.maxBytes} bytes.`);
  }

  private async listFiles(): Promise<CacheFile[]> {
    let shards: string[];
    try {
      shards = await fs.readdir(this.dir);
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === 'ENOENT') return [];
      throw err;
    }
    const files: CacheFile[] = [];
    for (const shard of shards) {
      if (!/^[a-f0-9]{2}$/.test(shard)) continue;
      const shardDir = path.join(this.dir, shard);
      let names: string[];
      try {
        names = await fs.readdir(shardDir);
      } catch {
        continue;
      }
      for (const name of names) {
        if (!name.endsWith('.mp3')) continue;
        const file = path.join(shardDir, name);
        try {
          const st = await fs.stat(file);
          files.push({ file, size: st.size, mtimeMs: st.mtimeMs });
        } catch {
          // file dihapus paralel
        }
      }
    }
    return files;
  }
}
