import {
  BadRequestException,
  Controller,
  Get,
  NotFoundException,
  Param,
  Query,
  Req,
  Res,
  UseGuards,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AuthGuard } from '@nestjs/passport';
import type { Request, Response } from 'express';
import * as fs from 'node:fs';
import { createReadStream } from 'node:fs';
import { join } from 'node:path';
import { requireTenant, type TenantUser } from '../auth/tenant-context';
import { PrismaService } from '../prisma/prisma.service';
import { R2Service } from './r2.service';

@Controller('media')
@UseGuards(AuthGuard('jwt'))
export class MediaController {
  private readonly uploadDir: string;

  constructor(
    private readonly prisma: PrismaService,
    private readonly r2: R2Service,
    config: ConfigService,
  ) {
    this.uploadDir = this.resolveUploadDir(config);
  }

  @Get('products/:productId')
  async productImage(
    @Req() req: Request,
    @Param('productId') productId: string,
    @Res() res: Response,
  ) {
    const companyId = requireTenant(req.user as TenantUser);
    const product = await this.prisma.product.findFirst({
      where: { id: productId, companyId },
    });
    if (!product) throw new NotFoundException('Producto no encontrado');

    const productAny = product as any;
    const objectKey =
      this.normalizeObjectKey(productAny.imageKey) ??
      this.objectKeyFromLegacyImage(product.imagen);
    if (!objectKey) throw new NotFoundException('Producto sin imagen');

    await this.serveObjectKey({
      objectKey,
      companyId,
      res,
      legacyMimeType: productAny.imageMimeType,
    });
    // eslint-disable-next-line no-console
    console.log(`[media] product image served companyId=${companyId} productId=${productId} key=${objectKey}`);
  }

  @Get('object')
  async objectImage(
    @Req() req: Request,
    @Query('key') rawKey: string | undefined,
    @Res() res: Response,
  ) {
    const companyId = requireTenant(req.user as TenantUser);
    const objectKey = this.normalizeObjectKey(rawKey);
    if (!objectKey) throw new BadRequestException('key inválida');

    await this.serveObjectKey({ objectKey, companyId, res });
  }

  private async serveObjectKey(params: {
    objectKey: string;
    companyId: string;
    res: Response;
    legacyMimeType?: string | null;
  }) {
    this.assertTenantObjectKey(params.objectKey, params.companyId);

    try {
      const object = await this.r2.getObjectStream(params.objectKey);
      params.res.setHeader('Content-Type', object.contentType ?? params.legacyMimeType ?? 'application/octet-stream');
      if (object.contentLength != null) {
        params.res.setHeader('Content-Length', String(object.contentLength));
      }
      if (object.etag) {
        params.res.setHeader('ETag', object.etag);
      }
      params.res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
      // eslint-disable-next-line no-console
      console.log(`[R2] GetObject successful key=${params.objectKey}`);
      object.body.pipe(params.res);
      return;
    } catch (error) {
      // eslint-disable-next-line no-console
      console.warn(`[media] R2 GetObject failed; trying legacy local fallback key=${params.objectKey}`, error);
    }

    const localPath = this.localPathForObjectKey(params.objectKey);
    if (!localPath || !fs.existsSync(localPath)) {
      throw new NotFoundException('Imagen no encontrada');
    }

    const stat = fs.statSync(localPath);
    params.res.setHeader('Content-Type', params.legacyMimeType ?? this.guessMimeType(localPath));
    params.res.setHeader('Content-Length', String(stat.size));
    params.res.setHeader('Cache-Control', 'public, max-age=3600');
    // eslint-disable-next-line no-console
    console.warn(`[media] legacy local fallback used key=${params.objectKey}`);
    createReadStream(localPath).pipe(params.res);
  }

  private normalizeObjectKey(raw?: string | null): string | null {
    const value = (raw ?? '').trim().replace(/\\/g, '/');
    if (!value || value.includes('..') || value.startsWith('/')) return null;
    const withoutLeadingUploads = value.startsWith('uploads/')
      ? value
      : value.startsWith('./uploads/')
        ? value.substring(2)
        : null;
    return withoutLeadingUploads;
  }

  private objectKeyFromLegacyImage(raw?: string | null): string | null {
    const value = (raw ?? '').trim().replace(/\\/g, '/');
    if (!value) return null;
    const marker = '/uploads/';
    const markerIndex = value.indexOf(marker);
    if (markerIndex >= 0) return this.normalizeObjectKey(value.substring(markerIndex + 1));
    if (value.startsWith('uploads/')) return this.normalizeObjectKey(value);
    if (value.startsWith('./uploads/')) return this.normalizeObjectKey(value.substring(2));
    return null;
  }

  private assertTenantObjectKey(objectKey: string, companyId: string) {
    const expectedPrefix = `uploads/companies/${companyId}/`;
    if (!objectKey.startsWith(expectedPrefix)) {
      throw new NotFoundException('Imagen no encontrada');
    }
  }

  private localPathForObjectKey(objectKey: string): string | null {
    const normalized = this.normalizeObjectKey(objectKey);
    if (!normalized) return null;
    const withoutUploads = normalized.substring('uploads/'.length);
    return join(this.uploadDir, ...withoutUploads.split('/'));
  }

  private resolveUploadDir(config: ConfigService): string {
    const fromEnv = (config.get<string>('UPLOAD_DIR') ?? '').trim();
    const volumeDir = '/uploads';
    const volumeExists = fs.existsSync(volumeDir);

    if (fromEnv.length > 0) {
      if ((fromEnv === './uploads' || fromEnv === 'uploads') && volumeExists) {
        return volumeDir;
      }
      return fromEnv;
    }

    return volumeExists ? volumeDir : join(process.cwd(), 'uploads');
  }

  private guessMimeType(filePath: string) {
    const value = filePath.toLowerCase();
    if (value.endsWith('.png')) return 'image/png';
    if (value.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
