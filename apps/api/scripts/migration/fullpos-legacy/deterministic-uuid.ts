/**
 * Deterministic UUIDv5 derivation (RFC 4122) for the legacy migration.
 *
 * Requirements covered:
 *  - same source row            -> same UUID (rerun-safe / idempotent)
 *  - same legacy id, other table-> different UUID (table is part of the name)
 *  - different tenant           -> different UUID (company is part of the name)
 *  - rollback                   -> the exact imported ids are recomputable from the manifest
 *
 * No global mapping table is required, and the namespace is immutable.
 */

import { createHash } from 'node:crypto';
import {
  MIGRATION_NAMESPACE_UUID,
  SOURCE_SYSTEM,
  TARGET_COMPANY_ID,
} from './constants';

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function uuidToBytes(uuid: string): Buffer {
  if (!UUID_PATTERN.test(uuid)) {
    throw new Error(`UUID inválido: ${uuid}`);
  }
  return Buffer.from(uuid.replace(/-/g, ''), 'hex');
}

export function bytesToUuid(bytes: Buffer): string {
  if (bytes.length !== 16) throw new Error('Se esperaban 16 bytes para un UUID');
  const hex = bytes.toString('hex');
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20, 32),
  ].join('-');
}

/** RFC 4122 name-based UUID (version 5, SHA-1). */
export function uuidV5(namespaceUuid: string, name: string): string {
  const namespaceBytes = uuidToBytes(namespaceUuid);
  const digest = createHash('sha1')
    .update(Buffer.concat([namespaceBytes, Buffer.from(name, 'utf8')]))
    .digest();
  const bytes = Buffer.from(digest.subarray(0, 16));
  bytes[6] = (bytes[6] & 0x0f) | 0x50; // version 5
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  return bytesToUuid(bytes);
}

/** Canonical name for one legacy row inside one tenant. */
export function buildEntityName(params: {
  companyId: string;
  sourceSystem: string;
  legacyTable: string;
  legacyId: string | number;
}): string {
  return [
    params.companyId,
    params.sourceSystem,
    params.legacyTable,
    String(params.legacyId),
  ].join('|');
}

/** Deterministic target UUID for a legacy row of the locked tenant. */
export function deriveTargetId(legacyTable: string, legacyId: string | number): string {
  return deriveTargetIdForTenant({
    companyId: TARGET_COMPANY_ID,
    sourceSystem: SOURCE_SYSTEM,
    legacyTable,
    legacyId,
  });
}

export function deriveTargetIdForTenant(params: {
  companyId: string;
  sourceSystem: string;
  legacyTable: string;
  legacyId: string | number;
}): string {
  const name = buildEntityName(params);
  return uuidV5(MIGRATION_NAMESPACE_UUID, name);
}
