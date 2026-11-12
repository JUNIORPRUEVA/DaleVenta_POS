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
