/**
 * Production cutover profile (prepared in Phase 5, NOT executed).
 *
 * The point of these tests: `--environment=production` alone must NEVER be enough.
 * A production write requires the known production host + database, the explicit cutover
 * token derived from the locked company id and the frozen source SHA, the locked target
 * ids AND a live connection whose metadata confirms the production database.
 */

import {
  TARGET_COMPANY_ID,
  TARGET_COMPANY_NAME,
  TARGET_WAREHOUSE_ID,
  EXPECTED_SOURCE_SHA256,
} from './constants';
import {
  assertProductionCutoverEnvironment,
  assertUrlIsLocalUat,
  assertUrlIsProductionTarget,
  productionCutoverConfirmationToken,
  type LiveDatabaseMetadata,
} from './environment-guard';
import { assertExecuteConfirmations, type ExecuteConfirmationInput } from './guards';

const PROD_URL = 'postgresql://daleventa_user:fakePassword123@31.97.99.70:5432/daleventa';
const TOKEN = productionCutoverConfirmationToken();

function metadata(overrides: Partial<LiveDatabaseMetadata> = {}): LiveDatabaseMetadata {
  return {
    databaseName: 'daleventa',
    serverAddress: null,
    serverPort: 5432,
    serverVersion: 'PostgreSQL 17.11',
    currentUser: 'daleventa_user',
    ...overrides,
  };
}

function productionGate(overrides: Partial<Parameters<typeof assertProductionCutoverEnvironment>[0]> = {}) {
  return assertProductionCutoverEnvironment({
    environment: 'production',
    url: PROD_URL,
    metadata: metadata(),
    confirmationToken: TOKEN,
    targetCompanyId: TARGET_COMPANY_ID,
    targetWarehouseId: TARGET_WAREHOUSE_ID,
    ...overrides,
  });
}

describe('productionCutoverConfirmationToken', () => {
  it('is derived from the locked company and the frozen source SHA', () => {
    expect(TOKEN).toBe(`CUTOVER:${TARGET_COMPANY_ID}:${EXPECTED_SOURCE_SHA256}`);
    expect(TOKEN).toContain('f3651f62-be10-41aa-bde7-663cf990eae8');
    expect(TOKEN).toContain('A5F1F9BEE57A12E66D9E3C3BE594B147E1A835D68B69B5EA78F4BDE0438EFBDA');
  });
});

describe('assertUrlIsProductionTarget (pre-connection gate)', () => {
  it('accepts the known production database on known production infrastructure', () => {
    expect(assertUrlIsProductionTarget(PROD_URL).database).toBe('daleventa');
    expect(assertUrlIsProductionTarget('postgresql://u@gcdndd.easypanel.host:5432/daleventa')).toBeDefined();
  });

  it('never accepts the UAT or a different database', () => {
    expect(() => assertUrlIsProductionTarget('postgresql://u@31.97.99.70:5432/daleventa_uat_local')).toThrow(
      /PRODUCTION_TARGET_NOT_ALLOWED/,
    );
    expect(() => assertUrlIsProductionTarget('postgresql://u@31.97.99.70:5432/daleventa_pos')).toThrow(
      /PRODUCTION_TARGET_NOT_ALLOWED/,
    );
  });

  it('never accepts an unknown host', () => {
    expect(() => assertUrlIsProductionTarget('postgresql://u@127.0.0.1:5432/daleventa')).toThrow(
      /PRODUCTION_TARGET_NOT_ALLOWED/,
    );
  });
});

