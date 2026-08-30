import 'reflect-metadata';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as express from 'express';
import type { Request, Response, NextFunction } from 'express';
import compression from 'compression';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  ExpressAdapter,
  type NestExpressApplication,
} from '@nestjs/platform-express';
import { AppModule } from './app.module';
import { GlobalExceptionFilter } from './common/filters/global-exception.filter';
import { CatalogRealtimeRelayService } from './products/catalog-realtime-relay.service';

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(
    AppModule,
    new ExpressAdapter(),
    {
      cors: false,
      bodyParser: false,
    },
  );
  app.set('trust proxy', 1);

  // Basic request logging (method/url/status/duration).
  app.use((req: Request, res: Response, next: NextFunction) => {
    const start = Date.now();
    const method = req.method;
    const url = req.originalUrl || req.url;

    res.on('finish', () => {
      const durationMs = Date.now() - start;
      const status = res.statusCode;
      // eslint-disable-next-line no-console
      console.log(`[req] ${method} ${url} -> ${status} (${durationMs}ms)`);
    });

    next();
  });

  const config = app.get(ConfigService);
  const bodySizeLimit = (config.get<string>('BODY_SIZE_LIMIT') ?? '10mb').trim() || '10mb';

  // HTTP compression (gzip/deflate/br) for JSON/text responses.
  // The default filter (expressjs/compression) only compresses compressible
  // content-types and skips already-encoded payloads, so images/media/PDF are
  // left untouched. Sets Content-Encoding and Vary: Accept-Encoding itself.
  app.use(
    compression({
      threshold: 1024,
      filter: (req: Request, res: Response) => {
        const type = res.getHeader('Content-Type');
        if (typeof type !== 'string') return false;
        // Compress only JSON/text-like payloads. Never compress images, PDFs,
        // binaries or already-compressed media (already handled by the default
        // filter, but kept explicit for safety).
        return /(json|text|javascript|xml|svg)/i.test(type);
      },
    }),
  );
  // eslint-disable-next-line no-console
  console.log('[http] compression enabled (gzip/deflate/br, threshold=1024)');

  app.use(express.json({ limit: bodySizeLimit }));
  app.use(express.urlencoded({ extended: true, limit: bodySizeLimit }));
  // eslint-disable-next-line no-console
  console.log(`[http] request body limit: ${bodySizeLimit}`);

  // Global exception filter: logs errors (incl. Prisma meta) and returns safe JSON.
  app.useGlobalFilters(new GlobalExceptionFilter());
  const port = Number(config.get('PORT') ?? 4000);
  const uploadDirEnv = (config.get<string>('UPLOAD_DIR') ?? '').trim();
  const volumeDir = '/uploads';
  const volumeExists = fs.existsSync(volumeDir);
  const uploadDir = uploadDirEnv.length > 0
    ? ((uploadDirEnv === './uploads' || uploadDirEnv === 'uploads') && volumeExists
        ? volumeDir
        : uploadDirEnv)
    : (volumeExists ? volumeDir : path.join(process.cwd(), 'uploads'));

  fs.mkdirSync(uploadDir, { recursive: true });
  app.useStaticAssets(uploadDir, { prefix: '/uploads' });
  // eslint-disable-next-line no-console
  console.log(`[uploads] serving static files from: ${uploadDir}`);

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true
    })
  );

  app.enableCors({
    origin: true,
    credentials: true,
    methods: ['GET', 'HEAD', 'PUT', 'PATCH', 'POST', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'Accept', 'Origin', 'X-Requested-With'],
  });

  const realtimeRelay = app.get(CatalogRealtimeRelayService);
  realtimeRelay.attach(app.getHttpServer() as unknown as import('node:http').Server);

  // Bind to IPv6 (dual-stack) when available so `localhost` (often ::1 on Windows)
  // works reliably; fall back to IPv4-only environments.
  let host = '::';
  try {
    await app.listen(port, host);
  } catch {
    host = '0.0.0.0';
    await app.listen(port, host);
  }
  realtimeRelay.start();
  // eslint-disable-next-line no-console
  const displayHost = host.includes(':') ? `[${host}]` : host;
  console.log(`API listening on http://${displayHost}:${port}`);
}

bootstrap();
