type LogLevel = 'info' | 'warn' | 'error' | 'debug';

function formatTimestamp(): string {
  return new Date().toISOString();
}

/**
 * Sanitasi string/objek agar tidak mencetak token, password, atau API key ke log.
 */
function sanitize(message: unknown): unknown {
  if (typeof message !== 'string') return message;
  return message
    .replace(/(password|pin|secret|api_key|token)[=:]\s*([^\s&,]+)/gi, '$1=[REDACTED]')
    .replace(/(bearer\s+)[a-zA-Z0-9_\-\.]+/gi, '$1[REDACTED]');
}

export const logger = {
  info(message: string, ...args: unknown[]): void {
    const sanitizedMsg = sanitize(message);
    console.log(`[${formatTimestamp()}] [INFO] ${sanitizedMsg}`, ...args.map(sanitize));
  },
  warn(message: string, ...args: unknown[]): void {
    const sanitizedMsg = sanitize(message);
    console.warn(`[${formatTimestamp()}] [WARN] ${sanitizedMsg}`, ...args.map(sanitize));
  },
  error(message: string, ...args: unknown[]): void {
    const sanitizedMsg = sanitize(message);
    console.error(`[${formatTimestamp()}] [ERROR] ${sanitizedMsg}`, ...args.map(sanitize));
  },
  debug(message: string, ...args: unknown[]): void {
    if (process.env.NODE_ENV === 'production') return;
    const sanitizedMsg = sanitize(message);
    console.debug(`[${formatTimestamp()}] [DEBUG] ${sanitizedMsg}`, ...args.map(sanitize));
  },
};