describe('assertProductionCutoverEnvironment', () => {
  it('accepts the exact production destination with the explicit token', () => {
    const result = productionGate();
    expect(result.classification).toBe('production');
    expect(result.description).toContain('daleventa');
    expect(result.description).not.toContain('fakePassword123');
  });

  it('refuses when the environment is not production', () => {
    expect(() => productionGate({ environment: 'uat' })).toThrow(/ENVIRONMENT_NOT_PRODUCTION/);
    expect(() => productionGate({ environment: '' })).toThrow(/ENVIRONMENT_NOT_PRODUCTION/);
  });

  it('refuses without the explicit cutover token', () => {
    expect(() => productionGate({ confirmationToken: null })).toThrow(/PRODUCTION_CUTOVER_NOT_CONFIRMED/);
    expect(() => productionGate({ confirmationToken: 'CUTOVER:whatever' })).toThrow(
      /PRODUCTION_CUTOVER_NOT_CONFIRMED/,
    );
    // an UAT-shaped token is not accepted either
    expect(() => productionGate({ confirmationToken: 'CUTOVER' })).toThrow(
      /PRODUCTION_CUTOVER_NOT_CONFIRMED/,
    );
  });

  it('refuses a wrong company or warehouse', () => {
    expect(() => productionGate({ targetCompanyId: '11111111-1111-4111-8111-111111111111' })).toThrow(
      /TARGET_COMPANY_MISMATCH/,
    );
    expect(() => productionGate({ targetWarehouseId: null })).toThrow(/TARGET_WAREHOUSE_MISMATCH/);
  });

  it('refuses when the live connection is not the production database', () => {
    expect(() => productionGate({ metadata: metadata({ databaseName: 'daleventa_uat_local' }) })).toThrow(
      /PRODUCTION_DATABASE_MISMATCH/,
    );
    expect(() => productionGate({ metadata: metadata({ databaseName: 'postgres' }) })).toThrow(
      /PRODUCTION_DATABASE_MISMATCH/,
    );
  });

  it('refuses a port that does not match the declared URL', () => {
    expect(() => productionGate({ metadata: metadata({ serverPort: 6543 }) })).toThrow(
      /PRODUCTION_PORT_MISMATCH/,
    );
  });

  it('refuses a non-production host before any connection', () => {
    expect(() => productionGate({ url: 'postgresql://u@127.0.0.1:5432/daleventa' })).toThrow(
      /PRODUCTION_TARGET_NOT_ALLOWED/,
    );
  });
});

describe('production via VERIFIED SSH TUNNEL', () => {
  // The production database is not reachable directly (5432 closes from the internet);
  // the authorized route is the controlled tunnel to the host's own loopback.
  const TUNNEL_URL = 'postgresql://daleventa_user:fakePassword123@127.0.0.1:15432/daleventa';

  function tunnelMetadata(overrides: Partial<LiveDatabaseMetadata> = {}): LiveDatabaseMetadata {
    // What a real tunnel session reports: the SERVER's own address/port, not the tunnel's.
    return metadata({
      databaseName: 'daleventa',
      serverAddress: '10.0.2.8/32',
      serverPort: 5432,
      ...overrides,
    });
  }

  function tunnelGate(overrides: Record<string, unknown> = {}) {
    return assertProductionCutoverEnvironment({
      environment: 'production',
      url: TUNNEL_URL,
      metadata: tunnelMetadata(),
      confirmationToken: TOKEN,
      targetCompanyId: TARGET_COMPANY_ID,
      targetWarehouseId: TARGET_WAREHOUSE_ID,
      sshTunnel: true,
      ...overrides,
    });
  }

  it('a plain localhost URL is never sufficient: without the tunnel flag it aborts', () => {
    expect(() => assertUrlIsProductionTarget(TUNNEL_URL)).toThrow(/PRODUCTION_TARGET_NOT_ALLOWED/);
    expect(() =>
      assertProductionCutoverEnvironment({
        environment: 'production',
        url: TUNNEL_URL,
        metadata: tunnelMetadata(),
        confirmationToken: TOKEN,
        targetCompanyId: TARGET_COMPANY_ID,
        targetWarehouseId: TARGET_WAREHOUSE_ID,
      }),
    ).toThrow(/PRODUCTION_TARGET_NOT_ALLOWED/);
  });

  it('accepts the tunnel route only on the declared local port', () => {
    expect(assertUrlIsProductionTarget(TUNNEL_URL, { sshTunnel: true }).port).toBe('15432');
    expect(() =>
      assertUrlIsProductionTarget('postgresql://u@127.0.0.1:5432/daleventa', { sshTunnel: true }),
    ).toThrow(/PRODUCTION_TUNNEL_NOT_ALLOWED/);
    expect(() =>
      assertUrlIsProductionTarget('postgresql://u@127.0.0.1:15432/daleventa_uat_local', {
        sshTunnel: true,
      }),
    ).toThrow(/PRODUCTION_TUNNEL_NOT_ALLOWED/);
    expect(() =>
      assertUrlIsProductionTarget('postgresql://u@10.0.0.9:15432/daleventa', { sshTunnel: true }),
    ).toThrow(/PRODUCTION_TUNNEL_NOT_ALLOWED/);
  });

  it('accepts a verified tunnel (token + ids + production database + real server metadata)', () => {
    const result = tunnelGate();
    expect(result.classification).toBe('production');
    expect(result.route).toBe('SSH_TUNNEL');
    expect(result.description).not.toContain('fakePassword123');
  });

  it('reports DIRECT when the tunnel flag is not used', () => {
    expect(productionGate().route).toBe('DIRECT');
  });

  it('refuses a tunnel whose live server looks local (a local database pretending to be production)', () => {
    expect(() =>
      tunnelGate({ metadata: tunnelMetadata({ serverAddress: '127.0.0.1/32' }) }),
    ).toThrow(/PRODUCTION_TUNNEL_UNVERIFIED/);
    expect(() => tunnelGate({ metadata: tunnelMetadata({ serverAddress: '::1/128' }) })).toThrow(
      /PRODUCTION_TUNNEL_UNVERIFIED/,
    );
    expect(() => tunnelGate({ metadata: tunnelMetadata({ serverAddress: null }) })).toThrow(
      /PRODUCTION_TUNNEL_UNVERIFIED/,
    );
  });

  it('refuses a tunnel whose live server does not listen on the production port', () => {
    expect(() => tunnelGate({ metadata: tunnelMetadata({ serverPort: 55432 }) })).toThrow(
      /PRODUCTION_TUNNEL_UNVERIFIED/,
    );
  });

  it('refuses a tunnel to a database that is not the production database', () => {
    expect(() => tunnelGate({ metadata: tunnelMetadata({ databaseName: 'daleventa_uat_local' }) })).toThrow(
      /PRODUCTION_DATABASE_MISMATCH/,
    );
  });

  it('still requires the cutover token, the locked ids and the frozen environment', () => {
    expect(() => tunnelGate({ confirmationToken: null })).toThrow(/PRODUCTION_CUTOVER_NOT_CONFIRMED/);
    expect(() => tunnelGate({ environment: 'uat' })).toThrow(/ENVIRONMENT_NOT_PRODUCTION/);
    expect(() => tunnelGate({ targetCompanyId: 'otro' })).toThrow(/TARGET_COMPANY_MISMATCH/);
    expect(() => tunnelGate({ targetWarehouseId: null })).toThrow(/TARGET_WAREHOUSE_MISMATCH/);
  });

  it('the UAT profile still refuses a production database name, tunnel or not', () => {
    expect(() => assertUrlIsLocalUat('postgresql://u@127.0.0.1:15432/daleventa')).toThrow(
      /PRODUCTION_FORBIDDEN/,
    );
  });
});

