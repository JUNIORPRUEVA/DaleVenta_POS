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
import sharp from 'sharp';
import { requireTenant, type TenantUser } from '../auth/tenant-context';
import { PrismaService } from '../prisma/prisma.service';
import { R2Service } from './r2.service';

@Controller('media')
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
    @Param('productId') productId: string,
    @Query('w') rawWidth: string | undefined,
    @Query('h') rawHeight: string | undefined,
    @Res() res: Response,
  ) {
    const product = await this.prisma.product.findFirst({ where: { id: productId } });
    if (!product) throw new NotFoundException('Producto no encontrado');
    const companyId = product.companyId;
    if (!companyId) throw new NotFoundException('Producto sin empresa');

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
      resize: this.parseResize(rawWidth, rawHeight),
    });
    // eslint-disable-next-line no-console
    console.log(`[media] product image served companyId=${companyId} productId=${productId} key=${objectKey}`);
  }

  // Ruta pública para fotos de perfil (avatares). A diferencia de /media/object
  // (que exige JWT), las fotos de perfil se sirven de forma pública para que
  // carguen en cualquier plataforma. Solo se permite el patrón users/profile;
  // cédula, licencia y expediente siguen protegidos con autenticación.
  @Get('photo')
  async publicProfilePhoto(
    @Query('key') rawKey: string | undefined,
    @Res() res: Response,
  ) {
    const objectKey = this.normalizeObjectKey(rawKey);
    if (!objectKey || !objectKey.includes('/users/profile/')) {
      throw new NotFoundException('Imagen no encontrada');
    }
    const companyId = this.companyIdFromObjectKey(objectKey);
    if (!companyId) throw new NotFoundException('Imagen no encontrada');

    await this.serveObjectKey({ objectKey, companyId, res });
  }

  private companyIdFromObjectKey(objectKey: string): string | null {
    const prefix = 'uploads/companies/';
    if (!objectKey.startsWith(prefix)) return null;
    const rest = objectKey.substring(prefix.length);
    const companyId = rest.split('/')[0] ?? '';
    return companyId.length > 0 ? companyId : null;
  }

  @UseGuards(AuthGuard('jwt'))
  @Get('object')
  async objectImage(
    @Req() req: Request,
    @Query('key') rawKey: string | undefined,
    @Query('w') rawWidth: string | undefined,
    @Query('h') rawHeight: string | undefined,
    @Res() res: Response,
  ) {
    const companyId = requireTenant(req.user as TenantUser);
    const objectKey = this.normalizeObjectKey(rawKey);
    if (!objectKey) throw new BadRequestException('key inválida');

    await this.serveObjectKey({
      objectKey,
      companyId,
      res,
      resize: this.parseResize(rawWidth, rawHeight),
    });
  }

  private async serveObjectKey(params: {
    objectKey: string;
    companyId: string;
    res: Response;
    legacyMimeType?: string | null;
    resize?: { width: number; height: number } | null;
  }) {
    this.assertTenantObjectKey(params.objectKey, params.companyId);

    try {
      if (params.resize) {
        const object = await this.r2.getObject(params.objectKey);
        await this.serveResizedImage({
          buffer: object.body,
          contentType: object.contentType ?? params.legacyMimeType,
          resize: params.resize,
          res: params.res,
          cacheControl: 'public, max-age=31536000, immutable',
        });
        return;
      }

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
    if (params.resize) {
      await this.serveResizedImage({
        buffer: fs.readFileSync(localPath),
        contentType: params.legacyMimeType ?? this.guessMimeType(localPath),
        resize: params.resize,
        res: params.res,
        cacheControl: 'public, max-age=3600',
      });
      return;
    }

    params.res.setHeader('Content-Type', params.legacyMimeType ?? this.guessMimeType(localPath));
    params.res.setHeader('Content-Length', String(stat.size));
    params.res.setHeader('Cache-Control', 'public, max-age=3600');
    // eslint-disable-next-line no-console
    console.warn(`[media] legacy local fallback used key=${params.objectKey}`);
    createReadStream(localPath).pipe(params.res);
  }

  private parseResize(rawWidth?: string, rawHeight?: string): { width: number; height: number } | null {
    const width = Number.parseInt((rawWidth ?? '').trim(), 10);
    const height = Number.parseInt((rawHeight ?? '').trim(), 10);
    if (!Number.isFinite(width) || !Number.isFinite(height)) return null;
    const safeWidth = Math.min(Math.max(width, 48), 512);
    const safeHeight = Math.min(Math.max(height, 48), 512);
    return { width: safeWidth, height: safeHeight };
  }

  private async serveResizedImage(params: {
    buffer: Buffer;
    contentType?: string | null;
    resize: { width: number; height: number };
    res: Response;
    cacheControl: string;
  }) {
    const type = (params.contentType ?? '').toLowerCase();
    if (!type.startsWith('image/')) {
      params.res.setHeader('Content-Type', params.contentType ?? 'application/octet-stream');
      params.res.setHeader('Content-Length', String(params.buffer.length));
      params.res.setHeader('Cache-Control', params.cacheControl);
      params.res.send(params.buffer);
      return;
    }

    const output = await sharp(params.buffer, { failOn: 'none' })
      .rotate()
      .resize({
        width: params.resize.width,
        height: params.resize.height,
        fit: 'inside',
        withoutEnlargement: true,
      })
      .webp({ quality: 78, effort: 4 })
      .toBuffer();

    params.res.setHeader('Content-Type', 'image/webp');
    params.res.setHeader('Content-Length', String(output.length));
    params.res.setHeader('Cache-Control', params.cacheControl);
    params.res.send(output);
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
