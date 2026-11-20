import { BadRequestException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { R2Service } from '../../storage/r2.service';
import {
  detectEvidenceType,
  evidenceSha256,
  LicenseEvidenceStorage,
  MAX_EVIDENCE_BYTES,
} from './license-evidence.storage';

const pdf = () => Buffer.from('%PDF-1.7\ncontenido');
const png = () =>
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00]);
const jpg = () => Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);

describe('detectEvidenceType', () => {
  it('reconoce PDF, PNG y JPG por su firma', () => {
    expect(detectEvidenceType(pdf())).toEqual({
      mime: 'application/pdf',
      ext: 'pdf',
    });
    expect(detectEvidenceType(png())).toEqual({
      mime: 'image/png',
      ext: 'png',
    });
    expect(detectEvidenceType(jpg())).toEqual({
      mime: 'image/jpeg',
      ext: 'jpg',
    });
  });

  it('rechaza un archivo renombrado que no es imagen ni PDF', () => {
    expect(detectEvidenceType(Buffer.from('MZ\x90\x00execute'))).toBeNull();
  });

  it('calcula la huella del archivo', () => {
    expect(evidenceSha256(pdf())).toHaveLength(64);
    expect(evidenceSha256(pdf())).toBe(evidenceSha256(pdf()));
  });
});

describe('LicenseEvidenceStorage private R2 and legacy compatibility', () => {
  const companyA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const companyB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  const body = pdf();
  const sha256 = evidenceSha256(body);
  const objectKey = `license-evidence/companies/${companyA}/${sha256}.pdf`;
  let directory: string;
  let settings: Record<string, string>;
  let r2: { putObject: jest.Mock; getObject: jest.Mock };
  const config = () => ({ get: (key: string) => settings[key] }) as unknown as ConfigService;
  const storage = () => new LicenseEvidenceStorage(config(), r2 as unknown as R2Service);
  const save = (companyId = companyA) => storage().save({ companyId, buffer: body, sha256, ext: 'pdf' });

  beforeEach(async () => {
    directory = await mkdtemp(join(tmpdir(), 'license-private-r2-'));
    settings = { LICENSE_EVIDENCE_STORAGE_DRIVER: 'r2', LICENSE_EVIDENCE_R2_BUCKET: 'private-receipts', R2_BUCKET: 'public-media', LICENSE_EVIDENCE_DIR: directory };
    r2 = { putObject: jest.fn().mockResolvedValue({ ok: true }), getObject: jest.fn().mockResolvedValue({ body }) };
  });

  afterEach(async () => { await rm(directory, { recursive: true, force: true }); });

  it('writes to the dedicated bucket and persists a non-public driver-qualified key', async () => {
    await expect(save()).resolves.toEqual({ storageKey: `r2:${objectKey}` });
    expect(r2.putObject).toHaveBeenCalledWith({ bucket: 'private-receipts', objectKey, body, contentType: 'application/pdf' });
    await expect(storage().read(`r2:${objectKey}`, companyA)).resolves.toEqual(body);
    expect(r2.getObject).toHaveBeenCalledWith(objectKey, 'private-receipts');
  });

  it('keeps company object keys separate even for identical files', async () => {
    const a = await save(); const b = await save(companyB);
    expect(a.storageKey).not.toBe(b.storageKey);
    await expect(storage().read(a.storageKey, companyB)).rejects.toThrow('No encontramos');
    expect(r2.getObject).not.toHaveBeenCalled();
  });

  it.each(['', 'public-media'])('refuses a missing or shared media bucket (%s)', async bucket => {
    settings.LICENSE_EVIDENCE_R2_BUCKET = bucket;
    await expect(save()).rejects.toThrow('Almacenamiento privado');
    await expect(storage().read(`r2:${objectKey}`, companyA)).rejects.toThrow('Almacenamiento privado');
    expect(r2.putObject).not.toHaveBeenCalled();
    expect(r2.getObject).not.toHaveBeenCalled();
  });

  it('does not silently fall back to disk on an R2 failure', async () => {
    r2.putObject.mockRejectedValue(new Error('synthetic unavailable'));
    await expect(save()).rejects.toThrow('synthetic unavailable');
    settings.LICENSE_EVIDENCE_STORAGE_DRIVER = 'local';
    await expect(storage().read(`${companyA}/${sha256}.pdf`, companyA)).rejects.toMatchObject({ code: 'ENOENT' });
  });

  it('reads legacy files after enabling R2 and R2 files after reverting the write driver', async () => {
    delete settings.LICENSE_EVIDENCE_STORAGE_DRIVER;
    const legacy = await save();
    settings.LICENSE_EVIDENCE_STORAGE_DRIVER = 'r2';
    await expect(storage().read(legacy.storageKey, companyA)).resolves.toEqual(body);
    await expect(storage().read(legacy.storageKey, companyB)).rejects.toThrow('No encontramos');
    settings.LICENSE_EVIDENCE_STORAGE_DRIVER = 'local';
    await expect(storage().read(`r2:${objectKey}`, companyA)).resolves.toEqual(body);
    expect(r2.putObject).not.toHaveBeenCalled();
  });

  it.each(['../../etc/passwd', 'r2:uploads/companies/a/file.pdf', `r2:${objectKey}?bucket=other`, `r2:license-evidence/companies/${companyA}/../file.pdf`])('rejects an invalid persisted key: %s', async key => {
    await expect(storage().read(key, companyA)).rejects.toThrow('No encontramos');
    expect(r2.getObject).not.toHaveBeenCalled();
  });

  it('detects corruption and rejects wrong content identities before writing', async () => {
    r2.getObject.mockResolvedValue({ body: Buffer.from('corrupted') });
    await expect(storage().read(`r2:${objectKey}`, companyA)).rejects.toThrow('integridad');
    await expect(storage().save({ companyId: companyA, buffer: body, ext: 'pdf', sha256: '0'.repeat(64) })).rejects.toThrow('identificacion');
    expect(r2.putObject).not.toHaveBeenCalled();
  });

  it('rejects unknown drivers and unsafe company IDs', async () => {
    settings.LICENSE_EVIDENCE_STORAGE_DRIVER = 'unsupported';
    await expect(save()).rejects.toThrow('Almacenamiento de comprobantes no valido');
    await expect(save('../other')).rejects.toThrow('Empresa de comprobante no valida');
    expect(r2.putObject).not.toHaveBeenCalled();
  });
});

