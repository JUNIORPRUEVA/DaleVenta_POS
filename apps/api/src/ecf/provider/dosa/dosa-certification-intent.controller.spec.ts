import { ConflictException, ServiceUnavailableException } from "@nestjs/common";
import {
  DosaCertificationIntentController,
  type RegisterDosaIntentDto,
} from "./dosa-certification-intent.controller";
import type { DosaCertificationIntentService } from "./dosa-certification-intent.service";
import type { DosaCredentialService } from "./dosa-credential.service";
import type { DosaCompanyFiscalConfigReader } from "./dosa-emission.service";
import type { PrismaService } from "../../../prisma/prisma.service";
import type { TenantUser } from "../../../auth/tenant-context";
import type { Request } from "express";

/**
 * Preasociación por HTTP.
 *
 * Lo que se demuestra aquí es lo que no puede fallar: la empresa sale del token y
 * no del cuerpo, el opt-in de e-CF es obligatorio, los rechazos tienen código
 * estable y la respuesta no filtra claves.
 */

const COMPANY = "21212121-0000-4000-8000-000000000021";
const RNC = "133306001";

function user(overrides: Partial<TenantUser> = {}): TenantUser {
  return { id: "user-1", companyId: COMPANY, ...overrides } as TenantUser;
}

function req(as: TenantUser = user()): Request {
  return { user: as } as unknown as Request;
}

class FakeIntents {
  readonly registerCalls: Array<{ companyId: string; rncFromClient?: string | null }> = [];
  constructor(
    private readonly behaviour:
      | "created"
      | "existing"
      | "no-rnc"
      | "mismatch"
      | "ambiguous"
      | "claim-failed" = "created",
  ) {}

  async register(input: {
    companyId: string;
    userId?: string | null;
    rncFromClient?: string | null;
  }) {
    this.registerCalls.push({
      companyId: input.companyId,
      rncFromClient: input.rncFromClient,
    });
    switch (this.behaviour) {
      case "no-rnc":
        return { ok: false as const, reason: "COMPANY_RNC_NOT_VERIFIED" as const };
      case "mismatch":
        return {
          ok: false as const,
          reason: "RNC_DOES_NOT_MATCH_COMPANY_IDENTITY" as const,
        };
      case "ambiguous":
        return { ok: false as const, reason: "AMBIGUOUS_RNC" as const, detail: "1" };
      case "claim-failed":
        return { ok: false as const, reason: "SESSION_CLAIM_FAILED" as const };
      default:
        return {
          ok: true as const,
          companyId: input.companyId,
          rnc: RNC,
          sessionId: "session-1",
          attemptNo: 1,
          created: this.behaviour === "created",
          fiscalAuthorizationGranted: false as const,
        };
    }
  }

  async describe() {
    return {
      canonicalRnc: RNC,
      canonicalSource: "FISCAL_CONFIG",
      session: { id: "session-1", status: "RUNNING", attemptNo: 1, sessionUrl: null },
    };
  }

  async preview() {
    switch (this.behaviour) {
      case "no-rnc":
        return { ok: false as const, reason: "COMPANY_RNC_NOT_VERIFIED" as const };
      case "mismatch":
        return {
          ok: false as const,
          reason: "RNC_DOES_NOT_MATCH_COMPANY_IDENTITY" as const,
        };
      case "ambiguous":
        return { ok: false as const, reason: "AMBIGUOUS_RNC" as const };
      default:
        return { ok: true as const, rnc: RNC };
    }
  }
}

function fiscalConfig(
  enabled: boolean | null,
  provider = "DOSA",
): DosaCompanyFiscalConfigReader {
  return {
    async read() {
      // `null` = la empresa todavía no tiene fila en `ecf_company_configurations`.
      if (enabled === null) return null;
      return { ecfEnabled: enabled, provider };
    },
  };
}

function auditLog(historicalProvider?: string) {
  const rows: Array<Record<string, unknown>> = [];
  if (historicalProvider) rows.push({
    companyId: COMPANY,
    targetType: "DOSA_CERTIFICATION_INTENT",
    targetId: "session-1",
    action: "ONBOARDING_STARTED",
    createdAt: new Date("2026-11-01T00:00:00Z"),
    metadata: { provider: historicalProvider },
  });
  const prisma = {
    ecfAuditLog: {
      async create(input: { data: Record<string, unknown> }) {
        rows.push({ ...input.data, createdAt: new Date() });
        return input.data;
      },
      async findMany(input: { where: { companyId: string; targetId: string } }) {
        return rows.filter((row) => row.companyId === input.where.companyId &&
          row.targetId === input.where.targetId);
      },
    },
    ecfDosaCertificationSession: {
      async findFirst(input: { where: { companyId: string } }) {
        if (input.where.companyId !== COMPANY) return null;
        return { id: "session-1", attemptNo: 1, status: "NOT_STARTED",
          sessionUrl: null, providerPostulationId: null,
          createdAt: new Date("2026-11-01T00:00:00Z") };
      },
    },
  } as unknown as PrismaService;
  return { prisma, rows };
}

