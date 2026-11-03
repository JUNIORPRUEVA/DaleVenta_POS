import {
  Body,
  ConflictException,
  Controller,
  Get,
  HttpCode,
  Inject,
  Post,
  Req,
  ServiceUnavailableException,
  UseGuards,
} from "@nestjs/common";
import { AuthGuard } from "@nestjs/passport";
import { IsOptional, IsString, MaxLength } from "class-validator";
import type { Request } from "express";
import { Permissions } from "../../../auth/roles.decorator";
import { RolesGuard } from "../../../auth/roles.guard";
import { requireTenant, type TenantUser } from "../../../auth/tenant-context";
import { PrismaService } from "../../../prisma/prisma.service";
import {
  DosaCertificationIntentService,
  type DosaIntentRejection,
} from "./dosa-certification-intent.service";
import { DosaCredentialService } from "./dosa-credential.service";
import type { DosaCredentialEnvironment } from "./dosa-credential-vault.service";
import { ECF_DOSA_FISCAL_CONFIG } from "./dosa-emission.service";
import type { DosaCompanyFiscalConfigReader } from "./dosa-emission.service";

/** Cuerpo del registro de intención. */
export class RegisterDosaIntentDto {
  /**
   * RNC que el cliente cree conocer. **Solo se compara** con el del expediente:
   * nunca se acepta como identidad. Se admite para detectar clientes
   * desincronizados y responder con un motivo claro.
   */
  @IsOptional()
  @IsString()
  @MaxLength(32)
  rnc?: string;
}

export type DosaIntentHttpResponse = {
  ok: true;
  companyId: string;
  rnc: string;
  sessionId: string;
  attemptNo: number;
  created: boolean;
  status: string;
  provider: string;
  ecfEnabled: boolean;
  /** Siempre `false`: preparar no autoriza emisión. */
  fiscalAuthorizationGranted: false;
};

export type DosaIntentStateResponse = {
  ok: true;
  companyId: string;
  canonicalRnc: string | null;
  canonicalSource: string | null;
  ecfEnabled: boolean;
  provider: string;
  canRegister: boolean;
  blockingReasons: readonly string[];
  session: {
    id: string;
    status: string;
    attemptNo: number;
    sessionUrl: string | null;
  } | null;
  credentials: {
    environment: DosaCredentialEnvironment;
    status: string;
    /** Solo presencia: nunca el valor, ni siquiera con nombre de clave. */
    present: {
      hasProductionKey: boolean;
      hasTestKey: boolean;
      hasSecret: boolean;
    };
  } | null;
  fiscalAuthorizationGranted: false;
};

const REJECTION_HTTP: Record<DosaIntentRejection, "CONFLICT" | "UNAVAILABLE"> = {
  COMPANY_RNC_NOT_VERIFIED: "CONFLICT",
  RNC_DOES_NOT_MATCH_COMPANY_IDENTITY: "CONFLICT",
  AMBIGUOUS_RNC: "CONFLICT",
  SESSION_CLAIM_FAILED: "UNAVAILABLE",
};

/**
 * Preasociación empresa ↔ RNC de la Postulación Inteligente.
 *
 * Controlador **delgado a propósito**: no decide identidad, no elige empresa y no
 * toca credenciales. Traduce la petición autenticada al servicio, comprueba el
 * opt-in de e-CF y deja auditoría.
 *
 * Garantías:
 *
 * * La empresa sale **del contexto del servidor** (`requireTenant`). Un
 *   `companyId` en el cuerpo se ignora por completo: no existe en el DTO.
 * * El RNC sale del expediente fiscal del backend; el del cliente solo se compara.
 * * Registrar la intención **no activa** facturación electrónica: no se escribe
 *   en `ecf_company_configurations`, ni en credenciales, ni en secuencias.
 * * La respuesta no contiene claves fiscales ni secretos.
 * * Es idempotente: repetir devuelve la misma sesión con `created: false`; dos
 *   envíos simultáneos no crean dos intentos.
 *
 * Preparación y activación son estados **distintos** y no se confunden:
 *
 * * *Preparación* = esta fila de sesión, creada por la acción voluntaria de un
 *   administrador con `manageEcfOnboarding` sobre su propia empresa.
 * * *Activación* = `ecf_company_configurations.enabled` (módulo visible) y
 *   `production_enabled` (emisión real), que este controlador **nunca** toca.
 *
 * Por eso el opt-in de e-CF **no** se exige aquí: exigirlo obligaría a activar
 * el módulo antes de poder prepararlo, que es justo el orden inverso. La
 * autorización administrativa (autenticación + permiso + empresa del token) es
 * el opt-in de la preparación; la activación sigue teniendo sus propias
 * compuertas fiscales, intactas.
 */
@Controller("ecf/dosa")
@UseGuards(AuthGuard("jwt"), RolesGuard)
export class DosaCertificationIntentController {
  /** Peticiones en vuelo por empresa: corta ráfagas duplicadas. */
  private readonly inFlight = new Set<string>();

