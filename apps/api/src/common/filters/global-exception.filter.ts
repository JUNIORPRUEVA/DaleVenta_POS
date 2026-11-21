import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { GuardianCaptureRegistry } from '../../guardian/guardian.capture.registry';
import { sanitizeRequestUrl } from '../request-log';

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function safeString(value: unknown): string {
  if (typeof value === 'string') return value;
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

@Catch()
export class GlobalExceptionFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const req = ctx.getRequest<{
      method?: string;
      originalUrl?: string;
      url?: string;
      ip?: string;
      requestId?: string;
      user?: { id?: string; companyId?: string | null };
    }>();
    const res = ctx.getResponse<{ status: (code: number) => any; json: (body: any) => any; setHeader?: (name: string, value: string) => void }>();

    const method = req?.method ?? 'UNKNOWN';
    const rawUrl = req?.originalUrl ?? req?.url ?? 'UNKNOWN';
    const url = sanitizeRequestUrl(rawUrl);
    const redactRequestUrl = (value: string) => value.split(rawUrl).join(url);

    const databaseMessage=exception instanceof Prisma.PrismaClientKnownRequestError
      ?safeString(exception.meta):exception instanceof Prisma.PrismaClientUnknownRequestError?exception.message:'';
    const lifecycleSignal=databaseMessage.match(/PRODUCT_LIFECYCLE_(NOT_ACTIVE|ANNULLED|TENANT_MISMATCH)/)?.[1];
    if(lifecycleSignal){
      const forbidden=lifecycleSignal==='TENANT_MISMATCH';
      res.status(forbidden?403:409).json({statusCode:forbidden?403:409,
        code:forbidden?'PRODUCT_COMPANY_MISMATCH':lifecycleSignal==='ANNULLED'?'PRODUCT_ANNULLED':'PRODUCT_NOT_ACTIVE',
        message:forbidden?'El producto no pertenece a esta empresa.':'El producto ya no está activo. Actualiza el catálogo antes de continuar.',
      });
      return;
    }

    const isHttp = exception instanceof HttpException;
    const status = isHttp
      ? exception.getStatus()
      : HttpStatus.INTERNAL_SERVER_ERROR;

    const isProd = (process.env.NODE_ENV ?? '').toLowerCase() === 'production';

    const prismaDetails: Record<string, unknown> | null =
      exception instanceof Prisma.PrismaClientKnownRequestError
        ? {
            kind: 'PrismaClientKnownRequestError',
            code: exception.code,
            meta: exception.meta,
            clientVersion: exception.clientVersion,
          }
        : exception instanceof Prisma.PrismaClientUnknownRequestError
          ? {
              kind: 'PrismaClientUnknownRequestError',
              clientVersion: exception.clientVersion,
            }
          : exception instanceof Prisma.PrismaClientValidationError
            ? {
                kind: 'PrismaClientValidationError',
                clientVersion: exception.clientVersion,
              }
            : exception instanceof Prisma.PrismaClientInitializationError
              ? {
                  kind: 'PrismaClientInitializationError',
                  errorCode: exception.errorCode,
                  clientVersion: exception.clientVersion,
                }
              : exception instanceof Prisma.PrismaClientRustPanicError
                ? {
                    kind: 'PrismaClientRustPanicError',
                    clientVersion: exception.clientVersion,
                  }
                : null;

    const rawResponse = isHttp ? exception.getResponse() : null;
    if (status === HttpStatus.TOO_MANY_REQUESTS && isObject(rawResponse)) {
      const seconds = rawResponse.retryAfterSeconds;
      if (typeof seconds === 'number' && Number.isFinite(seconds) && seconds >= 0) {
        res.setHeader?.('Retry-After', String(Math.ceil(seconds)));
      }
    }
    const rawMessage = isHttp
      ? safeString(rawResponse)
      : exception instanceof Error
        ? exception.message
        : safeString(exception);

    const message = redactRequestUrl(rawMessage);
    const stack = exception instanceof Error && exception.stack
      ? redactRequestUrl(exception.stack)
      : undefined;
    const requestId = req?.requestId ?? null;
    const logPayload = {
      requestId,
      method,
      url,
      status,
      message,
      prisma: prismaDetails,
      stack,
    };

    if (status >= HttpStatus.INTERNAL_SERVER_ERROR) {
      // eslint-disable-next-line no-console
      console.error('[error]', logPayload);
    } else {
      // eslint-disable-next-line no-console
      console.warn('[warn]', logPayload);
    }

    // Captura Guardian (best-effort, fire-and-forget). Nunca lanza ni bloquea la
    // respuesta; ignora rutas /guardian para no capturarse a sí misma.
    if (status >= HttpStatus.INTERNAL_SERVER_ERROR) {
      GuardianCaptureRegistry.capture({
        companyId: req?.user?.companyId ?? null,
        userId: req?.user?.id ?? null,
        requestId,
        method,
        path: url,
        status,
        exceptionType: exception instanceof Error ? exception.constructor.name : typeof exception,
        message: exception instanceof Error ? redactRequestUrl(exception.message) : message,
        stack,
        // Metadatos de Prisma sin parámetros de consulta: permiten distinguir
        // una caída de infraestructura (P1001) de una regla de negocio (P2002).
        prismaCode: prismaDetails ? String(prismaDetails['code'] ?? '') || null : null,
        prismaKind: prismaDetails ? String(prismaDetails['kind'] ?? '') || null : null,
      });
    }

    // Safe error response for clients.
    const responseBody: Record<string, unknown> = {
      statusCode: status,
      path: url,
      method,
      timestamp: new Date().toISOString(),
    };

    if (requestId) {
      responseBody.requestId = requestId;
    }
    if (isHttp && isObject(rawResponse)) {
      Object.assign(responseBody, rawResponse);
    } else {
      responseBody.message = isHttp ? message : 'Error interno del servidor';
    }

    if (!isProd) {
      if (stack) responseBody.stack = stack;
      if (prismaDetails) responseBody.prisma = prismaDetails;
      if (isObject(exception)) responseBody.debug = exception;
    }

    res.status(status).json(responseBody);
  }
}
