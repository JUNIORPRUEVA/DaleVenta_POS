/**
 * Execute-path environment guard (pure logic, no database connection).
 *
 * These tests are the reason a CLI flag alone can never write to a non-UAT database:
 * layer 1 rejects the URL (protected names, non-loopback, known production hosts),
 * layer 2 rejects a live connection that does not agree with the URL.
 */

import {
  assertUatEnvironment,
  assertUrlIsLocalUat,
  classifyEnvironment,
  describeDatabaseUrl,
  parseDatabaseUrl,
  PROTECTED_DATABASE_NAMES,
  PROTECTED_HOST_PATTERNS,
  type LiveDatabaseMetadata,
} from './environment-guard';

const UAT_URL = 'postgresql://daleventa_uat_user:fakePassword123@127.0.0.1:55432/daleventa_uat_local';

function metadata(overrides: Partial<LiveDatabaseMetadata> = {}): LiveDatabaseMetadata {
  return {
    databaseName: 'daleventa_uat_local',
    serverAddress: '127.0.0.1/32',
    serverPort: 55432,
    serverVersion: 'PostgreSQL 17.9',
    currentUser: 'daleventa_uat_user',
    ...overrides,
  };
}

describe('parseDatabaseUrl / describeDatabaseUrl', () => {
  it('extracts host, port, database and user', () => {
    const parsed = parseDatabaseUrl(UAT_URL);
    expect(parsed.host).toBe('127.0.0.1');
    expect(parsed.port).toBe('55432');
    expect(parsed.database).toBe('daleventa_uat_local');
    expect(parsed.user).toBe('daleventa_uat_user');
    expect(parsed.isLoopback).toBe(true);
    expect(parsed.isProtectedDatabase).toBe(false);
    expect(parsed.isProtectedHost).toBe(false);
  });

  it('never exposes the password in the printable description', () => {
    const description = describeDatabaseUrl(UAT_URL);
    expect(description).toContain('daleventa_uat_user@127.0.0.1:55432/daleventa_uat_local');
    expect(description).not.toContain('fakePassword123');
  });

  it('flags protected databases and known production infrastructure', () => {
    for (const name of PROTECTED_DATABASE_NAMES) {
      expect(parseDatabaseUrl(`postgresql://u@127.0.0.1:5432/${name}`).isProtectedDatabase).toBe(true);
    }
    expect(
      parseDatabaseUrl('postgresql://u@31.97.99.70:5432/daleventa_uat_local').isProtectedHost,
    ).toBe(true);
    expect(parseDatabaseUrl('postgresql://u@gcdndd.easypanel.host:5432/x').isProtectedHost).toBe(true);
    expect(PROTECTED_HOST_PATTERNS.length).toBeGreaterThan(0);
  });

  it('rejects an invalid URL', () => {
    expect(() => parseDatabaseUrl('not-a-url')).toThrow(/DATABASE_URL_INVALID/);
  });
});

describe('classifyEnvironment', () => {
  it('classifies a loopback database whose name looks like UAT as uat', () => {
    const result = classifyEnvironment({ environment: 'uat', url: UAT_URL, metadata: metadata() });
    expect(result.classification).toBe('uat');
    expect(result.reasons).toEqual([]);
  });

  it('classifies production for a protected live database name', () => {
    const result = classifyEnvironment({
      environment: 'uat',
      url: UAT_URL,
      metadata: metadata({ databaseName: 'daleventa' }),
    });
    expect(result.classification).toBe('production');
    expect(result.reasons.join(' ')).toMatch(/protected/);
  });

  it('classifies production for a protected database in the URL', () => {
    const result = classifyEnvironment({
      environment: 'uat',
      url: 'postgresql://u@127.0.0.1:5432/daleventa_pos',
      metadata: metadata({ databaseName: 'daleventa_pos' }),
    });
    expect(result.classification).toBe('production');
  });

  it('classifies production when the URL matches known production infrastructure', () => {
    const result = classifyEnvironment({
      environment: 'uat',
      url: 'postgresql://u@31.97.99.70:5432/daleventa_uat_local',
      metadata: metadata({ serverAddress: '31.97.99.70/32' }),
    });
    expect(result.classification).toBe('production');
  });

  it('classifies production when --environment=production is requested', () => {
    const result = classifyEnvironment({ environment: 'production', url: UAT_URL, metadata: metadata() });
    expect(result.classification).toBe('production');
  });

  it('classifies unknown for a non-loopback host', () => {
    const result = classifyEnvironment({
      environment: 'uat',
      url: 'postgresql://u@192.168.1.50:55432/daleventa_uat_local',
      metadata: metadata({ serverAddress: '192.168.1.50/32' }),
    });
    expect(result.classification).toBe('unknown');
  });

  it('classifies unknown when the database name does not look like UAT', () => {
    const result = classifyEnvironment({
      environment: 'uat',
      url: 'postgresql://u@127.0.0.1:55432/some_other_db',
      metadata: metadata({ databaseName: 'some_other_db' }),
    });
    expect(result.classification).toBe('unknown');
  });
});

