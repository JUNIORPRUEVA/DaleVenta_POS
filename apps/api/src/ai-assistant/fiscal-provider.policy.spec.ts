import { asksFiscalProvider, containsFiscalProvider, FISCAL_PROVIDER_SUPPORT_REPLY } from './fiscal-provider.policy';

describe('fiscal integration support boundary', () => {
  it.each(['¿Qué proveedor de facturación electrónica usan?', '¿Cuál es el nombre del proveedor fiscal?', '¿Con qué proveedor trabajan para e-CF?'])('routes identity questions to support: %s', question => {
    expect(asksFiscalProvider(question)).toBe(true);
  });
  it.each(['¿Cómo emito un E31?', '¿Cómo completo mi habilitación en DGII?', '¿Cómo registro una compra de mi proveedor?', '¿Necesito internet para facturar?'])('preserves product guidance: %s', question => {
    expect(asksFiscalProvider(question)).toBe(false);
  });
  it('does not disclose or promise an opened support case in the policy response', () => {
    expect(containsFiscalProvider(FISCAL_PROVIDER_SUPPORT_REPLY)).toBe(false);
    expect(FISCAL_PROVIDER_SUPPORT_REPLY).not.toMatch(/registrad|asignad|enviad/i);
  });
});
