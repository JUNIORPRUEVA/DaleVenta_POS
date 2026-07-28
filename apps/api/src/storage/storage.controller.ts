import {
  BadRequestException,
  Controller,
  Post,
  Req,
  UnauthorizedException,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { extname } from 'node:path';
import { join, posix } from 'node:path';
import * as fs from 'node:fs';
import type { Request } from 'express';
import type { Express } from 'express';
import { FileInterceptor } from '@nestjs/platform-express';
import { memoryStorage } from 'multer';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { requireTenant, type TenantUser } from '../auth/tenant-context';
import {
  ALLOWED_CONTENT_TYPES,
  buildTenantObjectKey,
  inferMediaType,
  sanitizeFileName,
  sanitizeObjectKeySegment,
} from './helpers/storage_helpers';
import { R2Service } from './r2.service';

const allowedMimeTypes = new Set<string>([
  ...ALLOWED_CONTENT_TYPES,
  'video/x-matroska',
  'application/zip',
  'application/x-zip-compressed',
  'application/x-7z-compressed',
  'application/gzip',
  'application/x-tar',
  'application/octet-stream',
]);

const imageExtensions = new Set(['.jpg', '.jpeg', '.png', '.webp']);
const videoExtensions = new Set(['.mp4', '.mov', '.webm', '.mkv']);
const documentExtensions = new Set([
  '.pdf',
  '.doc',
  '.docx',
  '.xls',
  '.xlsx',
  '.txt',
  '.csv',
  '.zip',
  '.7z',
  '.gz',
  '.tar',
]);
const maxImageSizeBytes = 12 * 1024 * 1024;
const maxVideoSizeBytes = 60 * 1024 * 1024;
const maxDocumentSizeBytes = 100 * 1024 * 1024;

function inferContentType(file: Express.Multer.File, safeExt: string): string {
  const mime = (file.mimetype ?? '').trim().toLowerCase();
  if (allowedMimeTypes.has(mime) && mime !== 'application/octet-stream') return mime;
  if (imageExtensions.has(safeExt)) {
    if (safeExt == '.png') return 'image/png';
    if (safeExt == '.webp') return 'image/webp';
    return 'image/jpeg';
  }
  if (safeExt == '.mov') return 'video/quicktime';
  if (safeExt == '.webm') return 'video/webm';
  if (safeExt == '.mkv') return 'video/x-matroska';
  if (safeExt == '.pdf') return 'application/pdf';
  if (safeExt == '.doc') return 'application/msword';
  if (safeExt == '.docx') return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  if (safeExt == '.xls') return 'application/vnd.ms-excel';
  if (safeExt == '.xlsx') return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  if (safeExt == '.txt') return 'text/plain';
  if (safeExt == '.csv') return 'text/csv';
  if (safeExt == '.zip') return 'application/zip';
  if (safeExt == '.7z') return 'application/x-7z-compressed';
  if (safeExt == '.gz') return 'application/gzip';
  if (safeExt == '.tar') return 'application/x-tar';
  return 'video/mp4';
}

function inferMediaFolder(contentType: string): 'images' | 'videos' | 'documents' | 'backups' {
  if (contentType == 'application/zip' || contentType == 'application/x-zip-compressed') return 'backups';
  if (contentType == 'application/x-7z-compressed' || contentType == 'application/gzip' || contentType == 'application/x-tar') {
    return 'backups';
  }
  if (contentType.startsWith('video/')) return 'videos';
  if (contentType.startsWith('image/')) return 'images';
  return 'documents';
}

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('upload')
export class StorageController {
  private readonly publicBaseUrl: string;

  constructor(
    private readonly r2: R2Service,
    config: ConfigService,
  ) {
    const base =
      config.get<string>('PUBLIC_BASE_URL') ??
      config.get<string>('API_BASE_URL') ??
      '';
    this.publicBaseUrl = base.trim().replace(/\/$/, '');
  }

  private resolveUploadDir(): string {
    const fromEnv = (process.env.UPLOAD_DIR ?? '').trim();
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

  private buildAbsoluteUrl(req: Request, relativePath: string): string {
    const proto = (req.get('x-forwarded-proto') ?? req.protocol ?? 'http')
      .split(',')[0]
      .trim();
    const host = (req.get('x-forwarded-host') ?? req.get('host') ?? '')
      .split(',')[0]
      .trim();
    const requestBase = host ? `${proto}://${host}` : '';
    const baseUrl = this.publicBaseUrl || requestBase;
    return baseUrl ? `${baseUrl}${relativePath}` : relativePath;
  }

  @Post()
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO, Role.MARKETING)
  @UseInterceptors(
    FileInterceptor('file', {
      storage: memoryStorage(),
      fileFilter: (_req: Express.Request, file: Express.Multer.File, cb: (error: Error | null, acceptFile: boolean) => void) => {
        const mime = (file.mimetype ?? '').trim().toLowerCase();
        const original = (file.originalname ?? '').trim().toLowerCase();
        const ext = extname(original);
        const extAllowed = imageExtensions.has(ext) || videoExtensions.has(ext) || documentExtensions.has(ext);
        const mimeAllowed = allowedMimeTypes.has(mime);
        const mimeUnknown = mime.length == 0 || mime == 'application/octet-stream';
        if (mimeAllowed || (mimeUnknown && extAllowed)) {
          return cb(null, true);
        }
        return cb(
          new BadRequestException('Solo se permiten imágenes, videos, documentos PDF/Office/texto o respaldos comprimidos'),
          false,
        );
      },
      limits: { fileSize: maxDocumentSizeBytes },
    }),
  )
  async upload(@Req() req: Request, @UploadedFile() file?: Express.Multer.File) {
    if (!file) {
      throw new BadRequestException('No se subió ningún archivo');
    }

    const auth = req.user as TenantUser | undefined;
    const userId = (auth?.id ?? '').trim();
    if (!userId) {
      throw new UnauthorizedException('Usuario no autenticado');
    }
    const companyId = requireTenant(auth);

    const body = (req.body ?? {}) as Record<string, unknown>;
    const kind = sanitizeObjectKeySegment((body['kind'] ?? 'general').toString(), 'general');
    const original = sanitizeFileName(file.originalname ?? 'archivo');
    const ext = extname(original).toLowerCase();
    const safeExt = imageExtensions.has(ext) || videoExtensions.has(ext) || documentExtensions.has(ext)
      ? ext
      : ((file.mimetype ?? '').toLowerCase().startsWith('video/') ? '.mp4' : '.jpg');
    const contentType = inferContentType(file, safeExt);
    const mediaFolder = inferMediaFolder(contentType);
    const maxAllowedSize =
      mediaFolder === 'videos'
        ? maxVideoSizeBytes
        : mediaFolder === 'images'
          ? maxImageSizeBytes
          : maxDocumentSizeBytes;
    if (file.size > maxAllowedSize) {
      throw new BadRequestException(
        mediaFolder === 'videos'
          ? 'El video excede el limite permitido de 60 MB'
          : mediaFolder === 'images'
            ? 'La imagen excede el limite permitido de 12 MB'
            : 'El archivo excede el limite permitido de 100 MB',
      );
    }
    const objectKey = buildTenantObjectKey({
      companyId,
      area: mediaFolder,
      kind,
      ownerId: userId,
      fileName: original,
      extension: safeExt,
    });

    const r2ObjectKey = `uploads/${objectKey}`;
    const mediaUrl = this.buildMediaObjectUrl(req, r2ObjectKey);

    try {
      await this.r2.putObject({
        objectKey: r2ObjectKey,
        body: file.buffer,
        contentType,
      });
      // eslint-disable-next-line no-console
      console.log(`[upload] R2 saved companyId=${companyId} key=${r2ObjectKey}`);
      return {
        url: mediaUrl,
        path: mediaUrl,
        publicUrl: mediaUrl,
        objectKey: r2ObjectKey,
        relativePath: mediaUrl,
        fileName: original,
        originalFileName: original,
        storageProvider: 'r2',
        kind,
        contentType,
        mimeType: contentType,
        mediaType: inferMediaType(contentType),
        size: file.size,
        companyId,
      };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.warn('[upload] R2 primary upload failed, falling back to local storage', error);
    }

    const uploadDir = this.resolveUploadDir();
    const absoluteFilePath = join(uploadDir, ...objectKey.split('/'));
    const absoluteDir = join(uploadDir, ...objectKey.split('/').slice(0, -1));
    fs.mkdirSync(absoluteDir, { recursive: true });
    fs.writeFileSync(absoluteFilePath, file.buffer);

    if (!fs.existsSync(absoluteFilePath)) {
      // eslint-disable-next-line no-console
      console.error(`[upload] file not found after write: ${absoluteFilePath}`);
      throw new BadRequestException('No se pudo persistir el archivo en disco');
    }

    const relativePath = `/${posix.join('uploads', objectKey)}`;
    const url = this.buildAbsoluteUrl(req, relativePath);
    // eslint-disable-next-line no-console
    console.warn(`[upload] legacy local fallback saved file=${absoluteFilePath} url=${url}`);

    return {
      url,
      path: url,
      publicUrl: url,
      objectKey: r2ObjectKey,
      relativePath,
      fileName: original,
      originalFileName: original,
      storageProvider: 'local',
      kind,
      contentType,
      mimeType: contentType,
      mediaType: inferMediaType(contentType),
      size: file.size,
      companyId,
    };
  }

  private buildMediaObjectUrl(req: Request, objectKey: string): string {
    const path = `/media/object?key=${encodeURIComponent(objectKey)}`;
    return this.buildAbsoluteUrl(req, path);
  }
}
