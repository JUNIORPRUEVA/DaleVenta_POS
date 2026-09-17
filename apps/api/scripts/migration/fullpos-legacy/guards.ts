/**
 * Guards for the legacy migration. Pure functions: no I/O.
 *
 * Every function here aborts loudly instead of degrading, because the only
 * acceptable failure mode is "stop before writing anything".
 */

import {
  DEMO_CASH_SESSION_ID,
  EXPECTED_SOURCE_SHA256,
  TARGET_COMPANY_ID,
  TARGET_COMPANY_NAME,
  TARGET_OWNER_USER_ID,
  TARGET_TERMINAL_ID,
  TARGET_WAREHOUSE_ID,
} from './constants';
import { productionCutoverConfirmationToken } from './environment-guard';
import { MigrationAbortError } from './errors';
import type { TargetSnapshot } from './types';

export function assertSourceSha256(actual: string, expected = EXPECTED_SOURCE_SHA256): void {
  if (actual.trim().toUpperCase() !== expected.trim().toUpperCase()) {
    throw new MigrationAbortError('SOURCE_HASH_MISMATCH', 'El SHA256 del origen no coincide', {
      expected,
      actual,
      hint: 'Si es la captura final de cutover, debe autorizarse explícitamente antes de continuar.',
    });
  }
}

/**
 * Validate the read-only target snapshot against the locked tenant.
 * Aborts when the company/warehouse/terminal/owner do not match, when the target
 * belongs to another company, or when the tenant baseline is not the expected one.
 */
export function assertTargetSnapshot(
  snapshot: TargetSnapshot,
  options: { requireCleanBaseline?: boolean } = {},
): void {
  const requireCleanBaseline = options.requireCleanBaseline ?? true;

  const company = snapshot.company;
  if (!company) {
    throw new MigrationAbortError('TARGET_COMPANY_MISSING', 'No existe la empresa destino', {
      expectedCompanyId: TARGET_COMPANY_ID,
    });
  }
  if (company.id !== TARGET_COMPANY_ID) {
    throw new MigrationAbortError('TARGET_COMPANY_MISMATCH', 'La empresa destino no coincide', {
      expectedCompanyId: TARGET_COMPANY_ID,
      actualCompanyId: company.id,
    });
  }
  if (company.name.trim() !== TARGET_COMPANY_NAME) {
    throw new MigrationAbortError('TARGET_COMPANY_NAME_MISMATCH', 'El nombre de la empresa no coincide', {
      expected: TARGET_COMPANY_NAME,
      actual: company.name,
    });
  }

  const warehouse = snapshot.warehouse;
  if (!warehouse) {
    throw new MigrationAbortError('TARGET_WAREHOUSE_MISSING', 'No existe el almacén destino', {
      expectedWarehouseId: TARGET_WAREHOUSE_ID,
    });
  }
  if (warehouse.id !== TARGET_WAREHOUSE_ID) {
    throw new MigrationAbortError('TARGET_WAREHOUSE_MISMATCH', 'El almacén destino no coincide', {
      expectedWarehouseId: TARGET_WAREHOUSE_ID,
      actualWarehouseId: warehouse.id,
    });
  }
  if (warehouse.companyId !== TARGET_COMPANY_ID) {
    throw new MigrationAbortError(
      'TARGET_WAREHOUSE_OTHER_TENANT',
      'El almacén destino pertenece a otra empresa',
      { warehouseCompanyId: warehouse.companyId, targetCompanyId: TARGET_COMPANY_ID },
    );
  }

  const terminal = snapshot.terminal;
  if (!terminal) {
    throw new MigrationAbortError('TARGET_TERMINAL_MISSING', 'No existe la terminal destino', {
      expectedTerminalId: TARGET_TERMINAL_ID,
    });
  }
  if (terminal.id !== TARGET_TERMINAL_ID) {
    throw new MigrationAbortError('TARGET_TERMINAL_MISMATCH', 'La terminal destino no coincide', {
      expectedTerminalId: TARGET_TERMINAL_ID,
      actualTerminalId: terminal.id,
    });
  }
  if (terminal.companyId !== TARGET_COMPANY_ID) {
    throw new MigrationAbortError(
      'TARGET_TERMINAL_OTHER_TENANT',
      'La terminal destino pertenece a otra empresa',
      { terminalCompanyId: terminal.companyId, targetCompanyId: TARGET_COMPANY_ID },
    );
  }
  if (terminal.defaultWarehouseId !== TARGET_WAREHOUSE_ID) {
    throw new MigrationAbortError(
      'TARGET_TERMINAL_WAREHOUSE_MISMATCH',
      'La terminal destino apunta a otro almacén',
      { expected: TARGET_WAREHOUSE_ID, actual: terminal.defaultWarehouseId },
    );
  }

  const owner = snapshot.ownerUser;
  if (!owner) {
    throw new MigrationAbortError('TARGET_OWNER_MISSING', 'No existe el usuario propietario destino', {
      expectedOwnerUserId: TARGET_OWNER_USER_ID,
    });
  }
  if (owner.id !== TARGET_OWNER_USER_ID) {
    throw new MigrationAbortError('TARGET_OWNER_MISMATCH', 'El usuario propietario no coincide', {
      expectedOwnerUserId: TARGET_OWNER_USER_ID,
      actualOwnerUserId: owner.id,
    });
  }
  if (owner.companyId !== TARGET_COMPANY_ID) {
    throw new MigrationAbortError(
      'TARGET_OWNER_OTHER_TENANT',
      'El usuario propietario pertenece a otra empresa',
      { ownerCompanyId: owner.companyId, targetCompanyId: TARGET_COMPANY_ID },
    );
  }
  if (owner.blocked) {
    throw new MigrationAbortError('TARGET_OWNER_BLOCKED', 'El usuario propietario está bloqueado', {});
  }

  if (requireCleanBaseline) {
    assertCleanBaseline(snapshot);
  }
}

