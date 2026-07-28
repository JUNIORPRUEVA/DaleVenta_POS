import { BadRequestException, Body, ConflictException, Controller, Delete, Get, Header, Param, Patch, Post, Query, Req, Res, UploadedFile, UseGuards, UseInterceptors } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { diskStorage } from 'multer';
import { extname, join } from 'node:path';
import type { Express, Request, Response } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import type { TenantUser } from '../auth/tenant-context';
import { CreateProductDto } from './dto/create-product.dto';
import { UpdateProductDto } from './dto/update-product.dto';
import { ProductCostInterceptor } from './product-cost.interceptor';
import { ProductsService } from './products.service';
import { FileInterceptor } from '@nestjs/platform-express';
import * as fs from 'node:fs';

@UseInterceptors(ProductCostInterceptor)
@Controller('products')
export class ProductsController {
  private readonly uploadDir: string;
  private readonly publicBaseUrl: string;
  private readonly fullposBaseUrl: string;

  private resolveUploadDir(config: ConfigService): string {
    const fromEnv = (config.get<string>('UPLOAD_DIR') ?? '').trim();
    const volumeDir = '/uploads';
    const volumeExists = fs.existsSync(volumeDir);

    if (fromEnv.length > 0) {
      if ((fromEnv == './uploads' || fromEnv == 'uploads') && volumeExists) {
        return volumeDir;
      }
      return fromEnv;
    }

    if (volumeExists) return volumeDir;
    return join(process.cwd(), 'uploads');
  }

  constructor(private readonly products: ProductsService, config: ConfigService) {
    const dir = this.resolveUploadDir(config);
    this.uploadDir = dir.trim();
    const base = config.get<string>('PUBLIC_BASE_URL') ?? config.get<string>('API_BASE_URL') ?? '';
    this.publicBaseUrl = base.trim().replace(/\/$/, '');
    this.fullposBaseUrl = (config.get<string>('FULLPOS_INTEGRATION_BASE_URL') ?? '').trim().replace(/\/$/, '');
    fs.mkdirSync(this.uploadDir, { recursive: true });
  }

  @UseGuards(AuthGuard('jwt'))
  @Header('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate')
  @Header('Pragma', 'no-cache')
  @Header('Expires', '0')
  @Header('Surrogate-Control', 'no-store')
  @Get()
  findAll(@Req() req: Request) {
    return this.products.findAll(req.user as TenantUser);
  }

  @UseGuards(AuthGuard('jwt'))
  @Header('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate')
  @Header('Pragma', 'no-cache')
  @Header('Expires', '0')
  @Header('Surrogate-Control', 'no-store')
  @Get('source')
  source() {
    return {
      source: this.products.getSource(),
      readOnly: this.products.isReadOnly(),
    };
  }

  @Header('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate')
  @Header('Pragma', 'no-cache')
  @Header('Expires', '0')
  @Header('Surrogate-Control', 'no-store')
  @Get('image-proxy')
  async imageProxy(@Query('url') rawUrl: string | undefined, @Res() res: Response) {
    const url = (rawUrl ?? '').trim();
    if (!url) {
      throw new BadRequestException('url es requerido');
    }

    if (!this.fullposBaseUrl) {
      throw new BadRequestException('FULLPOS_INTEGRATION_BASE_URL no está configurado');
    }

    let parsedUrl: URL;
    let fullposUrl: URL;
    try {
      parsedUrl = new URL(url);
      fullposUrl = new URL(this.fullposBaseUrl);
    } catch {
      throw new BadRequestException('url inválida');
    }

    const sameFullposHost = parsedUrl.host.toLowerCase() == fullposUrl.host.toLowerCase();
    if (!sameFullposHost) {
      throw new BadRequestException('Solo se permiten imágenes del host de FULLPOS');
    }

    const upstream = await fetch(parsedUrl.toString(), {
      headers: { Accept: 'image/*,*/*;q=0.8' },
    });

    if (!upstream.ok) {
      const text = await upstream.text().catch(() => '');
      res.status(upstream.status).send(text);
      return;
    }

    const contentType = upstream.headers.get('content-type') ?? 'application/octet-stream';
    if (!contentType.toLowerCase().startsWith('image/')) {
      res.status(415).send('El recurso remoto no es una imagen');
      return;
    }
    const contentLength = upstream.headers.get('content-length');
    const body = Buffer.from(await upstream.arrayBuffer());

    res.setHeader('Content-Type', contentType);
    if (contentLength) {
      res.setHeader('Content-Length', contentLength);
    }
    res.send(body);
  }

