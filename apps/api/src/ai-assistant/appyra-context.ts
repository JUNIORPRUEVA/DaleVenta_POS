import { createHmac, randomUUID } from 'node:crypto';

/**
 * CONTEXTO DE EMPRESA FIRMADO (FullPOS → APPYRA IA).
 *
 * POR QUÉ EXISTE
 * --------------
 * Todas las empresas clientes comparten el mismo tenant de APPYRA (`fulltech`). Si la empresa
 * viajara como un campo del cuerpo, cualquiera podría cambiarlo y leer o crear incidencias de otro
 * negocio. Por eso se firma aquí, en el backend, con un secreto que **sólo** existe en los entornos
 * de los dos servidores.
 *
 * QUÉ ENTRA EN EL TOKEN
 * ---------------------
 * Sólo lo necesario: empresa, usuario, rol, emisor, destinatario, caducidad corta y un identificador
 * único (para que APPYRA rechace la reutilización del mismo token).
 *
 * QUÉ NO ENTRA
 * ------------
 * Ni el token de sesión del usuario, ni su correo, ni permisos completos, ni nada que Flutter pueda
 * leer: el cliente nunca ve este valor.
 */

export interface FullposCompanyContext {
  readonly companyId: string;
  readonly userId: string;
  /** Rol efectivo del usuario en FullPOS. `ADMIN` es el único que habilita cambios de estado. */
  readonly role: string;
  /**
   * Nombre visible de la empresa, **firmado** dentro del token.
   *
   * Sirve para que el aviso al encargado diga el nombre del negocio y no un identificador. Se firma
   * aquí, en el backend, con el nombre que consta en la base de datos de FullPOS: el cliente nunca
   * lo envía, así que no puede alterarlo.
   */
  readonly companyName?: string;
}

export const CONTEXT_SECRET_ENV = 'APPYRA_IA_COMPANY_CONTEXT_SECRET';
const ISSUER = 'fullpos-cloud';
const AUDIENCE = 'appyra-ai';
/** Caducidad corta: el token se usa una vez, en la petición que lo lleva. */
const DEFAULT_TTL_SECONDS = 120;

export interface SignOptions {
  readonly ttlSeconds?: number;
  readonly nowSeconds?: number;
  readonly jti?: string;
}

/**
 * Firma el contexto. Devuelve `null` si falta el secreto: preferimos no enviar contexto antes que
 * enviar uno sin firmar (APPYRA lo rechazaría igual, pero así falla en el sitio correcto).
 */
export function signCompanyContext(
  context: FullposCompanyContext,
  secret: string,
  options: SignOptions = {},
): string | null {
  const cleanSecret = secret.trim();
  if (cleanSecret === '') {
    return null;
  }
  if (context.companyId.trim() === '' || context.userId.trim() === '') {
    return null;
  }

  const now = options.nowSeconds ?? Math.floor(Date.now() / 1000);
  const payload = {
    c: context.companyId,
    u: context.userId,
    r: context.role,
    e: now + (options.ttlSeconds ?? DEFAULT_TTL_SECONDS),
    i: ISSUER,
    a: AUDIENCE,
    j: options.jti ?? randomUUID(),
    ...(context.companyName === undefined || context.companyName.trim() === ''
      ? {}
      : { n: context.companyName.trim().slice(0, 120) }),
  };

  const encoded = Buffer.from(JSON.stringify(payload), 'utf8').toString('base64url');
  const signature = createHmac('sha256', cleanSecret).update(encoded).digest('hex');
  return `${encoded}.${signature}`;
}

/**
 * CONTEXTO DE EMPRESA FIRMADO, SENTIDO INVERSO (APPYRA IA → FullPOS).
 *
 * POR QUÉ
 * -------
 * El asistente necesita datos reales de la cuenta (licencia, plan, vencimiento y uso) para
 * responder «mi licencia está vencida» sin inventar. Esos datos viven en FullPOS, así que APPYRA
 * tiene que poder preguntarlos.
 *
 * CÓMO SE AUTENTICA
 * -----------------
 * El mismo secreto compartido (`APPYRA_IA_COMPANY_CONTEXT_SECRET`), con el emisor y el destinatario
 * **invertidos**: firma `appyra-ai` y va dirigido a `fullpos-cloud`. Caducidad muy corta y `jti`
 * propio para no reutilizar el token del turno.
 *
 * QUÉ NO HACE
 * -----------
 * No autoriza ninguna escritura: el único endpoint que lo acepta es de **lectura** y devuelve un
 * resumen saneado de la propia empresa. Sin `companyId` en el token no hay consulta posible, así
 * que un token manipulado no puede pedir datos de otro negocio.
 */
const ASSISTANT_ISSUER = 'appyra-ai';
const ASSISTANT_AUDIENCE = 'fullpos-cloud';
/** Vida muy corta: el token se usa en la petición en curso y nada más. */
const ASSISTANT_MAX_TTL_SECONDS = 300;

export interface VerifiedAssistantContext {
  readonly companyId: string;
  readonly userId: string | null;
  readonly role: string;
}

/**
 * Verifica un token emitido por APPYRA IA.
 *
 * Devuelve `null` ante cualquier anomalía (formato, firma, emisor, destinatario, caducidad). No se
 * distingue el motivo hacia fuera: quien llama responde 401 y no da pistas.
 */
export function verifyAssistantContext(
  token: string | null | undefined,
  secret: string,
  options: { readonly nowSeconds?: number } = {},
): VerifiedAssistantContext | null {
  const cleanSecret = secret.trim();
  const raw = (token ?? '').trim();
  if (cleanSecret === '' || raw === '') {
    return null;
  }

  const parts = raw.split('.');
  if (parts.length !== 2) {
    return null;
  }
  const [encoded, signature] = parts;
  if (encoded === undefined || signature === undefined || encoded === '' || signature === '') {
    return null;
  }

  const expected = createHmac('sha256', cleanSecret).update(encoded).digest('hex');
  // Comparación de longitud constante: evita filtrar cuántos caracteres coinciden.
  if (!timingSafeEqualHex(expected, signature)) {
    return null;
  }

  let payload: unknown;
  try {
    payload = JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8'));
  } catch {
    return null;
  }
  if (payload === null || typeof payload !== 'object') {
    return null;
  }

  const data = payload as Record<string, unknown>;
  if (data['i'] !== ASSISTANT_ISSUER || data['a'] !== ASSISTANT_AUDIENCE) {
    return null;
  }

  const now = options.nowSeconds ?? Math.floor(Date.now() / 1000);
  const expiresAt = typeof data['e'] === 'number' ? data['e'] : NaN;
  if (!Number.isFinite(expiresAt) || expiresAt <= now) {
    return null;
  }
  // Un token con vida absurda tampoco se acepta: significaría que no lo emitió APPYRA.
  if (expiresAt - now > ASSISTANT_MAX_TTL_SECONDS) {
    return null;
  }

  const companyId = typeof data['c'] === 'string' ? data['c'].trim() : '';
  if (companyId === '') {
    return null;
  }
  const userId = typeof data['u'] === 'string' && data['u'].trim() !== '' ? data['u'].trim() : null;
  const role = typeof data['r'] === 'string' ? data['r'] : '';

  return { companyId, userId, role };
}

function timingSafeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) {
    return false;
  }
  let diff = 0;
  for (let index = 0; index < a.length; index += 1) {
    diff |= a.charCodeAt(index) ^ b.charCodeAt(index);
  }
  return diff === 0;
}
