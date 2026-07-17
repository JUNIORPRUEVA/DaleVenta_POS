import { BadRequestException, Body, Controller, Get, Param, Patch, Post, Req, UploadedFile, UseGuards, UseInterceptors } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { FileInterceptor } from '@nestjs/platform-express';
import { diskStorage } from 'multer';
import { extname, join } from 'node:path';
import * as fs from 'node:fs';
import type { Express, Request } from 'express';
import { WebsiteService } from './website.service';
import { UpdateWebsiteProductDto } from './dto/update-website-product.dto';

function websiteUploadDir() {
  const fromEnv = (process.env.UPLOAD_DIR ?? '').trim();
  const base = fromEnv || (fs.existsSync('/uploads') ? '/uploads' : join(process.cwd(), 'uploads'));
  const dir = join(base, 'website');
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

@Controller('website')
export class WebsiteController {
  constructor(private readonly website: WebsiteService) {}

  @Get('public')
  publicStorefront() {
    return this.website.getPublicStorefront();
  }

  @UseGuards(AuthGuard('jwt'))
  @Get('products')
  adminProducts() {
    return this.website.getAdminProducts();
  }

  @UseGuards(AuthGuard('jwt'))
  @Patch('products/:productId')
  updateProduct(
    @Param('productId') productId: string,
    @Body() dto: UpdateWebsiteProductDto,
  ) {
    return this.website.updateProduct(productId, dto);
  }

  @UseGuards(AuthGuard('jwt'))
  @Post('upload')
  @UseInterceptors(
    FileInterceptor('file', {
      storage: diskStorage({
        destination: (_req: Express.Request, _file: Express.Multer.File, cb) => cb(null, websiteUploadDir()),
        filename: (_req: Express.Request, file: Express.Multer.File, cb) => {
          const unique = `${Date.now()}-${Math.round(Math.random() * 1e6)}`;
          cb(null, `${unique}${extname(file.originalname)}`);
        },
      }),
      fileFilter: (_req, file, cb) => {
        const isImage = /^image\/(png|jpe?g|webp)$/.test(file.mimetype);
        if (!isImage) return cb(new BadRequestException('Solo se permiten imágenes PNG/JPG/WEBP'), false);
        cb(null, true);
      },
      limits: { fileSize: 6 * 1024 * 1024 },
    }),
  )
  upload(@Req() req: Request, @UploadedFile() file?: Express.Multer.File) {
    if (!file) throw new BadRequestException('No se subió ningún archivo');
    const relativePath = `/uploads/website/${file.filename}`;
    const proto = (req.get('x-forwarded-proto') ?? req.protocol ?? 'http').split(',')[0].trim();
    const host = (req.get('x-forwarded-host') ?? req.get('host') ?? '').split(',')[0].trim();
    const baseUrl = host ? `${proto}://${host}` : '';
    return {
      filename: file.filename,
      path: relativePath,
      url: baseUrl ? `${baseUrl}${relativePath}` : relativePath,
    };
  }
}
