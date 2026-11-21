import { AiAssistantService } from './ai-assistant.service';

describe('nombres del contexto de Facturación', () => {
  const service = Object.create(AiAssistantService.prototype) as AiAssistantService;
  it('corrige el nombre de clientes anteriores conservando ruta, módulo y cotización', () => {
    const context = service['normalizeContext']({
      module: 'cotizaciones', route: '/cotizaciones?quoteId=quote-123', screenName: 'Cotizaciones',
      entityType: 'quote', entityId: 'quote-123',
    });
    expect(context).toMatchObject({module:'cotizaciones',screenName:'Facturación',route:'/cotizaciones?quoteId=quote-123',entityType:'quote',entityId:'quote-123'});
  });
  it('distingue el historial y no sustituye nombres de otros módulos', () => {
    expect(service['normalizeContext']({module:'cotizaciones',route:'/cotizaciones/historial',screenName:'Cotizaciones'}).screenName).toBe('Historial de cotizaciones');
    expect(service['normalizeContext']({module:'clientes',route:'/clientes',screenName:'Mis clientes'}).screenName).toBe('Mis clientes');
  });
  it('la ayuda del POS explica ventas y cotizaciones por separado', () => {
    const help = service['staticScreenHelp']('cotizaciones','Facturación');
    expect(help).toContain('cobras ventas');
    expect(help).toContain('Cotizar');
    expect(help).toContain('Historial de cotizaciones');
  });
});
