import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
} from "@nestjs/common";
import type { Request } from "express";

import type { DosaCompanyFiscalConfigReader } from "./dosa-emission.service";
import type { DosaCertificationIntentService } from "./dosa-certification-intent.service";
import {
  AuthorizeHistoricalTransitionDto,
  DosaCertificationIntentController,
} from "./dosa-certification-intent.controller";
import type { PrismaService } from "../../../prisma/prisma.service";
import type { TenantUser } from "../../../auth/tenant-context";

const COMPANY = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const INTENT = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

function user(role: string = "ADMIN"): TenantUser {
  return { id: "user-1", companyId: COMPANY, role } as TenantUser;
}

function req(as: TenantUser = user()): Request {
  return { user: as } as unknown as Request;
}

function dto(
  overrides: Partial<AuthorizeHistoricalTransitionDto> = {},
): AuthorizeHistoricalTransitionDto {
  return {
    intentId: INTENT,
    ownerApprovalReference: "ACTA-2026-001",
    reason: "Revisión del expediente reconciliado antes de continuar.",
    confirmation: "AUTHORIZE_HISTORICAL_TRANSITION",
    ...overrides,
  };
}

function fixture(options: {
  intent?: Record<string, unknown> | null;
  reconciled?: boolean;
  alreadyAuthorized?: boolean;
} = {}) {
  const intent = options.intent === undefined
    ? {
        id: INTENT,
        rnc: "101000001",
        attemptNo: 1,
        status: "NOT_STARTED",
        activeKey: `${COMPANY}:101000001`,
        sessionUrl: null,
        providerPostulationId: null,
        lastEventType: null,
        providerConfirmedAt: null,
        closedAt: null,
      }
    : options.intent;
  const created = { id: "audit-auth-1", createdAt: new Date("2026-11-04T20:00:00Z") };
  const tx = {
    ecfDosaCertificationSession: {
      findFirst: jest.fn().mockResolvedValue(intent),
    },
    ecfAuditLog: {
      findFirst: jest.fn().mockImplementation(({ where }: { where: { action: string } }) => {
        if (where.action === "INTENT_PROVIDER_RECONCILED") {
          return options.reconciled === false ? null : { id: "audit-reconciled" };
        }
        return options.alreadyAuthorized ? { id: "audit-existing" } : null;
      }),
      create: jest.fn().mockResolvedValue(created),
    },
  };
  const prisma = {
    $transaction: jest.fn((callback: (client: typeof tx) => unknown) =>
      callback(tx),
    ),
  } as unknown as PrismaService;
  const controller = new DosaCertificationIntentController(
    prisma,
    {} as DosaCertificationIntentService,
    {} as never,
    { read: async () => null } as DosaCompanyFiscalConfigReader,
  );
  return { controller, tx };
}

describe("POST /ecf/dosa/certification-intent/authorize-historical-transition", () => {
  const previousFlag = process.env.ECF_DOSA_HISTORICAL_TRANSITION_ENABLED;
  const previousPilot = process.env.ECF_PORTAL_PILOT_COMPANY_IDS;

  beforeEach(() => {
    process.env.ECF_DOSA_HISTORICAL_TRANSITION_ENABLED = "true";
    process.env.ECF_PORTAL_PILOT_COMPANY_IDS = COMPANY;
  });

  afterEach(() => {
    if (previousFlag === undefined) delete process.env.ECF_DOSA_HISTORICAL_TRANSITION_ENABLED;
    else process.env.ECF_DOSA_HISTORICAL_TRANSITION_ENABLED = previousFlag;
    if (previousPilot === undefined) delete process.env.ECF_PORTAL_PILOT_COMPANY_IDS;
    else process.env.ECF_PORTAL_PILOT_COMPANY_IDS = previousPilot;
  });

  it("registra una autorización auditable sin tocar la fila del intento", async () => {
    const { controller, tx } = fixture();

    const result = await controller.authorizeHistoricalTransition(req(), dto());

    expect(result).toMatchObject({
      ok: true,
      companyId: COMPANY,
      intentId: INTENT,
      attemptNo: 1,
      ttlHours: 24,
      fiscalAuthorizationGranted: false,
    });
    expect(tx.ecfAuditLog.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          action: "INTENT_HISTORICAL_TRANSITION_AUTHORIZED",
          targetId: INTENT,
          companyId: COMPANY,
        }),
      }),
    );
    // No existe ninguna escritura sobre la sesión: solo se crea auditoría.
    expect(tx.ecfDosaCertificationSession).not.toHaveProperty("update");
  });

  it("exige la bandera específica", async () => {
    delete process.env.ECF_DOSA_HISTORICAL_TRANSITION_ENABLED;
    const { controller } = fixture();

    await expect(
      controller.authorizeHistoricalTransition(req(), dto()),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it("exige administrador", async () => {
    const { controller } = fixture();

    await expect(
      controller.authorizeHistoricalTransition(req(user("VENDEDOR")), dto()),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it("exige confirmación explícita", async () => {
    const { controller } = fixture();

    await expect(
      controller.authorizeHistoricalTransition(
        req(),
        dto({ confirmation: "OTRA_COSA" }),
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it("rechaza un intento que no está en el estado seguro", async () => {
    const { controller } = fixture({
      intent: {
        id: INTENT,
        rnc: "101000001",
        attemptNo: 1,
        status: "RUNNING",
        activeKey: `${COMPANY}:101000001`,
        sessionUrl: "https://dosasystem.com/sesion/abc",
        providerPostulationId: "post-1",
        lastEventType: null,
        providerConfirmedAt: null,
        closedAt: null,
      },
    });

    await expect(
      controller.authorizeHistoricalTransition(req(), dto()),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it("rechaza un expediente sin reconciliación", async () => {
    const { controller } = fixture({ reconciled: false });

    await expect(
      controller.authorizeHistoricalTransition(req(), dto()),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it("rechaza una segunda autorización vigente", async () => {
    const { controller } = fixture({ alreadyAuthorized: true });

    await expect(
      controller.authorizeHistoricalTransition(req(), dto()),
    ).rejects.toBeInstanceOf(ConflictException);
  });
});
