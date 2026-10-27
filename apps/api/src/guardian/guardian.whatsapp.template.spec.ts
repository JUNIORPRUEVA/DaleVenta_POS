import { GuardianSeverity } from '@prisma/client';
import { buildGuardianAlertTemplateParams } from './guardian.alert.service';
import {
  GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_BODY,
  GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_PARAM_COUNT,
  GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_PARAMS,
  resolveGuardianWhatsAppProfile,
} from './guardian.whatsapp.config';

/**
 * Contrato de la plantilla administrativa `guardian_incident_alert`.
 *
 * Estas pruebas son la red de seguridad del texto que se introduce en WhatsApp
 * Manager: si alguien cambia el número o el orden de los parámetros en el código
 * sin actualizar la plantilla aprobada, la prueba falla.
 */
describe('plantilla administrativa guardian_incident_alert', () => {
  it('declara exactamente 8 parámetros, en orden y sin huecos', () => {
    expect(GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_PARAM_COUNT).toBe(8);
    expect(GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_PARAMS.map((param) => param.position)).toEqual([
      1, 2, 3, 4, 5, 6, 7, 8,
    ]);
    expect(GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_PARAMS.map((param) => param.key)).toEqual([
      'severity',
      'company',
      'moduleOperation',
      'occurredAtLocal',
      'problem',
      'diagnosis',
      'impact',
      'incidentShortId',
    ]);
  });

  it('el cuerpo usa cada marcador una sola vez y en orden', () => {
    const positions = [...GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_BODY.matchAll(/\{\{(\d)\}\}/g)].map(
      (match) => Number(match[1]),
    );

    expect(positions).toEqual([1, 2, 3, 4, 5, 6, 7, 8]);
    for (let index = 1; index <= 8; index += 1) {
      const occurrences = GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_BODY.split(`{{${index}}}`).length - 1;
      expect(occurrences).toBe(1);
    }
  });

  it('declara el estado del incidente en texto fijo, sin añadir parámetros', () => {
    expect(GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_BODY).toContain(
      'Estado: incidente registrado, investigación en curso.',
    );
    expect(GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_BODY).toContain('{{8}}');
    expect(GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_BODY).not.toContain('{{9}}');
  });

  it('no pide ni muestra datos fiscales, de clientes finales ni enlaces no aprobados', () => {
    const body = GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_BODY;

    expect(body).not.toMatch(/RNC|C[eé]dula|NCF|e-?CF|correo|email|@/i);
    // El contrato actual no contempla enlace al panel: si se añade, debe
    // actualizarse la plantilla aprobada y este documento a la vez.
    expect(body).not.toMatch(/https?:\/\//i);
  });

  it('cada ejemplo sintético respeta la longitud declarada y no contiene datos personales', () => {
    for (const param of GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_PARAMS) {
      expect(param.sample.length).toBeLessThanOrEqual(param.maxChars);
      expect(param.sample).not.toMatch(/@|\+?\d{10,}|RNC|C[eé]dula/i);
    }
  });

  it('buildGuardianAlertTemplateParams produce 8 valores en el orden de la plantilla', () => {
    const params = buildGuardianAlertTemplateParams({
      severity: GuardianSeverity.SEV1,
      companyName: 'Comercial Ejemplo SRL',
      module: 'caja',
      operation: 'cierre de sesión',
      occurredAt: new Date('2026-10-26T03:15:00.000Z'),
      problem: 'El cierre de caja no completa el cálculo del efectivo esperado',
      diagnosis: null,
      impact: null,
      incidentId: '4f2a9c11-2222-3333-4444-555566667777',
    });

    expect(params).toHaveLength(GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_PARAM_COUNT);
    expect(params[0]).toBe('CRÍTICO');
    expect(params[1]).toBe('Comercial Ejemplo SRL');
    expect(params[2]).toBe('caja / cierre de sesión');
    expect(params[3]).toMatch(/^\d{2}\/\d{2}, \d{2}:\d{2} [ap]\. m\.$/);
    expect(params[5]).toBe('Información pendiente de confirmar.');
    expect(params[6]).toBe('Pendiente de determinar.');
    expect(params[7]).toBe('INC-4F2A9C');
  });

  it('recorta cada parámetro al maxChars declarado sin tocar los que ya caben', () => {
    const params = buildGuardianAlertTemplateParams({
      severity: GuardianSeverity.SEV2,
      companyName: 'E'.repeat(300),
      module: 'M'.repeat(120),
      operation: 'O'.repeat(120),
      occurredAt: new Date('2026-10-26T03:15:00.000Z'),
      problem: 'P'.repeat(900),
      diagnosis: 'D'.repeat(900),
      impact: 'I'.repeat(900),
      incidentId: '4f2a9c11-2222-3333-4444-555566667777',
    });

    // Ningún valor puede superar el límite de su posición: Meta rechaza el envío
    // con error permanente y la alerta se perdería sin reintento.
    params.forEach((value, index) => {
      expect(value.length).toBeLessThanOrEqual(
        GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_PARAMS[index].maxChars,
      );
    });
    expect(params[0]).toBe('ALTO');
    expect(params[3]).toMatch(/^\d{2}\/\d{2}, \d{2}:\d{2} [ap]\. m\.$/);
    expect(params[7]).toBe('INC-4F2A9C');
  });

  it('el perfil de WhatsApp expone el mismo número de parámetros que el contrato', () => {
    const profile = resolveGuardianWhatsAppProfile({
      GUARDIAN_WA_CLOUD_TOKEN: 'token-uat',
      GUARDIAN_WA_PHONE_NUMBER_ID: '109999999999001',
      GUARDIAN_ALERT_RECIPIENTS: '+18095550000',
    } as NodeJS.ProcessEnv);

    expect(profile.templates.incidentAlert.name).toBe('guardian_incident_alert');
    expect(profile.templates.incidentAlert.language).toBe('es');
    expect(profile.templates.incidentAlert.category).toBe('UTILITY');
    expect(profile.templates.incidentAlert.paramCount).toBe(8);
    expect(profile.canSend).toBe(true);
  });
});
