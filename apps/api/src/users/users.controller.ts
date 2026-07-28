import { BadRequestException, Body, Controller, Delete, Get, Param, Patch, Post, Req, UnauthorizedException, UploadedFile, UseGuards, UseInterceptors, ForbiddenException } from '@nestjs/common';
import { UsersService } from './users.service';
import { AuthGuard } from '@nestjs/passport';
import { Roles } from '../auth/roles.decorator';
import { Role } from '@prisma/client';
import { RolesGuard } from '../auth/roles.guard';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';
import { BlockUserDto } from './dto/block-user.dto';
import { SelfUpdateUserDto } from './dto/self-update-user.dto';
import { SignWorkContractDto } from './dto/sign-work-contract.dto';
import { AiEditWorkContractDto } from './dto/ai-edit-work-contract.dto';
import { Request } from 'express';
import { FileInterceptor } from '@nestjs/platform-express';
import { memoryStorage } from 'multer';
import { extname } from 'node:path';
import { join, posix } from 'node:path';
import type { Express } from 'express';
import { randomUUID } from 'crypto';
import * as fs from 'node:fs';
import { R2Service } from '../storage/r2.service';
import { sanitizeFileName } from '../storage/helpers/storage_helpers';
import { ConfigService } from '@nestjs/config';
import type { TenantUser } from '../auth/tenant-context';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('users')
export class UsersController {
  private readonly publicBaseUrl: string;

  constructor(
    private readonly users: UsersService,
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

  @Post('upload')
  // Any authenticated user can upload a profile/document image.
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.MARKETING, Role.VENDEDOR, Role.TECNICO)
  @UseInterceptors(
    FileInterceptor('file', {
      storage: memoryStorage(),
      fileFilter: (_req: Express.Request, file: Express.Multer.File, cb: (error: Error | null, acceptFile: boolean) => void) => {
        const mimetype = (file.mimetype ?? '').toLowerCase().trim();
        const isImageMime = /^image\/(png|jpe?g|webp)$/.test(mimetype);
        if (isImageMime) return cb(null, true);

        // Some clients (desktop/web) may send empty/unknown mimetype. Fallback to file extension.
        const original = (file.originalname ?? '').toLowerCase();
        const hasAllowedExt = /\.(png|jpe?g|webp)$/.test(original);
        const isUnknownMime = mimetype.length === 0 || mimetype === 'application/octet-stream';
        if (isUnknownMime && hasAllowedExt) return cb(null, true);

        return cb(new BadRequestException('Solo se permiten imágenes PNG/JPG/WEBP'), false);
      },
      limits: { fileSize: 10 * 1024 * 1024 }
    })
  )
  async upload(@Req() req: Request, @UploadedFile() file?: Express.Multer.File) {
    if (!file) throw new BadRequestException('No se subió ningún archivo');

    const auth = req.user as { id?: string; role?: Role } | undefined;
    const uploaderId = (auth?.id ?? '').trim();
    const uploaderRole = auth?.role;
    if (!uploaderId) throw new UnauthorizedException('Usuario no autenticado');

    // Optional multipart fields to keep docs organized as an expediente.
    const body = (req.body ?? {}) as Record<string, unknown>;
    const requestedUserId = (body['userId'] ?? '').toString().trim();
    const targetUserId = requestedUserId || uploaderId;

    if (requestedUserId && requestedUserId !== uploaderId) {
      const isAdminLike = uploaderRole === Role.ADMIN || uploaderRole === Role.ASISTENTE;
      if (!isAdminLike) throw new ForbiddenException('No autorizado para subir documentos de otro usuario');
    }

    const allowedKinds = new Set(['profile', 'cedula', 'licencia', 'personal', 'expediente', 'document']);
    const rawKind = (body['kind'] ?? '').toString().trim().toLowerCase();
    const kind = rawKind && allowedKinds.has(rawKind) ? rawKind : 'document';

    const original = sanitizeFileName(file.originalname ?? 'archivo');
    const ext = extname(original || '').toLowerCase();
    const safeExt = ext && /\.(png|jpe?g|webp)$/.test(ext) ? ext : '.jpg';

    const mime = (file.mimetype ?? '').toLowerCase().trim();
    const contentType = /^image\/(png|jpe?g|webp)$/.test(mime)
      ? mime
      : (safeExt === '.png' ? 'image/png' : (safeExt === '.webp' ? 'image/webp' : 'image/jpeg'));

    const objectKey = `users/${targetUserId}/${kind}/${randomUUID()}-${original.replace(/\.[^/.]+$/, '')}${safeExt}`
      .replace(/\s+/g, '_')
      .replace(/[^a-zA-Z0-9/_\-.]/g, '');

    // Local uploads folder is source of truth for /uploads serving.
    const uploadDir = this.resolveUploadDir();
    const absoluteFilePath = join(uploadDir, ...objectKey.split('/'));
    fs.mkdirSync(join(uploadDir, ...objectKey.split('/').slice(0, -1)), { recursive: true });
    fs.writeFileSync(absoluteFilePath, file.buffer);
    if (!fs.existsSync(absoluteFilePath)) {
      throw new BadRequestException('No se pudo persistir el archivo en disco');
    }

    try {
      await this.r2.putObject({
        objectKey: `uploads/${objectKey}`,
        body: file.buffer,
        contentType,
      });
    } catch (error) {
      // Keep local upload as source of truth even when R2 is not configured.
      // eslint-disable-next-line no-console
      console.warn('[users/upload] R2 mirror failed, continuing with local storage only', error);
    }

    const relativePath = `/${posix.join('uploads', objectKey)}`;
    const r2PublicUrl = this.r2.buildPublicUrl(`uploads/${objectKey}`);
    const url =
      r2PublicUrl.startsWith('http://') || r2PublicUrl.startsWith('https://')
        ? r2PublicUrl
        : this.buildAbsoluteUrl(req, relativePath);

    return {
      url,
      objectKey: `uploads/${objectKey}`,
      relativePath,
      kind,
      userId: targetUserId,
      fileName: original,
    };
  }