  constructor(
    private readonly prisma: PrismaService,
    private readonly intents: DosaCertificationIntentService,
    private readonly credentials: DosaCredentialService,
    // `DosaCompanyFiscalConfigReader` es una interfaz: en runtime no existe como
    // valor, asi que Nest no puede resolverla por tipo. Se inyecta por token.
    @Inject(ECF_DOSA_FISCAL_CONFIG)
    private readonly fiscalConfig: DosaCompanyFiscalConfigReader,
  ) {}

  @Post("certification-intent")
  @HttpCode(200)
  @Permissions("manageEcfOnboarding")
  async register(
    @Req() req: Request,
    @Body() body: RegisterDosaIntentDto,
  ): Promise<DosaIntentHttpResponse> {
    const user = req.user as TenantUser;
    // La empresa SIEMPRE viene del token, jamás del cuerpo.
    const companyId = requireTenant(user);

    if (this.inFlight.has(companyId)) {
      throw new ConflictException("ECF_DOSA_INTENT_IN_PROGRESS");
    }
    this.inFlight.add(companyId);
    try {
      // Informativo: el estado del módulo de emisión NO condiciona la
      // preparación. Puede no existir configuración todavía (`null`) y el
      // administrador sigue teniendo derecho a preparar su habilitación.
      const fiscal = await this.fiscalConfig.read(companyId);

      const result = await this.intents.register({
        companyId,
        userId: user.id,
        rncFromClient: body?.rnc ?? null,
      });

      if (!result.ok) {
        if (REJECTION_HTTP[result.reason] === "UNAVAILABLE") {
          throw new ServiceUnavailableException(result.reason);
        }
        throw new ConflictException(result.reason);
      }

      // Sin configuración fiscal todavía, el proveedor del intento es DOSA por
      // definición de este recurso; no se afirma nada sobre la configuración
      // de la empresa, que sigue sin crearse ni modificarse.
      const provider = fiscal?.provider ?? "DOSA";

      await this.audit(user, companyId, result.sessionId, {
        rnc: result.rnc,
        attemptNo: result.attemptNo,
        created: result.created,
        provider,
      });

      return {
        ok: true,
        companyId,
        rnc: result.rnc,
        sessionId: result.sessionId,
        attemptNo: result.attemptNo,
        created: result.created,
        status: result.created ? "NOT_STARTED" : "EXISTING",
        provider,
        ecfEnabled: fiscal?.ecfEnabled === true,
        fiscalAuthorizationGranted: false,
      };
    } finally {
      this.inFlight.delete(companyId);
    }
  }

  @Get("certification-intent")
  @Permissions("viewEcfOnboarding")
  async state(@Req() req: Request): Promise<DosaIntentStateResponse> {
    const companyId = requireTenant(req.user as TenantUser);
    const fiscal = await this.fiscalConfig.read(companyId);
    const described = await this.intents.describe({ companyId });
    const preview = await this.intents.preview({ companyId });

    const environment: DosaCredentialEnvironment = "test";
    const credential = described.canonicalRnc
      ? await this.credentials.inspect({
          companyId,
          rnc: described.canonicalRnc,
          environment,
        })
      : null;

    // `ecfEnabled` es solo informativo: describe el módulo de emisión, no la
    // preparación. `canRegister` depende únicamente de que exista identidad
    // fiscal verificable y no ambigua.
    const ecfEnabled = fiscal?.ecfEnabled === true;
    const blockingReasons = preview.ok ? [] : [preview.reason];

    return {
      ok: true,
      companyId,
      canonicalRnc: described.canonicalRnc,
      canonicalSource: described.canonicalSource,
      ecfEnabled,
      provider: fiscal?.provider ?? "DOSA",
      canRegister: preview.ok,
      blockingReasons,
      session: described.session,
      credentials: credential
        ? {
            environment: credential.environment,
            status: credential.status,
            present: {
              hasProductionKey: credential.present.apiKeyProduccion,
              hasTestKey: credential.present.apiKeyTest,
              hasSecret: credential.present.apiSecret,
            },
          }
        : null,
      fiscalAuthorizationGranted: false,
    };
  }

  /**
   * Auditoría del intento. Nunca escribe credenciales: solo identificadores y el
   * resultado. Un fallo de auditoría no invalida la sesión ya creada, pero
   * tampoco se inventa un registro.
   */
  private async audit(
    user: TenantUser,
    companyId: string,
    sessionId: string,
    payload: Record<string, unknown>,
  ): Promise<void> {
    try {
      await this.prisma.ecfAuditLog.create({
        data: {
          companyId,
          actorUserId: user.id ?? null,
          action: "ONBOARDING_STARTED",
          targetType: "DOSA_CERTIFICATION_INTENT",
          targetId: sessionId,
          metadata: payload as never,
        },
      });
    } catch {
      // Deliberado: la preparación no se cae por un fallo de auditoría.
    }
  }
}

export { ECF_DOSA_FISCAL_CONFIG };
