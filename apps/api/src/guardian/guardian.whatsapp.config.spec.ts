import {
  normalizeWhatsAppRecipient,
  parseAdminRecipients,
  resolveGuardianWhatsAppProfile,
} from './guardian.whatsapp.config';

function env(overrides: Record<string, string | undefined>): NodeJS.ProcessEnv {
  return { ...overrides } as NodeJS.ProcessEnv;
}

describe('Guardian WhatsApp — identidad del remitente oficial', () => {
  it('sin credenciales propias queda bloqueado (fail-closed)', () => {
    const profile = resolveGuardianWhatsAppProfile(env({}));
    expect(profile.provider).toBe('none');
    expect(profile.canSend).toBe(false);
    expect(profile.blockedReason).toBe('WHATSAPP_SENDER_NOT_CONFIGURED');
    expect(profile.sender.tokenPresent).toBe(false);
  });

  it('no hereda credenciales Meta de otros productos', () => {
    const profile = resolveGuardianWhatsAppProfile(
      env({
        META_WHATSAPP_TOKEN: 'token-de-otro-producto',
        META_ACCESS_TOKEN: 'otro-token',
        META_PHONE_NUMBER_ID: '999999',
        META_GRAPH_VERSION: 'v19.0',
        GUARDIAN_ALERT_RECIPIENT: '18095550000',
      }),
    );
    expect(profile.provider).toBe('none');
    expect(profile.canSend).toBe(false);
    expect(profile.sender.phoneNumberId).toBeNull();
    expect(profile.sender.tokenPresent).toBe(false);
  });

  it('con remitente pero sin destinatario no puede enviar', () => {
    const profile = resolveGuardianWhatsAppProfile(
      env({
        GUARDIAN_WA_CLOUD_TOKEN: 'token-propio',
        GUARDIAN_WA_PHONE_NUMBER_ID: '123456789',
      }),
    );
    expect(profile.provider).toBe('meta_cloud');
    expect(profile.canSend).toBe(false);
    expect(profile.blockedReason).toBe('ALERT_RECIPIENT_NOT_CONFIGURED');
  });

  it('resuelve remitente, plantillas y destinatarios administrativos', () => {
    const profile = resolveGuardianWhatsAppProfile(
      env({
        GUARDIAN_WA_CLOUD_TOKEN: 'token-propio',
        GUARDIAN_WA_PHONE_NUMBER_ID: '123456789',
        GUARDIAN_WA_WABA_ID: 'waba-1',
        GUARDIAN_WA_DISPLAY_NUMBER: '+1 (809) 555-0101',
        GUARDIAN_ALERT_RECIPIENTS: '18095550000; 18095550001,18095550000',
      }),
    );

    expect(profile.provider).toBe('meta_cloud');
    expect(profile.canSend).toBe(true);
    expect(profile.blockedReason).toBeNull();
    expect(profile.sender.apiVersion).toBe('v21.0');
    expect(profile.sender.displayNumber).toBe('18095550101');
    expect(profile.templates.incidentAlert.name).toBe('guardian_incident_alert');
    expect(profile.templates.incidentAlert.language).toBe('es');
    expect(profile.templates.incidentAlert.paramCount).toBe(8);
    // Orden de configuración y deduplicación.
    expect(profile.adminRecipients).toEqual(['18095550000', '18095550001']);
  });

  it('acepta variables de plantilla y versión de Graph configurables', () => {
    const profile = resolveGuardianWhatsAppProfile(
      env({
        GUARDIAN_WA_CLOUD_TOKEN: 'token-propio',
        GUARDIAN_WA_PHONE_NUMBER_ID: '123456789',
        GUARDIAN_WA_API_VERSION: 'v22.0',
        GUARDIAN_WA_TEMPLATE_NAME: 'guardian_alerta_admin',
        GUARDIAN_WA_TEMPLATE_LANG: 'es_DO',
        GUARDIAN_ALERT_RECIPIENT: '18095550000',
      }),
    );
    expect(profile.sender.apiVersion).toBe('v22.0');
    expect(profile.templates.incidentAlert.name).toBe('guardian_alerta_admin');
    expect(profile.templates.incidentAlert.language).toBe('es_DO');
  });
});

describe('normalización de destinatarios', () => {
  it('normaliza a dígitos E.164 y rechaza longitudes imposibles', () => {
    expect(normalizeWhatsAppRecipient('+1 809 555 0000')).toBe('18095550000');
    expect(normalizeWhatsAppRecipient('123')).toBeNull();
    expect(normalizeWhatsAppRecipient('1234567890123456')).toBeNull();
    expect(normalizeWhatsAppRecipient('')).toBeNull();
  });

  it('parsea listas separadas por coma o punto y coma sin duplicados', () => {
    expect(parseAdminRecipients('18095550000, 18095550001;18095550000')).toEqual([
      '18095550000',
      '18095550001',
    ]);
    expect(parseAdminRecipients(undefined)).toEqual([]);
    expect(parseAdminRecipients('no-es-un-numero')).toEqual([]);
  });
});
