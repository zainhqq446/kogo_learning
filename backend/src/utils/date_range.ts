const DATE_ONLY = /^\d{4}-\d{2}-\d{2}$/;
const DAY_MS = 24 * 60 * 60 * 1000;

export interface DateBounds {
  /** Batas bawah inklusif (null = tanpa batas). */
  from: Date | null;
  /** Batas atas eksklusif (null = tanpa batas). */
  toExclusive: Date | null;
}

/**
 * Satu-satunya sumber aturan rentang tanggal filter riset (`from` / `to`),
 * dipakai oleh validasi query (researchQuerySchema) dan resolveRange() agar
 * keduanya tidak pernah berbeda:
 * - `from` inklusif; tanggal saja (YYYY-MM-DD) = awal hari tersebut (UTC).
 * - `to` inklusif; tanggal saja = seluruh hari tersebut (UTC), datetime =
 *   hingga milidetik tersebut. Dikembalikan sebagai batas atas eksklusif.
 */
export function resolveDateBounds(from?: string | null, to?: string | null): DateBounds {
  const fromDate = from ? new Date(DATE_ONLY.test(from) ? `${from}T00:00:00.000Z` : from) : null;
  let toExclusive: Date | null = null;
  if (to) {
    toExclusive = DATE_ONLY.test(to)
      ? new Date(Date.parse(`${to}T00:00:00.000Z`) + DAY_MS)
      : new Date(Date.parse(to) + 1);
  }
  return { from: fromDate, toExclusive };
}
