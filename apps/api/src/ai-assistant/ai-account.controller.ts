import { Controller, Get, Headers, Logger, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { CONTEXT_SECRET_ENV, verifyAssistantContext } from './appyra-context';
import { LicenseService } from '../license/license.service';

/**
 * CONSULTA DE CUENTA PARA EL ASISTENTE (APPYRA IA).
 *
 * POR QUÉ EXISTE
 * --------------
 * El asistente responde a clientes por el chat de la app y por WhatsApp. Cuando alguien pregunta
 * «¿por qué no me deja vender?» o «¿cuándo vence mi plan?», la respuesta correcta depende de datos
 * que sólo tiene FullPOS. Sin este endpoint, el modelo improvisaba o decía que no tenía acceso.
 *
 * CÓMO SE PROTEGE
 * ---------------
 * No usa JWT de usuario (APPYRA no lo tiene) ni el secreto de administración de licencias (sería
 * demasiado poder para una consulta). Exige un token HMAC firmado por APPYRA con el secreto
 * compartido, dirigido a `fullpos-cloud`, con caducidad de segundos. La empresa sale **del token**,
 * nunca de la URL ni del cuerpo: no hay forma de pedir la cuenta de otro negocio.
 *
 * SÓLO LECTURA. No activa, bloquea ni modifica nada: si el cliente necesita un cambio de plan, el
 * asistente lo deriva al equipo, que es quien tiene permiso para hacerlo.
 */
@Controller('ai')
export class AiAccountController {
  private readonly logger = new Logger(AiAccountController.name);

  constructor(
    private readonly config: ConfigService,
    private readonly licenses: LicenseService,
  ) {}

  @Get('account')
  async account(@Headers('x-appyra-context') token?: string | string[]) {
    const raw = Array.isArray(token) ? token[0] : token;
    const secret = this.config.get<string>(CONTEXT_SECRET_ENV) ?? '';
    const verified = verifyAssistantContext(raw, secret);
    if (verified === null) {
      // Sin detalle del motivo: un token caducado y uno falsificado se responden igual.
      this.logger.warn('Consulta de cuenta rechazada: contexto de APPYRA ausente o inválido.');
      throw new UnauthorizedException('Contexto del asistente inválido.');
    }

    const summary = await this.licenses.getAssistantAccountSummary(verified.companyId);
    return { ok: true, account: summary };
  }
}
