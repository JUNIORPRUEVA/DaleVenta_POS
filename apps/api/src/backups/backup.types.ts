export const BACKUP_FORMAT_VERSION = 2;
export const BACKUP_PRODUCT = "DaleVentas POS / FullPOS Cloud";
export const BACKUP_MINIMUM_COMPATIBLE_VERSION = "1.0.5";
export const AUTOMATIC_BACKUP_INTERVAL_DAYS = 2;
export const MAX_AUTOMATIC_BACKUPS_PER_COMPANY = 15;

export type BackupTypeName = "MANUAL" | "AUTOMATIC" | "PRE_RESTORE_SAFETY";
export type BackupStatusName = "PENDING" | "COMPLETE" | "FAILED";
export type BackupValidationStatus = "VALID" | "VALID_WITH_WARNINGS" | "INVALID";
export type BackupFormatKind = "CANONICAL" | "LEGACY" | "INVALID";

export type BackupModulePayload = {
  name: string;
  fileName: string;
  records: unknown[];
  recordCount: number;
  checksum: string;
};

export type BackupManifest = {
  backupFormatVersion: number;
  backupId: string;
  product: string;
  environment: string;
  createdAt: string;
  appVersion: string | null;
  backendVersion: string | null;
  minimumCompatibleVersion: string;
  companyId: string;
  companyNameSnapshot: string;
  backupType: BackupTypeName;
  backupStatus: BackupStatusName;
  modules: string[];
  recordCounts: Record<string, number>;
  checksums: Record<string, string>;
};

export type BackupArchiveBuildResult = {
  archive: Buffer;
  manifest: BackupManifest;
  modules: BackupModulePayload[];
  archiveChecksum: string;
};

export type BackupValidationResult = {
  status: BackupValidationStatus;
  format: BackupFormatKind;
  errors: string[];
  warnings: string[];
  manifest: BackupManifest | null;
};