describe('assertExecuteConfirmations (production profile)', () => {
  const base: ExecuteConfirmationInput = {
    execute: true,
    environment: 'production',
    targetCompanyId: TARGET_COMPANY_ID,
    targetWarehouseId: TARGET_WAREHOUSE_ID,
    sourceSha256: EXPECTED_SOURCE_SHA256,
    confirmCompanyName: TARGET_COMPANY_NAME,
    confirmWrite: true,
  };

  it('aborts without the cutover token even when everything else is confirmed', () => {
    expect(() => assertExecuteConfirmations(base)).toThrow(/PRODUCTION_CUTOVER_NOT_CONFIRMED/);
    expect(() => assertExecuteConfirmations({ ...base, productionConfirmationToken: 'nope' })).toThrow(
      /PRODUCTION_CUTOVER_NOT_CONFIRMED/,
    );
  });

  it('accepts the production profile only with the exact token and all confirmations', () => {
    expect(() =>
      assertExecuteConfirmations({ ...base, productionConfirmationToken: TOKEN }),
    ).not.toThrow();
  });

  it('still enforces every other confirmation in the production profile', () => {
    const withToken = { ...base, productionConfirmationToken: TOKEN };
    expect(() => assertExecuteConfirmations({ ...withToken, execute: false })).toThrow(
      /EXECUTE_FLAG_REQUIRED/,
    );
    expect(() => assertExecuteConfirmations({ ...withToken, confirmWrite: false })).toThrow(
      /WRITE_NOT_CONFIRMED/,
    );
    expect(() => assertExecuteConfirmations({ ...withToken, sourceSha256: null })).toThrow(
      /SOURCE_HASH_NOT_CONFIRMED/,
    );
    // the confirmed SHA must match the file actually opened when it is known
    expect(() =>
      assertExecuteConfirmations({
        ...withToken,
        sourceSha256: 'DEADBEEF',
        actualSourceSha256: EXPECTED_SOURCE_SHA256,
      }),
    ).toThrow(/SOURCE_HASH_MISMATCH/);
    expect(() =>
      assertExecuteConfirmations({ ...withToken, confirmCompanyName: 'Otra empresa' }),
    ).toThrow(/COMPANY_NAME_MISMATCH/);
    expect(() =>
      assertExecuteConfirmations({ ...withToken, targetCompanyId: 'otra' }),
    ).toThrow(/TARGET_COMPANY_MISMATCH/);
  });

  it('keeps the UAT profile working unchanged', () => {
    expect(() =>
      assertExecuteConfirmations({ ...base, environment: 'uat', productionConfirmationToken: null }),
    ).not.toThrow();
  });
});