/** The tenant must still be empty for the entities this migrator writes. */
export function assertCleanBaseline(snapshot: TargetSnapshot): void {
  const expectedZero: Array<[string, number]> = [
    ['productsTotal', snapshot.baseline.productsTotal],
    ['productsNonArchived', snapshot.baseline.productsNonArchived],
    ['sales', snapshot.baseline.sales],
    ['saleItems', snapshot.baseline.saleItems],
    ['warehouseStocks', snapshot.baseline.warehouseStocks],
    ['inventoryMovements', snapshot.baseline.inventoryMovements],
    ['cashSessions', snapshot.baseline.cashSessions],
    ['cashboxDaily', snapshot.baseline.cashboxDaily],
    ['cashMovements', snapshot.baseline.cashMovements],
    ['clients', snapshot.baseline.clients],
    ['suppliers', snapshot.baseline.suppliers],
    ['purchaseOrders', snapshot.baseline.purchaseOrders],
    ['taxes', snapshot.baseline.taxes],
    ['ncfSequences', snapshot.baseline.ncfSequences],
  ];

  const dirty = expectedZero.filter(([, value]) => value !== 0);
  if (dirty.length > 0) {
    throw new MigrationAbortError(
      'TARGET_BASELINE_NOT_EMPTY',
      'La empresa destino ya contiene datos y no es una base limpia',
      { found: Object.fromEntries(dirty) },
    );
  }
}

/** The demo shift must be the locked one; a different demo-only shift means the source changed. */
export function assertDemoShiftIsLocked(demoShiftIds: readonly number[]): void {
  const sorted = [...demoShiftIds].sort((a, b) => a - b);
  if (sorted.length !== 1 || sorted[0] !== DEMO_CASH_SESSION_ID) {
    throw new MigrationAbortError(
      'DEMO_SHIFT_UNEXPECTED',
      'El conjunto de turnos solo-DEMO no coincide con lo verificado en Fase 2.5',
      { expected: [DEMO_CASH_SESSION_ID], actual: sorted },
    );
  }
}

/* ------------------------------------------------------------------ */
/* Execute-path confirmations (pure: no I/O)                          */
/* ------------------------------------------------------------------ */

