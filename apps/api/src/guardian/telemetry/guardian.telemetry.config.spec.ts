import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  GUARDIAN_TELEMETRY_DEFAULT_INSTALL,
  isValidTelemetryUrl,
  normalizeInstallId,
  resolveGuardianTelemetryConfig,
} from './guardian.telemetry.config';

/**
 * Configuración del puente de telemetría.
 *
 * Se exige fail-closed: si falta cualquier pieza, el POS se comporta como si la
 * integración no existiera (es la garantía de que un cliente actual no cambia
 * de comportamiento al actualizar).
 */
describe('configuración de telemetría Guardian', () => {
  const baseEnv = { GUARDIAN_TELEMETRY_ENABLED: 'true' };
  const URL_OK = 'https://guardian-uat.invalid/guardian/machine/incidents';
  const KEY_OK = 'gmk_0123456789abcdefghijklmnopqrstuvwxyz';

  it('está deshabilitada por defecto', () => {
    const config = resolveGuardianTelemetryConfig({} as NodeJS.ProcessEnv);
    expect(config.enabled).toBe(false);
    expect(config.url).toBeNull();
    expect(config.problems).toHaveLength(0);
  });

  it('se habilita solo con bandera, URL válida y credencial', () => {
    const config = resolveGuardianTelemetryConfig({
      ...baseEnv,
      GUARDIAN_TELEMETRY_URL: URL_OK,
      GUARDIAN_TELEMETRY_KEY: KEY_OK,
    } as NodeJS.ProcessEnv);
    expect(config.enabled).toBe(true);
    expect(config.apiKeyPresent).toBe(true);
    expect(config.problems).toHaveLength(0);
  });

  it('rechaza esquemas que no sean http(s)', () => {
    const config = resolveGuardianTelemetryConfig({
      ...baseEnv,
      GUARDIAN_TELEMETRY_URL: 'ftp://guardian/x',
      GUARDIAN_TELEMETRY_KEY: KEY_OK,
    } as NodeJS.ProcessEnv);
    expect(config.enabled).toBe(false);
    expect(config.url).toBeNull();
    expect(config.problems.join(' ')).toContain('http(s)');
  });

  it('sin credencial no se habilita aunque la URL sea correcta', () => {
    const config = resolveGuardianTelemetryConfig({
      ...baseEnv,
      GUARDIAN_TELEMETRY_URL: URL_OK,
    } as NodeJS.ProcessEnv);
    expect(config.enabled).toBe(false);
    expect(config.problems.join(' ')).toContain('GUARDIAN_TELEMETRY_KEY');
  });

  it('acepta la credencial servida por archivo (Docker Secrets)', () => {
    const dir = mkdtempSync(join(tmpdir(), 'guardian-telemetry-'));
    try {
      const file = join(dir, 'key');
      writeFileSync(file, `${KEY_OK}\n`, 'utf8');
      const config = resolveGuardianTelemetryConfig({
        ...baseEnv,
        GUARDIAN_TELEMETRY_URL: URL_OK,
        GUARDIAN_TELEMETRY_KEY_FILE: file,
      } as NodeJS.ProcessEnv);
      expect(config.enabled).toBe(true);
      expect(config.apiKeyPresent).toBe(true);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('acota los límites a rangos seguros', () => {
    const config = resolveGuardianTelemetryConfig({
      ...baseEnv,
      GUARDIAN_TELEMETRY_URL: URL_OK,
      GUARDIAN_TELEMETRY_KEY: KEY_OK,
      GUARDIAN_TELEMETRY_TIMEOUT_MS: '999999',
      GUARDIAN_TELEMETRY_QUEUE_CAPACITY: '0',
      GUARDIAN_TELEMETRY_BATCH_SIZE: '1000',
      GUARDIAN_TELEMETRY_SAMPLE_RATE: '5',
      GUARDIAN_TELEMETRY_MAX_ATTEMPTS: '99',
    } as NodeJS.ProcessEnv);
    expect(config.timeoutMs).toBe(10_000);
    expect(config.queueCapacity).toBe(1);
    expect(config.batchSize).toBe(20);
    expect(config.sampleRate).toBe(1);
    expect(config.maxAttempts).toBe(3);
  });

  it('normaliza el identificador de instalación sin inventar identidad', () => {
    expect(normalizeInstallId('POS Farmacia / sucursal #2')).toBe('POS-Farmacia-sucursal-2');
    expect(normalizeInstallId('')).toBe(GUARDIAN_TELEMETRY_DEFAULT_INSTALL);
    expect(normalizeInstallId('///')).toBe(GUARDIAN_TELEMETRY_DEFAULT_INSTALL);
  });

  it('valida URLs de forma estricta', () => {
    expect(isValidTelemetryUrl(URL_OK)).toBe(true);
    expect(isValidTelemetryUrl('http://localhost:3000/guardian/machine/incidents')).toBe(true);
    expect(isValidTelemetryUrl('guardian/machine/incidents')).toBe(false);
    expect(isValidTelemetryUrl('javascript:alert(1)')).toBe(false);
  });
});
