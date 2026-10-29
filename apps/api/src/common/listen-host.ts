/**
 * Selección del host de escucha del API.
 *
 * Contexto: `main.ts` intenta `::` (IPv6 dual-stack) y, si falla, cae a
 * `0.0.0.0`. El problema es que ese fallback también se aplicaba cuando el
 * fallo era **EADDRINUSE** (puerto ocupado por otra instancia): el segundo
 * proceso "tenía éxito" enlazando solo IPv4 mientras el primero seguía en IPv6,
 * de modo que quedaban **dos instancias sirviendo el mismo puerto** sin ningún
 * error visible (tráfico y workers divididos).
 *
 * Regla: solo se cae a IPv4 cuando el fallo es de familia de direcciones
 * (pila IPv6 no disponible). Un puerto ocupado debe fallar de inmediato.
 */

/** Códigos que indican que la pila IPv6 no está disponible en el host. */
const FAMILY_UNAVAILABLE_CODES = new Set([
  'EAFNOSUPPORT',
  'EADDRNOTAVAIL',
  'EPROTONOSUPPORT',
  'ENOTFOUND',
  'EAI_AGAIN',
]);

/** Errores de sistema que NO deben enmascararse con un fallback. */
const FATAL_CODES = new Set(['EADDRINUSE', 'EACCES']);

export function listenErrorCode(error: unknown): string | null {
  if (!error || typeof error !== 'object') return null;
  const code = (error as { code?: unknown }).code;
  return typeof code === 'string' && code.length > 0 ? code : null;
}

/**
 * `true` solo si tiene sentido reintentar en IPv4: la pila IPv6 no existe.
 * Un puerto ocupado (`EADDRINUSE`) o permisos insuficientes (`EACCES`) NO se
 * reintentan: reintentar ahí produce dos instancias en el mismo puerto.
 */
export function shouldFallbackToIpv4(error: unknown): boolean {
  const code = listenErrorCode(error);
  if (!code) return false;
  if (FATAL_CODES.has(code)) return false;
  return FAMILY_UNAVAILABLE_CODES.has(code);
}

/** Mensaje operativo sin datos sensibles, para el log de arranque. */
export function describeListenFailure(port: number, host: string, error: unknown): string {
  const code = listenErrorCode(error);
  const message = error instanceof Error ? error.message : String(error ?? 'error desconocido');
  if (code === 'EADDRINUSE') {
    return (
      `El puerto ${port} ya está en uso (${host}). ` +
      'Probablemente hay otra instancia del API en ejecución: se aborta para no ' +
      'servir dos procesos sobre el mismo puerto. Detalle: ' +
      message
    );
  }
  return `No se pudo escuchar en ${host}:${port}. Detalle: ${message}`;
}
