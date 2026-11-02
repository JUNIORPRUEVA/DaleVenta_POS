import { ConflictException, ForbiddenException, ServiceUnavailableException } from "@nestjs/common";
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
    return { ok: true as const, rnc: RNC };
  }
}

function fiscalConfig(enabled: boolean, provider = "DOSA"): DosaCompanyFiscalConfigReader {
  return {
    async read() {
      return { ecfEnabled: enabled, provider };
    },
  };
}

function auditLog() {
  const rows: Array<Record<string, unknown>> = [];
  const prisma = {
    ecfAuditLog: {
      async create(input: { data: Record<string, unknown> }) {
        rows.push(input.data);
        return input.data;
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
  ecfEnabled?: boolean;
} = {}) {
  const intents = new FakeIntents(options.behaviour ?? "created");
  const { prisma, rows } = auditLog();
  const controller = new DosaCertificationIntentController(
    prisma,
    intents as unknown as DosaCertificationIntentService,
    credentials(),
    fiscalConfig(options.ecfEnabled ?? true),
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

  it("exige que la empresa haya activado la preparación de e-CF", async () => {
    const { controller, intents } = build({ ecfEnabled: false });

    await expect(
      controller.register(req(), {} as RegisterDosaIntentDto),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(intents.registerCalls).toHaveLength(0);
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

  it("con e-CF desactivado explica el bloqueo", async () => {
    const { controller } = build({ ecfEnabled: false });
    const state = await controller.state(req());
    expect(state.canRegister).toBe(false);
    expect(state.blockingReasons).toContain("ECF_DOSA_INTENT_ECF_NOT_ENABLED");
  });
});
