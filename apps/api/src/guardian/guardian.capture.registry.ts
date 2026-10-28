/**
 * Puente sin dependencias de Nest entre el filtro global de excepciones
 * (creado con `new` en `main.ts`) y el servicio de captura de Guardian.
 *
 * Se usa un registro estático para no acoplar `common/` con la inyección de
 * dependencias del módulo Guardian.
 */
export type GuardianBackendErrorInput = {
  companyId?: string | null;
  userId?: string | null;
  requestId?: string | null;
  method?: string;
  path?: string;
  status?: number;
  exceptionType?: string | null;
  message?: string | null;
  stack?: string | null;
  /** Código de error de Prisma (`P1001`, `P2002`...) cuando aplica. */
  prismaCode?: string | null;
  /** Tipo de error de Prisma (`PrismaClientInitializationError`...). */
  prismaKind?: string | null;
  /** Contexto adicional ya derivado, NUNCA datos de cliente. */
  context?: Record<string, unknown> | null;
};

type GuardianCaptureHandler = (input: GuardianBackendErrorInput) => void;

let handler: GuardianCaptureHandler | null = null;
let bridge: GuardianCaptureHandler | null = null;

export const GuardianCaptureRegistry = {
  register(next: GuardianCaptureHandler | null) {
    handler = next;
  },
  /**
   * Segundo consumidor independiente (puente de telemetría remoto).
   *
   * Existe como ranura aparte para que activar el puente no desactive ni
   * altere la captura local ya existente: cada consumidor decide por su propia
   * bandera y ninguno puede romper al otro.
   */
  registerBridge(next: GuardianCaptureHandler | null) {
    bridge = next;
  },
  /**
   * Nunca lanza y nunca bloquea: la captura es best-effort y jamás puede
   * convertir una respuesta HTTP correcta en un error.
   */
  capture(input: GuardianBackendErrorInput) {
    if (handler) {
      try {
        handler(input);
      } catch {
        // Silencio deliberado: Guardian no puede romper el manejo de errores.
      }
    }
    if (bridge) {
      try {
        bridge(input);
      } catch {
        // Idem: el puente de telemetría es best-effort y fail-open.
      }
    }
  },
};