  @Post()
  @Roles(Role.ADMIN)
  create(@Req() req: Request, @Body() dto: CreateUserDto) {
    return this.users.create(req.user as TenantUser, dto);
  }

  @Get()
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO, Role.MARKETING)
  findAll(@Req() req: Request) {
    return this.users.findAll(req.user as TenantUser);
  }

  @Get(':id/birthday-greeting')
  @Roles(Role.ADMIN)
  birthdayGreeting(@Param('id') id: string) {
    return this.users.generateBirthdayGreeting(id);
  }

  @Post(':id/work-contract/ai-edit')
  @Roles(Role.ADMIN)
  aiEditWorkContract(@Param('id') id: string, @Body() dto: AiEditWorkContractDto) {
    return this.users.applyAiWorkContractEdit(id, dto);
  }

  @Get('me')
  me(@Req() req: Request) {
    const user = req.user as { id?: string } | undefined;
    if (!user?.id) {
      throw new UnauthorizedException('Usuario no autenticado');
    }
    return this.users.findById(user.id);
  }

  @Post('me/work-contract/sign')
  signWorkContract(@Req() req: Request, @Body() dto: SignWorkContractDto) {
    const user = req.user as { id?: string } | undefined;
    if (!user?.id) {
      throw new UnauthorizedException('Usuario no autenticado');
    }
    return this.users.signWorkContract(user.id, dto);
  }

  @Get(':id')
  @Roles(Role.ADMIN)
  findOne(@Param('id') id: string) {
    return this.users.findById(id);
  }

  @Patch('me')
  updateSelf(@Req() req: Request, @Body() dto: SelfUpdateUserDto) {
    const user = req.user as { id?: string } | undefined;
    if (!user?.id) {
      throw new UnauthorizedException('Usuario no autenticado');
    }
    return this.users.updateSelf(user.id, dto);
  }

  @Patch(':id')
  @Roles(Role.ADMIN)
  update(@Param('id') id: string, @Body() dto: UpdateUserDto) {
    return this.users.update(id, dto);
  }

  @Patch(':id/block')
  @Roles(Role.ADMIN)
  setBlocked(@Param('id') id: string, @Body() dto: BlockUserDto) {
    return this.users.setBlocked(id, dto.blocked);
  }

  @Delete(':id')
  @Roles(Role.ADMIN)
  remove(@Param('id') id: string) {
    return this.users.remove(id);
  }
}
