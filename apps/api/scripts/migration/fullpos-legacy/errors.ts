/**
 * Error types used by the legacy migrator.
 *
 * `MigrationAbortError` is thrown by every guard that protects the target tenant,
 * the source database and the source hash. It always means: nothing was written,
 * nothing may be written, stop and report.
 */

export class MigrationAbortError extends Error {
  readonly code: string;
  readonly details: Record<string, unknown>;

  constructor(code: string, message: string, details: Record<string, unknown> = {}) {
    super(`${code}: ${message}`);
    this.name = 'MigrationAbortError';
    this.code = code;
    this.details = details;
  }
}

export class MigrationNoGoError extends Error {
  readonly failures: string[];

  constructor(message: string, failures: string[]) {
    super(`${message}\n${failures.map((line) => `  - ${line}`).join('\n')}`);
    this.name = 'MigrationNoGoError';
    this.failures = failures;
  }
}
