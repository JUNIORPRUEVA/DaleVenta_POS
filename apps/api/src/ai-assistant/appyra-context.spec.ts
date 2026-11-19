import { createHmac } from 'node:crypto';
import { signCompanyContext, verifyAssistantContext } from './appyra-context';

/**
 * El verificador es la única puerta que protege los datos de una empresa cuando APPYRA IA pregunta
 * por la cuenta. Estas pruebas fijan las cuatro cosas que no pueden fallar: identidad del emisor,
 * firma, caducidad y empresa presente.
 */

const SECRET = 'secreto-de-pruebas-suficientemente-largo';

function sign(payload: Record<string, unknown>, secret = SECRET): string {
  const encoded = Buffer.from(JSON.stringify(payload), 'utf8').toString('base64url');
  const signature = createHmac('sha256', secret).update(encoded).digest('hex');
  return `${encoded}.${signature}`;
}

const NOW = 1_800_000_000;

function payload(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    c: 'empresa-1',
    u: 'usuario-1',
    r: 'ADMIN',
    e: NOW + 60,
    i: 'appyra-ai',
    a: 'fullpos-cloud',
    j: 'nonce-1',
    ...overrides,
  };
}

describe('verifyAssistantContext', () => {
  it('acepta un token de APPYRA con empresa y caducidad corta', () => {
    const result = verifyAssistantContext(sign(payload()), SECRET, { nowSeconds: NOW });
    expect(result).toEqual({ companyId: 'empresa-1', userId: 'usuario-1', role: 'ADMIN' });
  });

  it('rechaza un token manipulado', () => {
    const token = sign(payload());
    const [encoded, signature] = token.split('.');
    // Se cambia la empresa manteniendo la firma vieja: es justo el ataque que importa.
    const tampered = Buffer.from(JSON.stringify(payload({ c: 'empresa-2' })), 'utf8').toString(
      'base64url',
    );
    expect(verifyAssistantContext(`${tampered}.${signature}`, SECRET, { nowSeconds: NOW })).toBeNull();
    expect(verifyAssistantContext(`${encoded}.${'0'.repeat(64)}`, SECRET, { nowSeconds: NOW })).toBeNull();
  });

  it('rechaza un token caducado y uno con vida excesiva', () => {
    expect(
      verifyAssistantContext(sign(payload({ e: NOW - 1 })), SECRET, { nowSeconds: NOW }),
    ).toBeNull();
    // Un token «para siempre» no lo emitiría APPYRA: se descarta aunque la firma sea buena.
    expect(
      verifyAssistantContext(sign(payload({ e: NOW + 86_400 })), SECRET, { nowSeconds: NOW }),
    ).toBeNull();
  });

  it('rechaza el token del sentido contrario (FullPOS → APPYRA)', () => {
    // Éste es el que FullPOS firma en cada turno: no sirve para preguntar por la cuenta.
    const fullposToken = signCompanyContext(
      { companyId: 'empresa-1', userId: 'usuario-1', role: 'ADMIN' },
      SECRET,
      { nowSeconds: NOW },
    );
    expect(verifyAssistantContext(fullposToken, SECRET, { nowSeconds: NOW })).toBeNull();
  });

  it('rechaza tokens sin empresa, con otro secreto o con formato raro', () => {
    expect(verifyAssistantContext(sign(payload({ c: '   ' })), SECRET, { nowSeconds: NOW })).toBeNull();
    expect(verifyAssistantContext(sign(payload(), 'otro-secreto'), SECRET, { nowSeconds: NOW })).toBeNull();
    expect(verifyAssistantContext('no-es-un-token', SECRET, { nowSeconds: NOW })).toBeNull();
    expect(verifyAssistantContext('a.b.c', SECRET, { nowSeconds: NOW })).toBeNull();
    expect(verifyAssistantContext(null, SECRET, { nowSeconds: NOW })).toBeNull();
  });

  it('sin secreto configurado no acepta nada, aunque el token sea correcto', () => {
    expect(verifyAssistantContext(sign(payload()), '   ', { nowSeconds: NOW })).toBeNull();
  });
});
