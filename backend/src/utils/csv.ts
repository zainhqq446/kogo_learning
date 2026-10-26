/** Byte Order Mark UTF-8 agar Microsoft Excel membaca karakter non-ASCII dengan benar. */
export const UTF8_BOM = '\uFEFF';

/** Karakter awal yang membuat spreadsheet mengeksekusi sel sebagai formula. */
const FORMULA_TRIGGERS = new Set(['=', '+', '-', '@', '\t', '\r']);
/**
 * `;` yang langsung diikuti pemicu formula. Excel dengan locale Indonesia/Eropa
 * memakai `;` sebagai pemisah kolom, sehingga setiap segmen setelah `;` bisa
 * menjadi sel tersendiri yang dieksekusi sebagai formula.
 */
const SEMICOLON_FORMULA = /;(?=[=+\-@\t\r])/g;

export type CsvValue = string | number | boolean | Date | null | undefined;

/**
 * Escape satu sel CSV (RFC 4180) dengan proteksi CSV/formula injection:
 * string yang diawali = + - @ (atau tab/CR) diberi prefiks tanda kutip tunggal
 * sehingga diperlakukan sebagai teks oleh Excel / Google Sheets / LibreOffice.
 * Hal yang sama berlaku untuk setiap segmen setelah `;` (locale yang memakai
 * titik koma sebagai pemisah kolom): `x;=1+1;y` menjadi `x;'=1+1;y`.
 */
export function escapeCsvCell(value: CsvValue): string {
  if (value === null || value === undefined) return '';

  let text: string;
  if (value instanceof Date) {
    text = Number.isNaN(value.getTime()) ? '' : value.toISOString();
  } else if (typeof value === 'number') {
    text = Number.isFinite(value) ? String(value) : '';
  } else if (typeof value === 'boolean') {
    text = value ? 'true' : 'false';
  } else {
    text = value;
    if (text.length > 0 && FORMULA_TRIGGERS.has(text[0])) {
      text = `'${text}`;
    }
    text = text.replace(SEMICOLON_FORMULA, ";'");
  }

  if (/[",\r\n]/.test(text) || /^\s|\s$/.test(text)) {
    return `"${text.replace(/"/g, '""')}"`;
  }
  return text;
}

export function toCsvRow(values: CsvValue[]): string {
  return values.map(escapeCsvCell).join(',');
}

export interface CsvColumn<T> {
  header: string;
  value: (row: T) => CsvValue;
}

/** BOM + baris header (diakhiri CRLF). */
export function csvHeader<T>(columns: Array<CsvColumn<T>>): string {
  return `${UTF8_BOM}${toCsvRow(columns.map((c) => c.header))}\r\n`;
}

/** Baris data (masing-masing diakhiri CRLF); string kosong bila tidak ada baris. */
export function csvRows<T>(columns: Array<CsvColumn<T>>, rows: T[]): string {
  let out = '';
  for (const row of rows) {
    out += `${toCsvRow(columns.map((c) => c.value(row)))}\r\n`;
  }
  return out;
}

/**
 * Membangun dokumen CSV lengkap (BOM + header + baris, pemisah CRLF).
 */
export function toCsv<T>(columns: Array<CsvColumn<T>>, rows: T[]): string {
  return csvHeader(columns) + csvRows(columns, rows);
}
