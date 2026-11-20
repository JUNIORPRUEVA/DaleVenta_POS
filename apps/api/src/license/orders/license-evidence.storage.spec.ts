import { BadRequestException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
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
