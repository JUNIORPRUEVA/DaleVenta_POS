import { Controller, Get, NotFoundException, Param, Req, Res } from '@nestjs/common';
import { join } from 'node:path';
import * as fs from 'node:fs';
import type { Request, Response } from 'express';
import { R2Service } from './r2.service';

@Controller('uploads')
export class UploadsController {
  constructor(private readonly r2: R2Service) {}

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

  @Get('*')
  async getUpload(
    @Param('0') keyPath: string,
    @Req() req: Request,
    @Res() res: Response,
  ) {
    const cleanPath = (keyPath ?? '').trim().replace(/^\/+/, '');
    if (!cleanPath || cleanPath.includes('..') || cleanPath.includes('\\')) {
      throw new NotFoundException('Archivo no encontrado');
    }

    const localPath = join(this.resolveUploadDir(), ...cleanPath.split('/'));
    if (fs.existsSync(localPath)) {
      res.sendFile(localPath);
      return;
    }

    const objectKey = `uploads/${cleanPath}`;
    try {
      const range = (req.headers.range ?? '').toString().trim();
      if (range) {
        const object = await this.r2.getObjectRange(objectKey, range);
        res.status(206);
        res.setHeader('Content-Type', object.contentType ?? 'application/octet-stream');
        res.setHeader('Cache-Control', 'private, max-age=300');
        res.setHeader('Accept-Ranges', 'bytes');
        if (object.contentRange) {
          res.setHeader('Content-Range', object.contentRange);
        }
        res.setHeader('Content-Length', String(object.contentLength));
        res.send(object.body);
        return;
      }

      const object = await this.r2.getObject(objectKey);
      res.setHeader('Content-Type', object.contentType ?? 'application/octet-stream');
      res.setHeader('Cache-Control', 'private, max-age=300');
      res.setHeader('Content-Length', String(object.contentLength));
      res.send(object.body);
    } catch {
      throw new NotFoundException('Archivo no encontrado');
    }
  }
}
