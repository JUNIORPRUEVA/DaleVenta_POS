import { HttpException, Injectable, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHmac } from 'node:crypto';

export type SupportCase = { id: string; reference: string; status: string; kind: string;
  messages: Array<{ authorType: string; authorName: string; body: string; createdAt: string }> };

@Injectable()
export class FullposSupportClient {
  constructor(private readonly config: ConfigService) {}

  async request(input: Record<string, unknown>): Promise<SupportCase> {
    const target = this.config.get<string>('APPYRA_CRM_SUPPORT_URL');
    const secret = this.config.get<string>('FULLPOS_SUPPORT_SHARED_SECRET');
    const unavailable = () => new ServiceUnavailableException(
      'No pudimos confirmar el registro en soporte. Reintenta este mismo envío.');
    if (!target || !secret || secret.length < 32) throw unavailable();
    let url: URL;
    try { url = new URL(target); } catch { throw unavailable(); }
    if (url.username || url.password || url.search || url.hash ||
      (url.protocol !== 'https:' && !(url.protocol === 'http:' && ['127.0.0.1', 'localhost'].includes(url.hostname)))) throw unavailable();
    const path = '/api/integrations/fullpos/support';
    url.pathname = path;
    const timestamp = Date.now().toString();
    const body = JSON.stringify(input);
    const signature = createHmac('sha256', secret).update(`${timestamp}\nPOST\n${path}\n${body}`).digest('hex');
    try {
      const response = await fetch(url, { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(10000),
        headers: { 'content-type': 'application/json', 'x-fullpos-timestamp': timestamp, 'x-fullpos-signature': signature }, body });
      // Un caso que no existe o es de otra empresa no es una caída del servicio:
      // el CRM responde 404 sin decir a quién pertenece. Se traduce a un 404
      // propio y genérico, sin propietario, referencia ni contenido.
      if (response.status === 404 && ['read', 'reply'].includes(String(input.action))) {
        throw new NotFoundException('No encontramos ese caso de soporte.');
      }
      if (!response.ok) throw unavailable();
      const result = await response.json() as { ok?: boolean; case?: SupportCase };
      if (!result.ok || !result.case?.id || !result.case.reference || !Array.isArray(result.case.messages)) throw unavailable();
      return result.case;
    } catch (error) {
      // El 404 intencional viaja tal cual; sólo los fallos reales se convierten
      // en 503 para que nadie reintente un recurso que no le pertenece.
      if (error instanceof HttpException) throw error;
      throw unavailable();
    }
  }
}

export function supportIntent(message: string): 'incident' | 'human' | null {
  const text = message.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim().replace(/[¿?]/g, '');
  if (/^(quiero |necesito |deseo )?(reportar|reporto|registrar) (una )?(averia|falla|incidencia)\s*[:.-]\s*\S/.test(text)) return 'incident';
  if (/^(?:(?:quiero|necesito|deseo|puedo|me gustaria) (?:hablar|comunicarme|contactar)(?: con)?|pasame con|comunicame con|conectame con) (?:una persona|un humano|soporte humano|un agente humano|alguien de soporte)(?:[.!\s]*|,? por favor[.!\s]*| (?:porque|sobre|para) .+)$/.test(text) ||
    /^(soporte humano|hablar con soporte humano)[.!\s]*$/.test(text)) return 'human';
  return null;
}
