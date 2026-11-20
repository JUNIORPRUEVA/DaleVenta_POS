import { BadRequestException, Injectable, InternalServerErrorException, NotFoundException, Optional } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join, resolve, sep } from 'node:path';
import { EVIDENCE_MAX_BYTES } from './license-evidence.validation';
import { R2Service } from '../../storage/r2.service';

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
 * Guarda los comprobantes en un directorio o bucket **privado**. Nunca en `/uploads`,
 * que se sirve sin autenticacion: un comprobante bancario no puede quedar
 * accesible por URL.
 */
@Injectable()
export class LicenseEvidenceStorage {
  private privateR2?: R2Service;

  constructor(
    private readonly config: ConfigService,
    @Optional() private readonly r2?: R2Service,
  ) {}

  private privateBucket() {
    const bucket = this.config.get<string>('LICENSE_EVIDENCE_R2_BUCKET')?.trim();
    const mediaBucket = (this.config.get<string>('R2_BUCKET') ?? this.config.get<string>('R2_BUCKET_NAME') ?? '').trim();
    if (!bucket || bucket === mediaBucket || !this.r2) {
      throw new InternalServerErrorException('Almacenamiento privado de comprobantes no configurado.');
    }
    return bucket;
  }

  private transport() {
    const accessKeyId = this.config.get<string>('LICENSE_EVIDENCE_R2_ACCESS_KEY_ID')?.trim();
    const secretAccessKey = this.config.get<string>('LICENSE_EVIDENCE_R2_SECRET_ACCESS_KEY')?.trim();
    if (Boolean(accessKeyId) !== Boolean(secretAccessKey)) {
      throw new InternalServerErrorException('Credencial privada de comprobantes incompleta.');
    }
    if (!accessKeyId) return this.r2!;
    if (!this.privateR2) {
      this.privateR2 = new R2Service(new ConfigService({
        R2_ENDPOINT: this.config.get<string>('R2_ENDPOINT') ?? this.config.get<string>('R2_S3_ENDPOINT') ?? this.config.get<string>('CLOUDFLARE_R2_ENDPOINT'),
        R2_REGION: this.config.get<string>('R2_REGION') ?? 'auto',
        R2_ACCESS_KEY_ID: accessKeyId,
        R2_SECRET_ACCESS_KEY: secretAccessKey,
        R2_BUCKET: this.privateBucket(),
      }));
    }
    return this.privateR2;
  }

  private driver() {
    const driver = this.config.get<string>('LICENSE_EVIDENCE_STORAGE_DRIVER')?.trim() || 'local';
    if (driver !== 'local' && driver !== 'r2') {
      throw new InternalServerErrorException('Almacenamiento de comprobantes no valido.');
    }
    return driver;
  }

  private assertCompany(companyId: string) {
    if (!/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(companyId)) {
      throw new BadRequestException('Empresa de comprobante no valida.');
    }
  }

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
    this.assertCompany(input.companyId);
    const inspected = this.inspect(input.buffer, '');
    if (inspected.sha256 !== input.sha256 || inspected.ext !== input.ext) {
      throw new BadRequestException('El contenido del comprobante no coincide con su identificacion.');
    }
    if (this.driver() === 'r2') {
      const bucket = this.privateBucket();
      const objectKey = `license-evidence/companies/${input.companyId}/${input.sha256}.${input.ext}`;
      await this.transport().putObject({ bucket, objectKey, body: input.buffer, contentType: inspected.mime });
      // Persist the driver with the key so switching defaults never hides old files.
      return { storageKey: `r2:${objectKey}` };
    }
    const storageKey = `${input.companyId}/${input.sha256}.${input.ext}`;
    const absolutePath = this.resolveStorageKey(storageKey);
    await mkdir(this.resolveStorageKey(input.companyId), { recursive: true });
    await writeFile(absolutePath, input.buffer);
    return { storageKey, absolutePath };
  }

  async read(storageKey: string, companyId: string) {
    this.assertCompany(companyId);
    const remote = storageKey.startsWith('r2:');
    const key = remote ? storageKey.slice(3) : storageKey;
    const relative = remote ? key.replace(/^license-evidence\/companies\//, '') : key;
    const match = /^([0-9a-f-]{36})\/([0-9a-f]{64})\.(pdf|png|jpg)$/.exec(relative);
    if (!match || match[1] !== companyId || (remote && !key.startsWith('license-evidence/companies/'))) {
      throw new NotFoundException('No encontramos ese comprobante.');
    }
    const bucket = remote ? this.privateBucket() : null;
    const buffer = remote
      ? (await this.transport().getObject(key, bucket!)).body
      : await readFile(this.resolveStorageKey(key));
    if (buffer.length > MAX_EVIDENCE_BYTES || evidenceSha256(buffer) !== match[2]) {
      throw new InternalServerErrorException('No se pudo verificar la integridad del comprobante.');
    }
    return buffer;
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
