import {
  BadRequestException,
  Controller,
  Get,
  NotFoundException,
  Query,
  Res,
} from '@nestjs/common';
import type { Response } from 'express';
import * as fs from 'node:fs';
import { extname, join } from 'node:path';
import { R2Service } from '../storage/r2.service';

type FiscalImageCandidates = {
  localPaths: string[];
  r2Keys: string[];
};

@Controller('public/contabilidad')
export class ContabilidadPublicController {
  constructor(private readonly r2: R2Service) {}

  @Get('object')
  async getObjectByKey(
    @Query('key') rawKey: string | undefined,
    @Res() res: Response,
  ) {
    const key = (rawKey ?? '').trim();
    if (key.length === 0) {
      throw new BadRequestException('key es requerido');
    }

    try {
      const object = await this.r2.getObject(key);
      res.setHeader('Content-Type', object.contentType ?? 'application/octet-stream');
      if (object.contentLength != null) {
        res.setHeader('Content-Length', String(object.contentLength));
      }
      res.send(object.body);
      return;
    } catch {
      throw new NotFoundException('No se encontró el archivo solicitado');
    }
  }

  @Get('fiscal-invoices/image')
  async getFiscalInvoiceImage(
    @Query('url') rawUrl: string | undefined,
    @Res() res: Response,
  ) {
    const raw = (rawUrl ?? '').trim();
    if (raw.length === 0) {
      throw new BadRequestException('url es requerido');
    }

    const candidates = this.buildCandidates(raw);

    for (const localRelative of candidates.localPaths) {
      const absolutePath = join(this.resolveUploadDir(), ...localRelative.split('/'));
      if (!fs.existsSync(absolutePath)) continue;

      const contentType = this.guessContentType(absolutePath);
      res.setHeader('Content-Type', contentType);
      res.sendFile(absolutePath);
      return;
    }

    for (const objectKey of candidates.r2Keys) {
      try {
        const object = await this.r2.getObject(objectKey);
        res.setHeader('Content-Type', object.contentType ?? 'application/octet-stream');
        if (object.contentLength != null) {
          res.setHeader('Content-Length', String(object.contentLength));
        }
        res.send(object.body);
        return;
      } catch {
        // Try the next candidate.
      }
    }

    throw new NotFoundException('No se encontró la imagen fiscal');
  }

  private buildCandidates(raw: string): FiscalImageCandidates {
    const normalized = raw.replaceAll('\\', '/').trim();

    let path = normalized;
    if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      try {
        path = new URL(normalized).pathname;
      } catch {
        path = normalized;
      }
    }

    const cleanPath = path.replace(/\/+/g, '/').trim();
    const noLeadingSlash = cleanPath.replace(/^\/+/, '');
    const noUploadsPrefix = noLeadingSlash.startsWith('uploads/')
      ? noLeadingSlash.substring('uploads/'.length)
      : noLeadingSlash;

    const localPaths = new Set<string>();
    const r2Keys = new Set<string>();

    if (noLeadingSlash.startsWith('uploads/')) {
      localPaths.add(noLeadingSlash.substring('uploads/'.length));
      r2Keys.add(noLeadingSlash);
    }

    if (noUploadsPrefix.length > 0) {
      localPaths.add(noUploadsPrefix);
      r2Keys.add(noUploadsPrefix);
      r2Keys.add(`uploads/${noUploadsPrefix}`);
    }

    return {
      localPaths: Array.from(localPaths),
      r2Keys: Array.from(r2Keys),
    };
  }

  private resolveUploadDir(): string {
    const volumeDir = '/uploads';
    const volumeExists = fs.existsSync(volumeDir);
    const uploadDirEnv = (process.env['UPLOAD_DIR'] ?? '').trim();

    if (uploadDirEnv.length > 0) {
      if ((uploadDirEnv === './uploads' || uploadDirEnv === 'uploads') && volumeExists) {
        return volumeDir;
      }
      return uploadDirEnv;
    }

    if (volumeExists) return volumeDir;
    return join(process.cwd(), 'uploads');
  }

  private guessContentType(filePath: string): string {
    const ext = extname(filePath).toLowerCase();
    if (ext === '.png') return 'image/png';
    if (ext === '.webp') return 'image/webp';
    if (ext === '.jpg' || ext === '.jpeg') return 'image/jpeg';
    if (ext === '.pdf') return 'application/pdf';
    return 'application/octet-stream';
  }
}
