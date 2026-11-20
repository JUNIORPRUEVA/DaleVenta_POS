import { BadRequestException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join, resolve, sep } from 'node:path';
import { EVIDENCE_MAX_BYTES } from './license-evidence.validation';

/**
 * Tope unico por comprobante: 8 MB. El almacen y la validacion documental usan
 * el **mismo** numero; antes el almacen aceptaba 10 MB y la validacion 8, asi
 * que el mensaje al cliente no coincidia con lo que se comprobaba.
 */
export const MAX_EVIDENCE_BYTES = EVIDENCE_MAX_BYTES;

export type EvidenceType = { mime: string; ext: string };

/**
 * El tipo se decide por la **firma del archivo**, no por la extension: un
 * ejecutable renombrado a `.pdf` no pasa.
 */
export function detectEvidenceType(buffer: Buffer): EvidenceType | null {
  if (!buffer || buffer.length < 4) return null;
  if (
    buffer.length >= 4 &&
    buffer[0] === 0x25 &&
    buffer[1] === 0x50 &&
    buffer[2] === 0x44 &&
    buffer[3] === 0x46
  ) {
    return { mime: 'application/pdf', ext: 'pdf' };
  }
  if (buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
    return { mime: 'image/jpeg', ext: 'jpg' };
  }
  if (
    buffer.length >= 8 &&
    buffer[0] === 0x89 &&
    buffer[1] === 0x50 &&
    buffer[2] === 0x4e &&
    buffer[3] === 0x47 &&
    buffer[4] === 0x0d &&
    buffer[5] === 0x0a &&
    buffer[6] === 0x1a &&
    buffer[7] === 0x0a
  ) {
    return { mime: 'image/png', ext: 'png' };
  }
  return null;
}

export function evidenceSha256(buffer: Buffer) {
  return createHash('sha256').update(buffer).digest('hex');
}

/**
 * Guarda los comprobantes en un directorio **privado**. Nunca en `/uploads`,
 * que se sirve sin autenticacion: un comprobante bancario no puede quedar
 * accesible por URL.
 */
@Injectable()
export class LicenseEvidenceStorage {
  constructor(private readonly config: ConfigService) {}

  rootDir() {
    const configured =
      this.config.get<string>('LICENSE_EVIDENCE_DIR') ??
      process.env.LICENSE_EVIDENCE_DIR ??
      '';
    const trimmed = configured.trim();
    return resolve(trimmed || join(process.cwd(), 'storage', 'license-evidence'));
  }

  /** Valida el archivo y devuelve su firma y su huella. */
  inspect(buffer: Buffer, originalName: string) {
    if (!buffer || buffer.length === 0) {
      throw new BadRequestException({
        code: 'EVIDENCE_EMPTY',
        message: 'El archivo del comprobante esta vacio.',
      });
    }
    if (buffer.length > MAX_EVIDENCE_BYTES) {
      throw new BadRequestException({
        code: 'EVIDENCE_TOO_LARGE',
        message: `El comprobante supera el maximo de ${
          MAX_EVIDENCE_BYTES / (1024 * 1024)
        } MB.`,
        maxBytes: MAX_EVIDENCE_BYTES,
      });
    }
    const type = detectEvidenceType(buffer);
    if (!type) {
      throw new BadRequestException({
        code: 'EVIDENCE_TYPE_NOT_ALLOWED',
        message: 'Solo se aceptan imagenes JPG, PNG o documentos PDF.',
        originalName: originalName || null,
      });
    }
    return { ...type, sha256: evidenceSha256(buffer), sizeBytes: buffer.length };
  }

  async save(input: {
    companyId: string;
    buffer: Buffer;
    ext: string;
    sha256: string;
  }) {
    const storageKey = `${input.companyId}/${input.sha256}.${input.ext}`;
    const absolutePath = this.resolveStorageKey(storageKey);
    await mkdir(this.resolveStorageKey(input.companyId), { recursive: true });
    await writeFile(absolutePath, input.buffer);
    return { storageKey, absolutePath };
  }

  async read(storageKey: string) {
    return readFile(this.resolveStorageKey(storageKey));
  }

  resolveStorageKey(storageKey: string) {
    const root = this.rootDir();
    const parts = storageKey
      .split(/[\\/]+/)
      .map((part) => part.trim())
      .filter((part) => part && part !== '.' && part !== '..');
    const absolute = resolve(root, ...parts);
    if (absolute !== root && !absolute.startsWith(`${root}${sep}`)) {
      throw new BadRequestException('Ruta de comprobante invalida');
    }
    return absolute;
  }
}
