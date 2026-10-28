import { GuardianCaptureRegistry } from '../guardian.capture.registry';

/**
 * Reporte de fallos de tareas de fondo (cron, intervalos, outbox) a Guardian.
 *
 * Se apoya en el mismo registro que usa el filtro global de excepciones, así
 * que hereda todas sus garantías: no bloquea, no lanza y no participa en
 * ninguna transacción.
 *
 * Convención de ruta: `/jobs/<modulo>/<operacion>`. El clasificador usa el
 * módulo declarado aquí, de modo que un fallo del outbox de notificaciones no
 * se confunde con un fallo del backend genérico.
 *
 * Uso: dentro de un `catch` que ya existe. Nunca cambia el flujo de control:
 * el `catch` debe seguir haciendo lo que hacía (registrar, reintentar o callar).
 */
export function reportGuardianJobFailure(params: {
  module: string;
  operation: string;
  error: unknown;
}): void {
  try {
    const module = String(params.module ?? 'backend')
      .trim()
      .toLowerCase()
      .replace(/[^a-z]/g, '')
      .slice(0, 20) || 'backend';
    const operation = String(params.operation ?? 'job')
      .trim()
      .slice(0, 60)
      .replace(/[^A-Za-z0-9._-]/g, '-') || 'job';

    const error = params.error;
    const message = error instanceof Error ? error.message : String(error ?? '');
    const stack = error instanceof Error ? error.stack ?? null : null;

    GuardianCaptureRegistry.capture({
      requestId: null,
      method: 'JOB',
      path: `/jobs/${module}/${operation}`,
      // Marca interna de fallo técnico: las tareas de fondo no tienen código
      // HTTP propio y esta ruta nunca se sirve por HTTP.
      status: 500,
      exceptionType: error instanceof Error ? error.constructor.name : 'BackgroundJobError',
      message,
      stack,
      prismaCode: extractPrismaCode(error),
      prismaKind: null,
      context: { origin: 'job', jobModule: module, jobOperation: operation },
    });
  } catch {
    // Silencio deliberado: reportar el fallo de una tarea no puede romperla.
  }
}

function extractPrismaCode(error: unknown): string | null {
  if (typeof error === 'object' && error !== null && 'code' in error) {
    const code = (error as { code?: unknown }).code;
    if (typeof code === 'string' && /^P\d{4}$/.test(code)) return code;
  }
  return null;
}