describe('LicenseEvidenceStorage.inspect', () => {
  const storage = new LicenseEvidenceStorage({
    get: () => undefined,
  } as unknown as ConfigService);

  it('acepta un PDF valido y devuelve su firma', () => {
    const result = storage.inspect(pdf(), 'comprobante.pdf');
    expect(result).toMatchObject({ mime: 'application/pdf', ext: 'pdf' });
    expect(result.sizeBytes).toBe(pdf().length);
  });

  it('rechaza archivo vacio, demasiado grande o de tipo no permitido', () => {
    expect(() => storage.inspect(Buffer.alloc(0), 'vacio.pdf')).toThrow(
      BadRequestException,
    );
    expect(() =>
      storage.inspect(Buffer.alloc(MAX_EVIDENCE_BYTES + 1, 0x25), 'grande.pdf'),
    ).toThrow(BadRequestException);
    expect(() =>
      storage.inspect(Buffer.from('#!/bin/sh\nrm -rf'), 'script.pdf'),
    ).toThrow(BadRequestException);
  });

  it('no deja salir del directorio de comprobantes', () => {
    expect(() => storage.resolveStorageKey('../../etc/passwd')).not.toThrow();
    const resolved = storage.resolveStorageKey('../../etc/passwd');
    expect(resolved.startsWith(storage.rootDir())).toBe(true);
  });
});
