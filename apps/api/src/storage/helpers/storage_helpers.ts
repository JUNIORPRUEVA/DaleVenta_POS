import { BadRequestException } from '@nestjs/common';
import { basename, extname } from 'node:path';
import { randomUUID } from 'node:crypto';

export type MediaType = 'image' | 'video' | 'document';

export const ALLOWED_CONTENT_TYPES = [
  'image/jpeg',
  'image/png',
  'image/webp',
  'video/mp4',
  'video/quicktime',
  'video/webm',
  'application/pdf',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'text/plain',
] as const;

export const ALLOWED_KINDS = [
  'reference_photo',
  'evidence_before',
  'evidence_during',
  'evidence_after',
  'evidence_final',
  'client_signature',
  'service_invoice_custom',
  'service_warranty_custom',
  'technical_document',
  'video_evidence',
  'quote_attachment',
  'other',
] as const;

export type StorageKind = (typeof ALLOWED_KINDS)[number];

export function isAllowedContentType(value: string): boolean {
  return (ALLOWED_CONTENT_TYPES as readonly string[]).includes(value.trim());
}

export function inferMediaType(mimeType: string): MediaType {
  const v = mimeType.trim().toLowerCase();
  if (v.startsWith('image/')) return 'image';
  if (v.startsWith('video/')) return 'video';
  return 'document';
}

export function sanitizeFileName(fileName: string, { maxLen = 120 }: { maxLen?: number } = {}) {
  const raw = basename((fileName ?? '').trim());
  const safeBase = raw.length > 0 ? raw : 'file';

  const ext = extname(safeBase);
  const nameNoExt = ext.length > 0 ? safeBase.slice(0, -ext.length) : safeBase;

  // Remove diacritics (áéíóú -> aeiou)
  const normalized = nameNoExt.normalize('NFD').replace(/[\u0300-\u036f]/g, '');

  // Replace unsupported chars, collapse dashes.
  const cleaned = normalized
    .replace(/[^A-Za-z0-9._-]+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^[-.]+|[-.]+$/g, '');

  const base = cleaned.length > 0 ? cleaned : 'file';
  const finalBase = base.toLowerCase().slice(0, Math.max(1, maxLen));

  const finalExt = ext
    .toLowerCase()
    .replace(/[^a-z0-9.]/g, '')
    .slice(0, 12);

  return `${finalBase}${finalExt}`;
}

export function buildServiceObjectKey(serviceId: string, fileName: string, now: Date = new Date()) {
  const yyyy = String(now.getUTCFullYear());
  const mm = String(now.getUTCMonth() + 1).padStart(2, '0');
  const ts = Math.floor(now.getTime() / 1000);
  const safe = sanitizeFileName(fileName);
  return `services/${serviceId}/${yyyy}/${mm}/${ts}-${safe}`;
}

export function sanitizeObjectKeySegment(value: string, fallback = 'general') {
  const cleaned = (value ?? '')
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9_-]+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^[-_]+|[-_]+$/g, '');

  return cleaned || fallback;
}

export function tenantUploadPrefix(companyId: string) {
  const normalizedCompanyId = (companyId ?? '').trim();
  if (!normalizedCompanyId) {
    throw new BadRequestException('Empresa requerida para guardar archivo');
  }

  return `companies/${sanitizeObjectKeySegment(normalizedCompanyId, 'company')}`;
}

export function buildTenantObjectKey(params: {
  companyId: string;
  area: string;
  kind?: string;
  ownerId?: string | null;
  fileName: string;
  extension: string;
  now?: Date;
}) {
  const now = params.now ?? new Date();
  const yyyy = String(now.getUTCFullYear());
  const mm = String(now.getUTCMonth() + 1).padStart(2, '0');
  const original = sanitizeFileName(params.fileName || 'file');
  const baseName = original.replace(/\.[^/.]+$/, '') || 'file';
  const safeExt = params.extension.startsWith('.')
    ? params.extension.toLowerCase()
    : `.${params.extension.toLowerCase()}`;
  const owner = sanitizeObjectKeySegment(params.ownerId ?? 'shared', 'shared');

  return [
    tenantUploadPrefix(params.companyId),
    sanitizeObjectKeySegment(params.area),
    sanitizeObjectKeySegment(params.kind ?? 'general'),
    owner,
    yyyy,
    mm,
    `${randomUUID()}-${baseName}${safeExt}`,
  ].join('/');
}

export function assertValidObjectKeyForService(serviceId: string, objectKey: string) {
  const key = (objectKey ?? '').trim();
  if (!key) throw new BadRequestException('objectKey requerido');
  if (key.startsWith('/') || key.includes('..') || key.includes('\\')) {
    throw new BadRequestException('objectKey inválido');
  }
  const expectedPrefix = `services/${serviceId}/`;
  if (!key.startsWith(expectedPrefix)) {
    throw new BadRequestException('objectKey no corresponde al servicio');
  }
}

export function parseIntEnv(name: string, fallback: number) {
  const raw = (process.env[name] ?? '').trim();
  if (!raw) return fallback;
  const n = Number(raw);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : fallback;
}
