import { GuardianPlatformService } from './guardian.platform.service';

/**
 * `health()` debe informar el proveedor de IA REAL, no el que sugiere una
 * variable. Si el runtime degradó a mock, el panel tiene que decirlo.
 */
describe('GuardianPlatformService.health — honestidad del proveedor de IA', () => {
  const originalEnv = { ...process.env };

  function service() {
    const prisma = {
      guardianAlert: { count: jest.fn(async () => 0) },
      guardianIncident: { count: jest.fn(async () => 0), findFirst: jest.fn(async () => null) },
    };
    return new GuardianPlatformService(prisma as any, {} as any, {} as any);
  }

  afterEach(() => {
    process.env = { ...originalEnv };
  });

  it('reporta deepseek cuando la configuración es válida', async () => {
    process.env = {
      ...originalEnv,
      GUARDIAN_AI_PROVIDER: 'deepseek',
      GUARDIAN_AI_API_KEY: 'clave-uat',
      GUARDIAN_AI_MODEL: 'deepseek-flash',
    };

    const health = await service().health();

    expect(health.aiProvider).toBe('deepseek');
    expect(health.aiModel).toBe('deepseek-flash');
    expect(health.aiConfigurationIssues).toEqual([]);
  });

  it('reporta mock y el motivo cuando la configuración es incoherente', async () => {
    process.env = {
      ...originalEnv,
      GUARDIAN_AI_PROVIDER: 'deepseek',
      GUARDIAN_AI_API_KEY: 'clave-uat',
      GUARDIAN_AI_BASE_URL: 'https://api.openai.com/v1',
    };

    const health = await service().health();

    expect(health.aiProvider).toBe('mock');
    expect(health.aiModel).toBeNull();
    expect(health.aiConfigurationIssues).toContain('AI_BASE_URL_MISMATCH');
  });

  it('sin credencial no anuncia ningún proveedor real', async () => {
    delete process.env.GUARDIAN_AI_API_KEY;
    process.env.GUARDIAN_AI_PROVIDER = 'deepseek';

    const health = await service().health();

    expect(health.aiProvider).toBe('mock');
    expect(health.aiModel).toBeNull();
  });

  it('no reporta WhatsApp configurado por heredar credenciales de otro producto', async () => {
    process.env = {
      ...originalEnv,
      META_WA_TOKEN: 'token-de-otro-producto',
      META_PHONE_NUMBER_ID: '109900000000000',
    };
    delete process.env.GUARDIAN_WA_CLOUD_TOKEN;
    delete process.env.GUARDIAN_WA_PHONE_NUMBER_ID;

    const health = await service().health();

    expect(health.whatsappCloudConfigured).toBe(false);
  });
});
