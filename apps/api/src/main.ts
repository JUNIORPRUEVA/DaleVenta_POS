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
import { describeListenFailure, shouldFallbackToIpv4 } from './common/listen-host';
import { requestIdMiddleware } from './common/request-id/request-id.middleware';
import { assertSafeUatEnvironment, buildSafeUatBanner } from './common/uat-safety';
import { assertDosaSignatureLabSafety } from './ecf/provider/dosa/dosa-webhook-signature.policy';
import { CatalogRealtimeRelayService } from './products/catalog-realtime-relay.service';

async function bootstrap() {
  assertSafeUatEnvironment();
  // Barrera DOSA: la estrategia de firma no verificada solo puede existir en un
  // laboratorio local. Si la configuracion la pide en cualquier otro entorno, la
  // aplicacion NO arranca (fallar ruidosamente, no arrancar fingiendo autenticar).
  assertDosaSignatureLabSafety();
  if ((process.env.APP_ENV ?? '').trim().toLowerCase() === 'uat') {
    // eslint-disable-next-line no-console
    console.log(buildSafeUatBanner());
  }

  const app = await NestFactory.create<NestExpressApplication>(
    AppModule,
    new ExpressAdapter(),
    {
      cors: false,
      bodyParser: false,
    },
  );
  app.set('trust proxy', 1);

  // Request correlation: accepts/propagates x-request-id (or x-correlation-id)
  // and always echoes a sanitized identifier in the response headers.
  app.use(requestIdMiddleware);

  // Apagado ordenado: Nest ejecuta `onModuleDestroy`/`beforeApplicationShutdown`
  // y Prisma cierra su pool. Sin esto el proceso muere con conexiones abiertas.
  app.enableShutdownHooks();

  // Basic request logging (request id/method/url/status/duration).
  app.use((req: Request, res: Response, next: NextFunction) => {
    const start = Date.now();
    const method = req.method;
    const url = req.originalUrl || req.url;
    const requestId = (req as Request & { requestId?: string }).requestId ?? '-';

    res.on('finish', () => {
      const durationMs = Date.now() - start;
      const status = res.statusCode;
      // eslint-disable-next-line no-console
      console.log(`[req] ${requestId} ${method} ${url} -> ${status} (${durationMs}ms)`);
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

  // Guardian webhook de WhatsApp Cloud API: necesita el cuerpo CRUDO para
  // verificar X-Hub-Signature-256 con HMAC SHA-256. Debe ir antes del json parser.
  app.use(
    '/guardian/webhooks/whatsapp',
    express.raw({ type: 'application/json', limit: bodySizeLimit }),
    (req: Request, _res: Response, next: NextFunction) => {
      (req as Request & { rawBody?: Buffer }).rawBody = req.body as Buffer;
      req.body = {};
      next();
    },
  );

  // Cuerpo CRUDO solo para el webhook de DOSA: la firma se calcula sobre los
  // bytes EXACTOS recibidos, sin normalizar. Es un `verify` por ruta, así que
  // el resto de la API sigue parseando exactamente igual que antes.
  const rawBodyPathPrefixes = ['/webhook/', '/api/webhook/'];
  app.use(
    express.json({
      limit: bodySizeLimit,
      verify: (
        req: Request & { rawBody?: Buffer },
        _res: Response,
        buf: Buffer,
      ) => {
        const url = req.originalUrl ?? req.url ?? '';
        if (rawBodyPathPrefixes.some((prefix) => url.startsWith(prefix))) {
          req.rawBody = Buffer.from(buf);
        }
      },
    }),
  );
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
  });

  const realtimeRelay = app.get(CatalogRealtimeRelayService);
  realtimeRelay.attach(app.getHttpServer() as unknown as import('node:http').Server);

  // Bind to IPv6 (dual-stack) when available so `localhost` (often ::1 on Windows)
  // works reliably; fall back to IPv4-only environments.
  //
  // El fallback se aplica SOLO si la pila IPv6 no existe. Si el puerto está
  // ocupado (EADDRINUSE) se aborta: reintentar en IPv4 dejaba dos instancias
  // sirviendo el mismo puerto sin ningún error visible.
  const isolatedUat =
    process.env.APP_ENV === 'uat' && process.env.UAT_LOCAL_ONLY === 'true';
  let host = isolatedUat ? '127.0.0.1' : '::';
  try {
    await app.listen(port, host);
  } catch (error) {
    if (isolatedUat || !shouldFallbackToIpv4(error)) {
      // eslint-disable-next-line no-console
      console.error(describeListenFailure(port, host, error));
      throw error;
    }
    host = '0.0.0.0';
    await app.listen(port, host);
  }
  realtimeRelay.start();
  // eslint-disable-next-line no-console
  const displayHost = host.includes(':') ? `[${host}]` : host;
  console.log(`API listening on http://${displayHost}:${port}`);

  // Cierre explicito y acotado. Si el apagado ordenado no termina a tiempo, se
  // sale igualmente para no dejar el proceso colgado. No se registra nada
  // sensible: solo el evento y el codigo de salida.
  let closing = false;
  const shutdown = (signal: NodeJS.Signals) => {
    if (closing) return;
    closing = true;
    // eslint-disable-next-line no-console
    console.log(`API shutdown requested (${signal})`);
    const forceExit = setTimeout(() => {
      // eslint-disable-next-line no-console
      console.error('API shutdown timed out; forcing exit');
      process.exit(1);
    }, 15_000);
    forceExit.unref();
    void app
      .close()
      .then(() => {
        clearTimeout(forceExit);
        // eslint-disable-next-line no-console
        console.log('API shutdown complete');
        process.exit(0);
      })
      .catch(() => {
        clearTimeout(forceExit);
        process.exit(1);
      });
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

bootstrap();
