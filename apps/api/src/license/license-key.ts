import { randomUUID } from 'node:crypto';

/** Existing credential format, shared by authorized activation paths only. */
export function createLicenseKey(): string {
  return `DV-${randomUUID().replace(/-/g, '').slice(0, 20).toUpperCase()}`;
}