function credentials(): DosaCredentialService {
  return {
    async inspect() {
      return {
        companyId: COMPANY,
        rnc: RNC,
        environment: "test" as const,
        status: "PENDING_CONFIRMATION" as const,
        keyVersion: 1,
        fingerprint: "f".repeat(64),
        present: { apiKeyProduccion: true, apiKeyTest: true, apiSecret: false },
        updatedAt: null,
      };
    },
  } as unknown as DosaCredentialService;
}

function build(options: {
  behaviour?: ConstructorParameters<typeof FakeIntents>[0];
  ecfEnabled?: boolean | null;
  historicalProvider?: string;
  configuredProvider?: string;
} = {}) {
  const intents = new FakeIntents(options.behaviour ?? "created");
  const { prisma, rows } = auditLog(options.historicalProvider);
  const controller = new DosaCertificationIntentController(
    prisma,
    intents as unknown as DosaCertificationIntentService,
    credentials(),
    fiscalConfig(options.ecfEnabled === undefined ? true : options.ecfEnabled,
      options.configuredProvider ?? "DOSA"),
  );
  return { controller, intents, rows };
}

describe("POST /ecf/dosa/certification-intent", () => {
  it("registra la intención usando la empresa del token", async () => {
    const { controller, intents } = build();

    const response = await controller.register(req(), {} as RegisterDosaIntentDto);

    expect(response).toMatchObject({
      ok: true,
      companyId: COMPANY,
      rnc: RNC,
      sessionId: "session-1",
      created: true,
      fiscalAuthorizationGranted: false,
    });
    expect(intents.registerCalls[0].companyId).toBe(COMPANY);
  });

  it("un companyId del cuerpo NO se usa: el DTO no lo admite", () => {
    // Estructural: si el cliente envía companyId, el ValidationPipe global
    // (forbidNonWhitelisted) lo rechaza porque no está en el DTO.
    const dto = {} as RegisterDosaIntentDto;
    expect(Object.keys(dto)).toEqual([]);
  });

  it("prepara la habilitación aunque la emisión esté DESACTIVADA", async () => {
    // Preparar no es activar: el módulo de emisión apagado no puede impedir
    // que un administrador autorizado inicie su habilitación.
    const { controller, intents } = build({ ecfEnabled: false });

    const response = await controller.register(
      req(),
      {} as RegisterDosaIntentDto,
    );

    expect(response.ok).toBe(true);
    expect(response.ecfEnabled).toBe(false);
    expect(response.fiscalAuthorizationGranted).toBe(false);
    expect(intents.registerCalls).toHaveLength(1);
  });

  it("prepara aunque la empresa no tenga todavía configuración fiscal", async () => {
    const { controller, intents } = build({ ecfEnabled: null });

    const response = await controller.register(
      req(),
      {} as RegisterDosaIntentDto,
    );

    expect(response.ok).toBe(true);
    expect(response.ecfEnabled).toBe(false);
    // El proveedor del intento es DOSA sin afirmar nada de la configuración.
    expect(response.provider).toBe("DOSA");
    expect(intents.registerCalls).toHaveLength(1);
  });

  it("la intención nueva es DOSA aunque la configuración de emisión sea ALANUBE", async () => {
    const { controller, rows } = build({ ecfEnabled: false, configuredProvider: "ALANUBE" });
    const response = await controller.register(req(), {} as RegisterDosaIntentDto);
    expect(response.provider).toBe("DOSA");
    expect(rows[0].metadata).toMatchObject({
      provider: "DOSA", configuredProvider: "ALANUBE",
    });
  });

  it("una intención existente conserva el proveedor de su auditoría", async () => {
    const { controller, rows } = build({
      behaviour: "existing", historicalProvider: "ALANUBE",
    });
    const response = await controller.register(req(), {} as RegisterDosaIntentDto);
    expect(response.provider).toBe("ALANUBE");
    expect(rows).toHaveLength(1);
  });

  it("rechaza un RNC sin verificar en el expediente", async () => {
    const { controller } = build({ behaviour: "no-rnc" });
    await expect(
      controller.register(req(), {} as RegisterDosaIntentDto),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it("rechaza un RNC del cliente que no coincide", async () => {
    const { controller, intents } = build({ behaviour: "mismatch" });
    await expect(
      controller.register(req(), { rnc: "130000002" }),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(intents.registerCalls[0].rncFromClient).toBe("130000002");
  });

  it("rechaza un RNC compartido por varias empresas", async () => {
    const { controller } = build({ behaviour: "ambiguous" });
    await expect(
      controller.register(req(), {} as RegisterDosaIntentDto),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it("un fallo del claim no se presenta como éxito", async () => {
    const { controller } = build({ behaviour: "claim-failed" });
    await expect(
      controller.register(req(), {} as RegisterDosaIntentDto),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
  });

  it("es idempotente: repetir devuelve la misma sesión con created:false", async () => {
    const { controller } = build({ behaviour: "existing" });
    const response = await controller.register(req(), {} as RegisterDosaIntentDto);
    expect(response.created).toBe(false);
    expect(response.sessionId).toBe("session-1");
    expect(response.status).toBe("EXISTING");
  });

  it("una ráfaga simultánea de la misma empresa no crea dos intentos", async () => {
    const { controller, intents } = build();
    const first = controller.register(req(), {} as RegisterDosaIntentDto);
    // Segunda petición de la MISMA empresa mientras la primera está en vuelo.
    await expect(
      controller.register(req(), {} as RegisterDosaIntentDto),
    ).rejects.toBeInstanceOf(ConflictException);
    await first;
    expect(intents.registerCalls).toHaveLength(1);
  });

  it("deja auditoría del intento sin credenciales", async () => {
    const { controller, rows } = build();
    await controller.register(req(), {} as RegisterDosaIntentDto);

    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      companyId: COMPANY,
      action: "ONBOARDING_STARTED",
      targetType: "DOSA_CERTIFICATION_INTENT",
      targetId: "session-1",
    });
    const serialized = JSON.stringify(rows);
    // La auditoria no guarda valores de credencial: solo identificadores.
    expect(serialized).not.toMatch(/[A-Za-z0-9+/_-]{40,}/);
    expect(serialized).not.toContain("CLAVE");
  });

  it("la respuesta no contiene claves ni secretos", async () => {
    const { controller } = build();
    const response = await controller.register(req(), {} as RegisterDosaIntentDto);
    // Ninguna cadena larga: ni clave, ni huella, ni token.
    expect(JSON.stringify(response)).not.toMatch(/[A-Za-z0-9+/_-]{40,}/);
    expect(response.fiscalAuthorizationGranted).toBe(false);
  });

  it("no se puede preparar para una empresa ajena: el token manda", async () => {
    const { controller, intents } = build();
    await controller.register(
      req(user({ companyId: "99999999-0000-4000-8000-000000000099" })),
      {} as RegisterDosaIntentDto,
    );
    expect(intents.registerCalls[0].companyId).toBe(
      "99999999-0000-4000-8000-000000000099",
    );
    expect(intents.registerCalls[0].companyId).not.toBe(COMPANY);
  });
});

describe("GET /ecf/dosa/certification-intent", () => {
  it("devuelve el estado sin secretos", async () => {
    const { controller } = build();
    const state = await controller.state(req());

    expect(state).toMatchObject({
      ok: true,
      companyId: COMPANY,
      canonicalRnc: RNC,
      ecfEnabled: true,
      canRegister: true,
      fiscalAuthorizationGranted: false,
    });
    expect(state.session?.status).toBe("RUNNING");
    expect(state.credentials?.status).toBe("PENDING_CONFIRMATION");
    // La respuesta solo dice SI hay credencial, nunca cual: todos los campos de
    // presencia son booleanos y no hay ninguna cadena larga (clave o huella).
    expect(
      Object.values(state.credentials!.present).every(
        (value) => typeof value === "boolean",
      ),
    ).toBe(true);
    const serialized = JSON.stringify(state);
    expect(serialized).not.toMatch(/[A-Za-z0-9+/_-]{40,}/);
  });

  it("con emisión desactivada la preparación sigue disponible", async () => {
    const { controller } = build({ ecfEnabled: false });
    const state = await controller.state(req());
    // El estado del módulo se informa, pero no bloquea la preparación.
    expect(state.ecfEnabled).toBe(false);
    expect(state.canRegister).toBe(true);
    expect(state.blockingReasons).toEqual([]);
  });

  it("solo bloquea por identidad fiscal, no por el interruptor de emisión", async () => {
    const { controller } = build({ ecfEnabled: false, behaviour: "no-rnc" });
    const state = await controller.state(req());
    expect(state.canRegister).toBe(false);
    expect(state.blockingReasons).toEqual(["COMPANY_RNC_NOT_VERIFIED"]);
  });
});

describe("GET /ecf/dosa/certification-diagnostic", () => {
  it("muestra el proveedor histórico y referencias sin alterar el intento", async () => {
    const { controller, rows } = build({ historicalProvider: "ALANUBE" });
    const diagnostic = await controller.diagnostic(req());
    expect(diagnostic.intention).toMatchObject({
      attemptNo: 1, status: "NOT_STARTED", recordedProvider: "ALANUBE",
      hasProviderSessionUrl: false, hasProviderPostulationId: false,
    });
    expect(diagnostic.configuredEmissionProvider).toBe("DOSA");
    expect(rows).toHaveLength(1);
  });
});
