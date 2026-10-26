import { createHash } from 'node:crypto';

/**
 * Firma estable de un patrón de incidente.
 *
 * Se usa para agrupar incidentes equivalentes y para deduplicar alertas.
 * Incluye solo la parte superior del stack (marcos normalizados) para que el
 * mismo defecto agrupe aunque cambien los números de línea por refactors.
 */
export function normalizeStackFrames(stack: string | null | undefined, maxFrames = 3): string[] {
  if (!stack) return [];
  const frames: string[] = [];
  for (const rawLine of stack.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line) continue;
    if (!/^(at\s|#\d+\s|package:)/.test(line)) continue;
    frames.push(
      line
        .replace(/\(.*?:\d+:\d+\)/g, '')
        .replace(/:\d+:\d+/g, '')
        .replace(/\s+/g, ' ')
        .trim()
        .slice(0, 160),
    );
    if (frames.length >= maxFrames) break;
  }
  return frames;
}

export function buildFingerprint(input: {
  module: string;
  operation: string;
  exceptionType?: string | null;
  stack?: string | null;
  appVersion?: string | null;
}): string {
  const frames = normalizeStackFrames(input.stack).join('>');
  const versionMajor = String(input.appVersion ?? '').split('.')[0] ?? '';
  const material = [
    String(input.module ?? '').toLowerCase(),
    String(input.operation ?? '').toLowerCase(),
    String(input.exceptionType ?? '').toLowerCase(),
    frames.toLowerCase(),
    versionMajor,
  ].join('|');

  return createHash('sha256').update(material).digest('hex').slice(0, 40);
}