  @UseGuards(AuthGuard('jwt'))
  @Header('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate')
  @Header('Pragma', 'no-cache')
  @Header('Expires', '0')
  @Header('Surrogate-Control', 'no-store')
  @Get(':id')
  findOne(@Req() req: Request, @Param('id') id: string) {
    return this.products.findOne(req.user as TenantUser, id);
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN, Role.ASISTENTE)
  @Post()
  create(@Req() req: Request, @Body() dto: CreateProductDto) {
    return this.products.create(req.user as TenantUser, dto);
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN, Role.ASISTENTE)
  @Post('upload')
  @UseInterceptors(
    FileInterceptor('file', {
      storage: diskStorage({
        destination: (_req: Express.Request, _file: Express.Multer.File, cb: (error: Error | null, destination: string) => void) => {
          const fromEnv = (process.env.UPLOAD_DIR ?? '').trim();
          const volumeDir = '/uploads';
          const volumeExists = fs.existsSync(volumeDir);
          const dir = fromEnv.length > 0
            ? ((fromEnv == './uploads' || fromEnv == 'uploads') && volumeExists ? volumeDir : fromEnv)
            : (volumeExists ? volumeDir : join(process.cwd(), 'uploads'));
          fs.mkdirSync(dir, { recursive: true });
          cb(null, dir);
        },
        filename: (_req: Express.Request, file: Express.Multer.File, cb: (error: Error | null, filename: string) => void) => {
          const unique = `${Date.now()}-${Math.round(Math.random() * 1e6)}`;
          cb(null, `${unique}${extname(file.originalname)}`);
        }
      }),
      fileFilter: (_req: Express.Request, file: Express.Multer.File, cb: (error: Error | null, acceptFile: boolean) => void) => {
        const isImage = /^image\/(png|jpe?g|webp)$/.test(file.mimetype);
        if (!isImage) return cb(new BadRequestException('Solo se permiten imágenes PNG/JPG/WEBP'), false);
        cb(null, true);
      },
      limits: { fileSize: 5 * 1024 * 1024 }
    })
  )
  upload(@Req() req: Request, @UploadedFile() file?: Express.Multer.File) {
    if (this.products.isReadOnly()) {
      throw new ConflictException('Productos en modo solo-lectura: no se permite subir imágenes aquí.');
    }
    if (!file) throw new BadRequestException('No se subió ningún archivo');
    const relativePath = `/uploads/${file.filename}`;
    const proto = (req.get('x-forwarded-proto') ?? req.protocol ?? 'http').split(',')[0].trim();
    const host = (req.get('x-forwarded-host') ?? req.get('host') ?? '').split(',')[0].trim();
    const requestBase = host ? `${proto}://${host}` : '';
    const baseUrl = this.publicBaseUrl || requestBase;
    const url = baseUrl ? `${baseUrl}${relativePath}` : relativePath;
    // eslint-disable-next-line no-console
    console.log(`[products/upload] saved file=${file.filename} path=${relativePath} url=${url}`);
    return { filename: file.filename, path: relativePath, url };
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN, Role.ASISTENTE)
  @Patch(':id')
  update(@Req() req: Request, @Param('id') id: string, @Body() dto: UpdateProductDto) {
    return this.products.update(req.user as TenantUser, id, dto);
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN)
  @Delete('debug/purge')
  purgeAllForDebug(@Req() req: Request) {
    return this.products.purgeAllForDebug(req.user as TenantUser);
  }

  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(Role.ADMIN, Role.ASISTENTE)
  @Delete(':id')
  remove(@Req() req: Request, @Param('id') id: string) {
    return this.products.remove(req.user as TenantUser, id);
  }
}
