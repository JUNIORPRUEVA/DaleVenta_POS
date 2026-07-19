import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Header,
  Param,
  Patch,
  Post,
  Req,
  UploadedFile,
  UnauthorizedException,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { FileInterceptor } from '@nestjs/platform-express';
import { Role } from '@prisma/client';
import { diskStorage } from 'multer';
import * as fs from 'node:fs';
import { extname, join, posix } from 'node:path';
import type { Express, Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { TechnicalNetworkService } from './technical-network.service';

type AuthRequest = Request & { user?: { id?: string; role?: Role } };

function technicalNetworkUploadDir() {
  const fromEnv = (process.env.UPLOAD_DIR ?? '').trim();
  const base =
    fromEnv || (fs.existsSync('/uploads') ? '/uploads' : join(process.cwd(), 'uploads'));
  const now = new Date();
  const dir = join(
    base,
    'technical-network',
    `${now.getFullYear()}`,
    `${now.getMonth() + 1}`.padStart(2, '0'),
  );
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

function safeUploadName(originalName: string) {
  const extension = extname(originalName).toLowerCase();
  const cleanBase =
    originalName
      .replace(extension, '')
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-zA-Z0-9_-]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 48) || 'archivo';
  return `${Date.now()}-${Math.round(Math.random() * 1e9)}-${cleanBase}${extension}`;
}

@Controller('technical-network')
export class TechnicalNetworkController {
  constructor(private readonly service: TechnicalNetworkService) {}

  @Get('public-form')
  @Header('Content-Type', 'text/html; charset=utf-8')
  publicForm() {
    return this.service.publicFormHtml();
  }

  @Post('public/applications')
  submitPublicApplication(@Body() dto: Record<string, unknown>) {
    return this.service.submitApplication(dto);
  }

  @Post('public/upload')
  @UseInterceptors(
    FileInterceptor('file', {
      storage: diskStorage({
        destination: (_req: Express.Request, _file: Express.Multer.File, cb) =>
          cb(null, technicalNetworkUploadDir()),
        filename: (_req: Express.Request, file: Express.Multer.File, cb) =>
          cb(null, safeUploadName(file.originalname)),
      }),
      fileFilter: (_req, file, cb) => {
        const allowed = /^(image\/(png|jpe?g|webp)|application\/pdf|application\/msword|application\/vnd\.openxmlformats-officedocument\.wordprocessingml\.document)$/.test(
          file.mimetype,
        );
        if (!allowed) {
          return cb(
            new BadRequestException('Solo se permiten imágenes, PDF, DOC o DOCX.'),
            false,
          );
        }
        cb(null, true);
      },
      limits: { fileSize: 8 * 1024 * 1024 },
    }),
  )
  uploadPublicFile(@Req() req: Request, @UploadedFile() file?: Express.Multer.File) {
    if (!file) throw new BadRequestException('No se subió ningún archivo.');
    const marker = `${posix.sep}technical-network${posix.sep}`;
    const normalizedPath = file.path.replace(/\\/g, '/');
    const relativeTail = normalizedPath.includes(marker)
      ? normalizedPath.substring(normalizedPath.indexOf(marker) + 1)
      : `technical-network/${file.filename}`;
    const relativePath = `/${posix.join('uploads', relativeTail)}`;
    const proto = (req.get('x-forwarded-proto') ?? req.protocol ?? 'http')
      .split(',')[0]
      .trim();
    const host = (req.get('x-forwarded-host') ?? req.get('host') ?? '')
      .split(',')[0]
      .trim();
    const baseUrl = host ? `${proto}://${host}` : '';
    return {
      originalName: file.originalname,
      mimeType: file.mimetype,
      sizeBytes: file.size,
      path: relativePath,
      url: baseUrl ? `${baseUrl}${relativePath}` : relativePath,
    };
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN)
  @Get('summary')
  summary() {
    return this.service.summary();
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN)
  @Get('applications')
  applications() {
    return this.service.listApplications();
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN)
  @Get('technicians')
  technicians() {
    return this.service.listTechnicians();
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN)
  @Patch('applications/:id/status')
  updateApplicationStatus(
    @Req() req: AuthRequest,
    @Param('id') id: string,
    @Body() dto: Record<string, unknown>,
  ) {
    return this.service.updateApplicationStatus(this.userId(req), id, dto);
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN)
  @Post('applications/:id/approve')
  approve(@Req() req: AuthRequest, @Param('id') id: string) {
    return this.service.approveApplication(this.userId(req), id);
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN)
  @Post('technicians')
  createTechnician(@Req() req: AuthRequest, @Body() dto: Record<string, unknown>) {
    return this.service.createTechnician(this.userId(req), dto);
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN)
  @Patch('technicians/:id')
  updateTechnician(
    @Param('id') id: string,
    @Body() dto: Record<string, unknown>,
  ) {
    return this.service.updateTechnician(id, dto);
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN)
  @Post('technicians/:id/jobs')
  addJob(
    @Req() req: AuthRequest,
    @Param('id') technicianId: string,
    @Body() dto: Record<string, unknown>,
  ) {
    return this.service.addJob(this.userId(req), technicianId, dto);
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN)
  @Post('technicians/:id/evaluations')
  addEvaluation(
    @Req() req: AuthRequest,
    @Param('id') technicianId: string,
    @Body() dto: Record<string, unknown>,
  ) {
    return this.service.addEvaluation(this.userId(req), technicianId, dto);
  }

  private userId(req: AuthRequest) {
    const id = req.user?.id;
    if (!id) throw new UnauthorizedException('Usuario no autenticado');
    return id;
  }
}