export type ExecuteConfirmationInput = {
  execute: boolean;
  environment: string | null;
  targetCompanyId: string | null;
  targetWarehouseId: string | null;
  sourceSha256: string | null;
  confirmCompanyName: string | null;
  confirmWrite: boolean;
  /** Required ONLY for the production cutover profile: explicit confirmation token. */
  productionConfirmationToken?: string | null;
  /** SHA of the file actually opened (optional: verified later when present). */
  actualSourceSha256?: string;
};

/**
 * Every confirmation is mandatory and is validated against the locked values.
 * A missing/incorrect confirmation always aborts before any connection is opened.
 *
 * `--environment=production` alone is NEVER enough: production additionally requires the
 * explicit cutover token (derived from the locked company id + frozen source SHA) and, later,
 * the live connection metadata check (`assertProductionCutoverEnvironment`).
 */
export function assertExecuteConfirmations(params: ExecuteConfirmationInput): void {
  if (!params.execute) {
    throw new MigrationAbortError('EXECUTE_FLAG_REQUIRED', 'Falta --execute', {});
  }

  const environment = (params.environment ?? '').trim().toLowerCase();
  if (!environment) {
    throw new MigrationAbortError('ENVIRONMENT_REQUIRED', 'Falta --environment=uat|production', {});
  }
  if (environment === 'production' || environment === 'prod') {
    const expectedToken = productionCutoverConfirmationToken();
    if ((params.productionConfirmationToken ?? '').trim() !== expectedToken) {
      throw new MigrationAbortError(
        'PRODUCTION_CUTOVER_NOT_CONFIRMED',
        'Falta la confirmación explícita del cutover final (--confirm-production-cutover)',
        { requiredTokenFormat: expectedToken },
      );
    }
  } else if (environment !== 'uat') {
    throw new MigrationAbortError('ENVIRONMENT_NOT_UAT', 'El único entorno autorizado es uat', {
      environment,
    });
  }

  if (!params.targetCompanyId) {
    throw new MigrationAbortError('TARGET_COMPANY_NOT_CONFIRMED', 'Falta --target-company-id', {});
  }
  if (params.targetCompanyId.trim() !== TARGET_COMPANY_ID) {
    throw new MigrationAbortError('TARGET_COMPANY_MISMATCH', 'El company id confirmado no es el bloqueado', {
      expected: TARGET_COMPANY_ID,
      actual: params.targetCompanyId,
    });
  }

  if (!params.targetWarehouseId) {
    throw new MigrationAbortError('TARGET_WAREHOUSE_NOT_CONFIRMED', 'Falta --target-warehouse-id', {});
  }
  if (params.targetWarehouseId.trim() !== TARGET_WAREHOUSE_ID) {
    throw new MigrationAbortError('TARGET_WAREHOUSE_MISMATCH', 'El warehouse id confirmado no es el bloqueado', {
      expected: TARGET_WAREHOUSE_ID,
      actual: params.targetWarehouseId,
    });
  }

  if (!params.sourceSha256) {
    throw new MigrationAbortError('SOURCE_HASH_NOT_CONFIRMED', 'Falta --source-sha256', {});
  }
  if (
    params.actualSourceSha256 &&
    params.sourceSha256.trim().toUpperCase() !== params.actualSourceSha256.trim().toUpperCase()
  ) {
    throw new MigrationAbortError('SOURCE_HASH_MISMATCH', 'El SHA confirmado no coincide con el origen abierto', {
      confirmed: params.sourceSha256,
      actual: params.actualSourceSha256,
    });
  }

  if (!params.confirmCompanyName) {
    throw new MigrationAbortError('COMPANY_NAME_NOT_CONFIRMED', 'Falta --confirm-company-name', {});
  }
  if (params.confirmCompanyName.trim() !== TARGET_COMPANY_NAME) {
    throw new MigrationAbortError(
      'COMPANY_NAME_MISMATCH',
      'El nombre de empresa confirmado no coincide',
      { expected: TARGET_COMPANY_NAME, actual: params.confirmCompanyName },
    );
  }

  if (!params.confirmWrite) {
    throw new MigrationAbortError('WRITE_NOT_CONFIRMED', 'Falta --confirm-write', {});
  }
}