describe('assertUrlIsLocalUat (pre-connection gate)', () => {
  it('accepts the disposable local UAT url and returns the parsed parts', () => {
    const parsed = assertUrlIsLocalUat(UAT_URL);
    expect(parsed.database).toBe('daleventa_uat_local');
    expect(parsed.port).toBe('55432');
  });

  it('refuses protected production databases before connecting', () => {
    expect(() => assertUrlIsLocalUat('postgresql://u:p@127.0.0.1:5432/daleventa')).toThrow(
      /PRODUCTION_FORBIDDEN/,
    );
    expect(() => assertUrlIsLocalUat('postgresql://u:p@127.0.0.1:5432/daleventa_pos')).toThrow(
      /PRODUCTION_FORBIDDEN/,
    );
  });

  it('refuses known production infrastructure before connecting', () => {
    expect(() => assertUrlIsLocalUat('postgresql://u:p@31.97.99.70:5432/daleventa_uat_local')).toThrow(
      /PRODUCTION_FORBIDDEN/,
    );
    expect(() =>
      assertUrlIsLocalUat('postgresql://u:p@gcdndd.easypanel.host:5432/daleventa_uat_local'),
    ).toThrow(/PRODUCTION_FORBIDDEN/);
  });

  it('refuses non-loopback and non-UAT names before connecting', () => {
    expect(() => assertUrlIsLocalUat('postgresql://u:p@192.168.0.10:5432/daleventa_uat_local')).toThrow(
      /ENVIRONMENT_NOT_VERIFIED/,
    );
    expect(() => assertUrlIsLocalUat('postgresql://u:p@127.0.0.1:5432/produccion')).toThrow(
      /ENVIRONMENT_NOT_VERIFIED/,
    );
  });
});

describe('assertUatEnvironment', () => {
  it('accepts the disposable local UAT database', () => {
    const result = assertUatEnvironment({
      environment: 'uat',
      url: UAT_URL,
      metadata: metadata(),
      env: {},
    });
    expect(result.classification).toBe('uat');
    expect(result.description).not.toContain('fakePassword123');
  });

  it('refuses a protected production database name (URL layer)', () => {
    expect(() =>
      assertUatEnvironment({
        environment: 'uat',
        url: 'postgresql://u@127.0.0.1:5432/daleventa',
        metadata: metadata({ databaseName: 'daleventa' }),
        env: {},
      }),
    ).toThrow(/protected database|database must be/);
  });

  it('refuses a non-loopback host (URL layer)', () => {
    expect(() =>
      assertUatEnvironment({
        environment: 'uat',
        url: 'postgresql://u@10.0.0.7:5432/daleventa_uat_local',
        metadata: metadata({ serverAddress: '10.0.0.7/32' }),
        env: {},
      }),
    ).toThrow(/host must be/);
  });

  it('refuses known production infrastructure (URL layer)', () => {
    // The sanctioned gate rejects the host (not loopback) and/or the production
    // infrastructure pattern; either way the write never starts.
    expect(() =>
      assertUatEnvironment({
        environment: 'uat',
        url: 'postgresql://u@gcdndd.easypanel.host:5432/daleventa_uat_local',
        metadata: metadata({ serverAddress: '10.0.0.9/32' }),
        env: {},
      }),
    ).toThrow(/host must be|remote production infrastructure/);
  });

  it('refuses any environment other than uat', () => {
    expect(() =>
      assertUatEnvironment({ environment: 'production', url: UAT_URL, metadata: metadata(), env: {} }),
    ).toThrow(/ENVIRONMENT_NOT_UAT/);
    expect(() =>
      assertUatEnvironment({ environment: '', url: UAT_URL, metadata: metadata(), env: {} }),
    ).toThrow(/ENVIRONMENT_NOT_UAT/);
  });

  it('refuses when the live database does not match the URL', () => {
    expect(() =>
      assertUatEnvironment({
        environment: 'uat',
        url: UAT_URL,
        metadata: metadata({ databaseName: 'daleventa_uat_other' }),
        env: {},
      }),
    ).toThrow(/DATABASE_URL_MISMATCH/);
  });

  it('refuses when the live server address is not loopback', () => {
    expect(() =>
      assertUatEnvironment({
        environment: 'uat',
        url: UAT_URL,
        metadata: metadata({ serverAddress: '10.1.2.3/32' }),
        env: {},
      }),
    ).toThrow(/UAT_NOT_LOOPBACK/);
  });

  it('refuses when the live port does not match the URL port', () => {
    expect(() =>
      assertUatEnvironment({
        environment: 'uat',
        url: UAT_URL,
        metadata: metadata({ serverPort: 5432 }),
        env: {},
      }),
    ).toThrow(/UAT_PORT_MISMATCH/);
  });

  it('treats IPv6 loopback as a local destination in its own classification layer', () => {
    // NOTE: the project's sanctioned gate (src/common/uat-safety.ts) only allowlists
    // "localhost", "127.0.0.1" and "::1" (unbracketed). The migration actually used an
    // IPv4 loopback destination, so this documents this module's own layer-2 behaviour.
    const ipv6Url = 'postgresql://u@[::1]:55432/daleventa_uat_local';
    expect(parseDatabaseUrl(ipv6Url).isLoopback).toBe(true);
    expect(
      classifyEnvironment({
        environment: 'uat',
        url: ipv6Url,
        metadata: metadata({ serverAddress: '::1/128', serverPort: 55432 }),
      }).classification,
    ).toBe('uat');
  });
});
