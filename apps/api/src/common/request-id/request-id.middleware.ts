import { randomUUID } from 'node:crypto';
import type { NextFunction, Request, Response } from 'express';

/**
 * Identificador de correlación por petición.
 *
 * - Reutiliza `x-request-id` o `x-correlation-id` si el cliente/proxy envía uno válido.
 * - Si no llega o no es válido, genera un UUID v4 nuevo (nunca confía en el valor recibido).
 * - Se devuelve siempre en la respuesta para poder cruzar un reporte de soporte con los logs.
 *
 * Seguridad: solo se aceptan identificadores con un charset acotado y longitud
 * limitada, para evitar inyección de cabeceras o falsificación de líneas de log.
 * No se registran ni se propagan cabeceras de autenticación.
 */
export const REQUEST_ID_HEADER = 'x-request-id';
export const CORRELATION_ID_HEADER = 'x-correlation-id';

const REQUEST_ID_PATTERN = /^[A-Za-z0-9._:-]{8,128}$/;

export type RequestWithId = Request & { requestId?: string };

/** Devuelve el identificador recibido si es seguro; en caso contrario `null`. */
export function sanitizeRequestId(raw: unknown): string | null {
  const value = Array.isArray(raw) ? raw[0] : raw;
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (!REQUEST_ID_PATTERN.test(trimmed)) return null;
  return trimmed;
}

export function resolveRequestId(headers: Record<string, unknown>): string {
  return (
    sanitizeRequestId(headers[REQUEST_ID_HEADER]) ??
    sanitizeRequestId(headers[CORRELATION_ID_HEADER]) ??
    randomUUID()
  );
}

export function requestIdMiddleware(req: RequestWithId, res: Response, next: NextFunction) {
  const requestId = resolveRequestId((req.headers ?? {}) as Record<string, unknown>);

  req.requestId = requestId;
  res.setHeader(REQUEST_ID_HEADER, requestId);
  res.setHeader(CORRELATION_ID_HEADER, requestId);

  next();
}
