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
};

type GuardianCaptureHandler = (input: GuardianBackendErrorInput) => void;

let handler: GuardianCaptureHandler | null = null;

export const GuardianCaptureRegistry = {
  register(next: GuardianCaptureHandler | null) {
    handler = next;
  },
  /**
   * Nunca lanza y nunca bloquea: la captura es best-effort y jamás puede
   * convertir una respuesta HTTP correcta en un error.
   */
  capture(input: GuardianBackendErrorInput) {
    if (!handler) return;
    try {
      handler(input);
    } catch {
      // Silencio deliberado: Guardian no puede romper el manejo de errores.
    }
  },
};
