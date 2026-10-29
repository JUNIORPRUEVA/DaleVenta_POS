import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  GUARDIAN_SECRET_FILE_SUFFIX,
  guardianSecretPresent,
  guardianSecretValue,
  resolveGuardianSecret,
} from './guardian.secret';
import { resolveGuardianWhatsAppProfile } from './guardian.whatsapp.config';

/**
 * Contrato de lectura de credenciales con Docker Secrets.
 *
 * Estas pruebas existen porque los secretos estaban montados en `/run/secrets`
 * y el backend leía solo variables de entorno: los archivos existían, pero el
 * proceso no podía usarlos (webhook 503/403 y API de plataforma 401 en UAT).
 *
 * Prioridad exigida: `NAME` (variable) gana sobre `NAME_FILE` (archivo), y la
 * ausencia de ambas es un fallo cerrado, nunca un valor vacío utilizable.
 */
describe('secretos Guardian con soporte *_FILE', () => {
  let dir: string;

  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), 'guardian-secret-'));
  });

  afterEach(() => {
    rmSync(dir, { recursive: true, force: true });
  });

  const writeSecret = (name: string, content: string): string => {
    const path = join(dir, name);
    writeFileSync(path, content, 'utf8');
    return path;
  };

  it('usa la variable de entorno cuando está definida', () => {
    const result = resolveGuardianSecret({ DEMO_TOKEN: 'desde-variable' }, 'DEMO_TOKEN');

    expect(result).toEqual({
      value: 'desde-variable',
      source: 'env',
      problem: null,
      filePath: null,
    });
  });

  it('cae al archivo cuando la variable no existe y recorta el salto de línea de Docker', () => {
    const path = writeSecret('token', 'desde-archivo\n');
    const result = resolveGuardianSecret({ DEMO_TOKEN_FILE: path }, 'DEMO_TOKEN');

    expect(result.source).toBe('file');
    expect(result.value).toBe('desde-archivo');
    expect(result.problem).toBeNull();
    expect(result.filePath).toBe(path);
  });

  it('la variable gana sobre el archivo y el archivo ni se consulta', () => {
    const path = writeSecret('token', 'desde-archivo');
    const result = resolveGuardianSecret(
      { DEMO_TOKEN: 'desde-variable', DEMO_TOKEN_FILE: path },
      'DEMO_TOKEN',
    );

    expect(result.source).toBe('env');
    expect(result.value).toBe('desde-variable');
  });

  it('una variable con solo espacios cuenta como ausente y usa el archivo', () => {
    const path = writeSecret('token', 'desde-archivo');
    const result = resolveGuardianSecret(
      { DEMO_TOKEN: '   ', DEMO_TOKEN_FILE: path },
      'DEMO_TOKEN',
    );

    expect(result.source).toBe('file');
    expect(result.value).toBe('desde-archivo');
  });

  it('sin variable ni archivo devuelve ausencia explícita (fail-closed)', () => {
    const result = resolveGuardianSecret({}, 'DEMO_TOKEN');

    expect(result.value).toBe('');
    expect(result.source).toBe('missing');
    expect(result.problem).toContain(`DEMO_TOKEN${GUARDIAN_SECRET_FILE_SUFFIX}`);
  });

  it('un archivo vacío no se acepta como credencial', () => {
    const path = writeSecret('token', '\n\n');
    const result = resolveGuardianSecret({ DEMO_TOKEN_FILE: path }, 'DEMO_TOKEN');

    expect(result.value).toBe('');
    expect(result.source).toBe('missing');
    expect(result.problem).toContain('vacío');
  });

  it('un archivo inexistente no lanza y se trata como ausente', () => {
    const path = join(dir, 'no-existe');
    const result = resolveGuardianSecret({ DEMO_TOKEN_FILE: path }, 'DEMO_TOKEN');

    expect(result.value).toBe('');
    expect(result.source).toBe('missing');
    expect(result.problem).toContain('no se pudo leer');
  });

  it('el problema nunca incluye el contenido del secreto', () => {
    const secret = 'valor-ultra-secreto-123';
    const result = resolveGuardianSecret(
      { DEMO_TOKEN_FILE: join(dir, 'no-existe'), DEMO_TOKEN: '' },
      'DEMO_TOKEN',
    );

    expect(result.problem ?? '').not.toContain(secret);
    expect(JSON.stringify(result)).not.toContain(secret);
  });

  it('los atajos de valor y presencia respetan ambas vías', () => {
    const path = writeSecret('token', 'desde-archivo');

    expect(guardianSecretValue({ DEMO_TOKEN_FILE: path }, 'DEMO_TOKEN')).toBe('desde-archivo');
    expect(guardianSecretPresent({ DEMO_TOKEN_FILE: path }, 'DEMO_TOKEN')).toBe(true);
    expect(guardianSecretPresent({}, 'DEMO_TOKEN')).toBe(false);
  });

  it('el perfil de WhatsApp acepta el token servido por archivo', () => {
    const path = writeSecret('wa_token', 'token-de-prueba-uat\n');
    const profile = resolveGuardianWhatsAppProfile({
      GUARDIAN_WA_CLOUD_TOKEN_FILE: path,
      GUARDIAN_WA_PHONE_NUMBER_ID: '1403225316204356',
      GUARDIAN_WA_WABA_ID: '1574660008027902',
      GUARDIAN_ALERT_RECIPIENTS: '18093987826',
    } as NodeJS.ProcessEnv);

    expect(profile.sender.tokenPresent).toBe(true);
    expect(profile.canSend).toBe(true);
    expect(profile.blockedReason).toBeNull();
  });

  it('sin token por ninguna vía el perfil sigue bloqueado', () => {
    const profile = resolveGuardianWhatsAppProfile({
      GUARDIAN_WA_PHONE_NUMBER_ID: '1403225316204356',
      GUARDIAN_ALERT_RECIPIENTS: '18093987826',
    } as NodeJS.ProcessEnv);

    expect(profile.sender.tokenPresent).toBe(false);
    expect(profile.canSend).toBe(false);
    expect(profile.blockedReason).toBe('WHATSAPP_SENDER_NOT_CONFIGURED');
  });
});
