import { BadRequestException, ConflictException, ForbiddenException } from "@nestjs/common";
import type { TenantUser } from "../../../auth/tenant-context";
import type { PrismaService } from "../../../prisma/prisma.service";
import {
  DosaCertificationIntentController,
  type ReconcileDosaIntentDto,
} from "./dosa-certification-intent.controller";
import {
  effectiveIntentProvider,
  intentReconciliationKind,
} from "./dosa-intent-attribution";
import { internalEvidenceDigest } from "./dosa-internal-review-evidence";
import type { DosaCertificationIntentService } from "./dosa-certification-intent.service";
import type { DosaCredentialService } from "./dosa-credential.service";

/**
 * Reconciliación EXCEPCIONAL por revisión interna.
 *
 * Todo el material es sintético: no se usa ningún dato real ni se ejecuta nada
 * contra producción. Lo que se demuestra aquí es que la excepción queda
 * limitada al caso exacto y que falla cerrada en todo lo demás.
 */

const COMPANY = "21212121-0000-4000-8000-0000000000a1";
const OTHER_COMPANY = "31313131-0000-4000-8000-0000000000b1";
const INTENT = "41414141-0000-4000-8000-0000000000c1";
const OTHER_INTENT = "42424242-0000-4000-8000-0000000000c2";
const AUDIT = "51515151-0000-4000-8000-0000000000d1";
const CREATED_AT = new Date("2026-11-04T01:33:58.668Z");

type FixtureOptions = {
  attemptNo?: number;
  status?: string;
  sessionUrl?: string | null;
  providerPostulationId?: string | null;
  lastEventType?: string | null;
  providerConfirmedAt?: Date | null;
  closedAt?: Date | null;
  sourceCreated?: boolean;
  sourceProvider?: string;
  auditCount?: number;
  originalActor?: string;
  legacyActivity?: number;
  webhookActivity?: number;
  latestIsOtherIntent?: boolean;
};

function fixture(options: FixtureOptions = {}) {
  const auditRows: Array<Record<string, any>> = [
    {
      id: AUDIT,
      companyId: COMPANY,
      targetId: INTENT,
      action: "ONBOARDING_STARTED",
      actorUserId: options.originalActor ?? "admin-1",
      createdAt: CREATED_AT,
      metadata: {
        provider: options.sourceProvider ?? "ALANUBE",
        created: options.sourceCreated ?? true,
        rnc: "133080206",
        attemptNo: 1,
      },
      before: null,
      after: null,
    },
  ];
  for (let extra = 1; extra < (options.auditCount ?? 1); extra += 1) {
    auditRows.push({
      id: `${AUDIT}-${extra}`,
      companyId: COMPANY,
      targetId: INTENT,
      action: "ONBOARDING_STARTED",
      actorUserId: "admin-1",
      createdAt: new Date(CREATED_AT.getTime() + extra * 1000),
      metadata: { provider: "ALANUBE", created: false, rnc: "133080206", attemptNo: 1 },
      before: null,
      after: null,
    });
  }

  const intent = {
    id: INTENT,
    companyId: COMPANY,
    rnc: "133080206",
    attemptNo: options.attemptNo ?? 1,
    status: options.status ?? "NOT_STARTED",
    sessionUrl: options.sessionUrl ?? null,
    providerPostulationId: options.providerPostulationId ?? null,
    lastEventType: options.lastEventType ?? null,
    providerConfirmedAt: options.providerConfirmedAt ?? null,
    closedAt: options.closedAt ?? null,
    createdAt: CREATED_AT,
    createdByUserId: "admin-1",
  };

  let sessionQueries = 0;
  const prisma: any = {
    ecfDosaCertificationSession: {
      findFirst: async ({ where }: any) => {
        sessionQueries += 1;
        if (where.companyId !== COMPANY) return null;
        if (where.id) return where.id === INTENT ? intent : null;
        // Consulta del "último intento" (sin id).
        return options.latestIsOtherIntent ? { id: OTHER_INTENT } : intent;
      },
    },
    ecfAuditLog: {
      findMany: async ({ where }: any) =>
        auditRows.filter(
          (entry) => entry.companyId === where.companyId && entry.targetId === where.targetId,
        ),
      create: async ({ data }: any) => {
        if (auditRows.some((entry) => entry.action === "INTENT_PROVIDER_RECONCILED")) {
          throw new Error("unique reconciliation");
        }
        auditRows.push({ id: "audit-reconciliation", createdAt: new Date(), ...data });
      },
    },
    ecfCertificationAttempt: { count: async () => options.legacyActivity ?? 0 },
    ecfDosaWebhookEvent: { count: async () => options.webhookActivity ?? 0 },
    ecfCertificationPortalTicket: { count: async () => 0 },
    ecfCertificationPortalSession: { count: async () => 0 },
    $transaction: async (callback: (tx: unknown) => Promise<unknown>) => callback(prisma),
  };

  const controller = new DosaCertificationIntentController(
    prisma as PrismaService,
    {} as DosaCertificationIntentService,
    {} as DosaCredentialService,
    { read: async () => ({ provider: "ALANUBE", ecfEnabled: true }) } as any,
  );

  const user = { id: "admin-2", companyId: COMPANY, role: "ADMIN" } as TenantUser;
  const request = { user } as any;
  const body = {
    intentId: INTENT,
    sourceAuditId: AUDIT,
    reviewKind: "INTERNAL",
    internalReviewReference: "internal-audit-2026-11-04-001",
    ownerApprovalReference: "owner-approval-2026-11-04",
    reason:
      "Revisión interna del intento local: sin referencias de proveedor ni actividad externa registrada.",
    confirmation: "RECONCILE_EXISTING_DOSA_INTENT",
  } as ReconcileDosaIntentDto;

  return { controller, prisma, auditRows, intent, request, body, getSessionQueries: () => sessionQueries };
}

describe("reconciliación interna — camino favorable", () => {
  const previous = {
    master: process.env.ECF_DOSA_INTENT_RECONCILIATION_ENABLED,
    internal: process.env.ECF_DOSA_INTENT_RECONCILIATION_INTERNAL_ENABLED,
    pilot: process.env.ECF_PORTAL_PILOT_COMPANY_IDS,
  };
  beforeEach(() => {
    process.env.ECF_DOSA_INTENT_RECONCILIATION_ENABLED = "true";
    process.env.ECF_DOSA_INTENT_RECONCILIATION_INTERNAL_ENABLED = "true";
    process.env.ECF_PORTAL_PILOT_COMPANY_IDS = COMPANY;
  });
  afterAll(() => {
    const restore = (key: string, value: string | undefined) => {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    };
    restore("ECF_DOSA_INTENT_RECONCILIATION_ENABLED", previous.master);
    restore("ECF_DOSA_INTENT_RECONCILIATION_INTERNAL_ENABLED", previous.internal);
    restore("ECF_PORTAL_PILOT_COMPANY_IDS", previous.pilot);
  });

  it("registra la decisión interna con snapshot, digest y actor", async () => {
    const f = fixture();
    const result = await f.controller.reconcileProvider(f.request, f.body);

    expect(result).toMatchObject({
      attemptNo: 1,
      historicalProvider: "ALANUBE",
      effectiveProvider: "DOSA",
      reviewKind: "INTERNAL",
      fiscalAuthorizationGranted: false,
    });
    expect(f.auditRows).toHaveLength(2);
    const reconciliation = f.auditRows[1];
    expect(reconciliation.actorUserId).toBe("admin-2");
    expect(reconciliation.before).toEqual({ provider: "ALANUBE" });
    expect(reconciliation.after).toEqual({ provider: "DOSA" });
    expect(reconciliation.metadata).toMatchObject({
      reviewKind: "INTERNAL",
      sourceAuditId: AUDIT,
      internalReviewReference: f.body.internalReviewReference,
      ownerApprovalReference: f.body.ownerApprovalReference,
      reason: f.body.reason,
    });
    expect(reconciliation.metadata.externalReviewReference).toBeUndefined();
    expect(reconciliation.metadata.internalEvidenceDigest).toMatch(/^[0-9a-f]{64}$/);
    expect(reconciliation.metadata.evidenceSnapshot).toMatchObject({
      schema: "fullpos.dosa.internal-review.v1",
      activity: {
        legacyProviderAttempts: 0,
        webhookEvents: 0,
        portalTickets: 0,
        portalSessions: 0,
      },
    });
  });

  it("la auditoría original ALANUBE queda intacta", async () => {
    const f = fixture();
    const before = { ...f.auditRows[0], metadata: { ...f.auditRows[0].metadata } };
    await f.controller.reconcileProvider(f.request, f.body);
    expect(f.auditRows[0]).toEqual(before);
    expect(f.auditRows[0].metadata).toMatchObject({ provider: "ALANUBE", created: true });
  });

  it("historical sigue siendo ALANUBE y la atribución efectiva es DOSA", async () => {
    const f = fixture();
    await f.controller.reconcileProvider(f.request, f.body);
    expect(effectiveIntentProvider(f.auditRows as any)).toBe("DOSA");
    expect(intentReconciliationKind(f.auditRows as any)).toBe("INTERNAL");
  });

  it("el digest es reproducible desde el snapshot guardado", async () => {
    const f = fixture();
    await f.controller.reconcileProvider(f.request, f.body);
    const metadata = f.auditRows[1].metadata;
    expect(internalEvidenceDigest(metadata.evidenceSnapshot)).toBe(
      metadata.internalEvidenceDigest,
    );
  });

  it("no crea un segundo intento ni reescribe el existente", async () => {
    const f = fixture();
    const snapshotBefore = { ...f.intent };
    await f.controller.reconcileProvider(f.request, f.body);
    expect(f.intent).toEqual(snapshotBefore);
  });

  it("rechaza la repetición (idempotencia del índice único)", async () => {
    const f = fixture();
    await f.controller.reconcileProvider(f.request, f.body);
    await expect(
      f.controller.reconcileProvider(f.request, f.body),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(f.auditRows).toHaveLength(2);
  });

  it("la emisión fiscal permanece cerrada", async () => {
    const f = fixture();
    const result = await f.controller.reconcileProvider(f.request, f.body);
    expect(result.fiscalAuthorizationGranted).toBe(false);
  });

  it("el diagnóstico declara la revisión interna y conserva el histórico", async () => {
    const f = fixture();
    await f.controller.reconcileProvider(f.request, f.body);
    const diagnostic = await f.controller.diagnostic(f.request);

    expect(diagnostic.intention?.reconciliationKind).toBe("INTERNAL");
    expect(diagnostic.intention?.recordedProvider).toBe("ALANUBE");
    expect(diagnostic.intention?.effectiveProvider).toBe("DOSA");
    // Sin datos del proveedor no hay nada que revisar.
    expect(diagnostic.intention?.attributionConflict).toBe(false);
    expect(diagnostic.intention?.hasProviderPostulationId).toBe(false);
  });

  it("marca conflicto si aparece un dato del proveedor tras la reconciliación", async () => {
    const f = fixture();
    await f.controller.reconcileProvider(f.request, f.body);
    // Evento tardío: llega un identificador de proveedor DESPUÉS de decidir.
    f.intent.providerPostulationId = "postulacion-tardia";

    const diagnostic = await f.controller.diagnostic(f.request);

    // No se cambia la atribución sola: se expone para revisión humana.
    expect(diagnostic.intention?.attributionConflict).toBe(true);
    expect(diagnostic.intention?.effectiveProvider).toBe("DOSA");
    expect(effectiveIntentProvider(f.auditRows as any)).toBe("DOSA");
  });
});

describe("reconciliación interna — banderas", () => {
  const previousMaster = process.env.ECF_DOSA_INTENT_RECONCILIATION_ENABLED;
  const previousInternal = process.env.ECF_DOSA_INTENT_RECONCILIATION_INTERNAL_ENABLED;
  const previousPilot = process.env.ECF_PORTAL_PILOT_COMPANY_IDS;
  beforeEach(() => {
    process.env.ECF_PORTAL_PILOT_COMPANY_IDS = COMPANY;
    process.env.ECF_DOSA_INTENT_RECONCILIATION_ENABLED = "true";
    process.env.ECF_DOSA_INTENT_RECONCILIATION_INTERNAL_ENABLED = "true";
  });
  afterAll(() => {
    const restore = (key: string, value: string | undefined) => {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    };
    restore("ECF_DOSA_INTENT_RECONCILIATION_ENABLED", previousMaster);
    restore("ECF_DOSA_INTENT_RECONCILIATION_INTERNAL_ENABLED", previousInternal);
    restore("ECF_PORTAL_PILOT_COMPANY_IDS", previousPilot);
  });

  it("sin la bandera interna, la maestra no basta", async () => {
    delete process.env.ECF_DOSA_INTENT_RECONCILIATION_INTERNAL_ENABLED;
    const f = fixture();
    await expect(f.controller.reconcileProvider(f.request, f.body)).rejects.toThrow(
      "DOSA_INTENT_RECONCILIATION_INTERNAL_DISABLED",
    );
    expect(f.auditRows).toHaveLength(1);
  });

  it("con la interna encendida pero la maestra apagada, no hay escritura", async () => {
    process.env.ECF_DOSA_INTENT_RECONCILIATION_ENABLED = "false";
    const f = fixture();
    await expect(f.controller.reconcileProvider(f.request, f.body)).rejects.toThrow(
      "DOSA_INTENT_RECONCILIATION_DISABLED",
    );
    expect(f.auditRows).toHaveLength(1);
  });

  it("la EXTERNAL sigue funcionando sin la bandera interna", async () => {
    delete process.env.ECF_DOSA_INTENT_RECONCILIATION_INTERNAL_ENABLED;
    const f = fixture();
    const body: ReconcileDosaIntentDto = {
      intentId: INTENT,
      sourceAuditId: AUDIT,
      externalReviewReference: "provider-review-2026-11-04",
      ownerApprovalReference: "owner-approval-2026-11-04",
      reason:
        "Revisión documentada del proveedor: no existe postulación para este RNC.",
      confirmation: "RECONCILE_EXISTING_DOSA_INTENT",
    };
    const result = await f.controller.reconcileProvider(f.request, body);
    expect(result).toMatchObject({ reviewKind: "EXTERNAL", effectiveProvider: "DOSA" });
    expect(f.auditRows[1].metadata).toMatchObject({ reviewKind: "EXTERNAL" });
    expect(effectiveIntentProvider(f.auditRows as any)).toBe("DOSA");
    expect(intentReconciliationKind(f.auditRows as any)).toBe("EXTERNAL");
  });

  it("un registro EXTERNAL anterior (sin reviewKind) sigue siendo válido", () => {
    const legacy = [
      fixture().auditRows[0],
      {
        id: "legacy",
        action: "INTENT_PROVIDER_RECONCILED",
        actorUserId: "admin-2",
        before: { provider: "ALANUBE" },
        after: { provider: "DOSA" },
        metadata: {
          sourceAuditId: AUDIT,
          externalReviewReference: "provider-review-legacy",
          ownerApprovalReference: "owner-approval-legacy",
          reason: "Registro anterior a la excepción interna.",
        },
      },
    ];
    expect(effectiveIntentProvider(legacy as any)).toBe("DOSA");
    expect(intentReconciliationKind(legacy as any)).toBe("EXTERNAL");
  });
});

describe("reconciliación interna — rechazos", () => {
  const previousMaster = process.env.ECF_DOSA_INTENT_RECONCILIATION_ENABLED;
  const previousInternal = process.env.ECF_DOSA_INTENT_RECONCILIATION_INTERNAL_ENABLED;
  const previousPilot = process.env.ECF_PORTAL_PILOT_COMPANY_IDS;
  beforeEach(() => {
    process.env.ECF_DOSA_INTENT_RECONCILIATION_ENABLED = "true";
    process.env.ECF_DOSA_INTENT_RECONCILIATION_INTERNAL_ENABLED = "true";
    process.env.ECF_PORTAL_PILOT_COMPANY_IDS = COMPANY;
  });
  afterAll(() => {
    const restore = (key: string, value: string | undefined) => {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    };
    restore("ECF_DOSA_INTENT_RECONCILIATION_ENABLED", previousMaster);
    restore("ECF_DOSA_INTENT_RECONCILIATION_INTERNAL_ENABLED", previousInternal);
    restore("ECF_PORTAL_PILOT_COMPANY_IDS", previousPilot);
  });

  it("exige referencias del tipo declarado y rechaza las cruzadas", async () => {
    const cases: Array<[ReconcileDosaIntentDto, string]> = [
      [
        { ...fixture().body, internalReviewReference: undefined } as ReconcileDosaIntentDto,
        "DOSA_INTENT_INTERNAL_REVIEW_REFERENCE_REQUIRED",
      ],
      [
        { ...fixture().body, internalReviewReference: "corto" } as ReconcileDosaIntentDto,
        "DOSA_INTENT_INTERNAL_REVIEW_REFERENCE_REQUIRED",
      ],
      [
        {
          ...fixture().body,
          externalReviewReference: "provider-review-123",
        } as ReconcileDosaIntentDto,
        "DOSA_INTENT_REVIEW_REFERENCES_CONFLICT",
      ],
      [
        {
          intentId: INTENT,
          sourceAuditId: AUDIT,
          reviewKind: "EXTERNAL",
          internalReviewReference: "internal-audit-2026-11-04",
          ownerApprovalReference: "owner-approval-2026-11-04",
          reason: "Revisión documentada del intento local sin actividad externa.",
          confirmation: "RECONCILE_EXISTING_DOSA_INTENT",
        } as ReconcileDosaIntentDto,
        "DOSA_INTENT_EXTERNAL_REVIEW_REFERENCE_REQUIRED",
      ],
    ];
    for (const [body, code] of cases) {
      const f = fixture();
      await expect(f.controller.reconcileProvider(f.request, body)).rejects.toThrow(code);
      expect(f.auditRows).toHaveLength(1);
    }
  });

  it("exige la aprobación del propietario", async () => {
    const f = fixture();
    f.body.ownerApprovalReference = "   ";
    await expect(f.controller.reconcileProvider(f.request, f.body)).rejects.toBeInstanceOf(
      BadRequestException,
    );
    expect(f.auditRows).toHaveLength(1);
  });

  it("rechaza cualquier actividad externa registrada", async () => {
    for (const activity of [
      { legacyActivity: 1 },
      { webhookActivity: 1 },
      { sessionUrl: "https://dosasystem.test/sesion/abc" },
      { providerPostulationId: "postulacion-1" },
      { lastEventType: "certificacion_iniciada" },
      { providerConfirmedAt: new Date() },
      { closedAt: new Date() },
    ] as FixtureOptions[]) {
      const f = fixture(activity);
      await expect(f.controller.reconcileProvider(f.request, f.body)).rejects.toBeInstanceOf(
        ConflictException,
      );
      expect(f.auditRows).toHaveLength(1);
    }
  });

  it("solo acepta el primer intento y el último del expediente", async () => {
    for (const options of [
      { attemptNo: 2 },
      { status: "IN_PROGRESS" },
      { latestIsOtherIntent: true },
    ] as FixtureOptions[]) {
      const f = fixture(options);
      await expect(f.controller.reconcileProvider(f.request, f.body)).rejects.toBeInstanceOf(
        ConflictException,
      );
      expect(f.auditRows).toHaveLength(1);
    }
  });

  it("rechaza un histórico inconsistente (origen o actor)", async () => {
    for (const options of [
      { sourceCreated: false },
      { sourceProvider: "DOSA" },
      { originalActor: "otro-usuario" },
      { auditCount: 2 },
    ] as FixtureOptions[]) {
      const f = fixture(options);
      const initial = f.auditRows.length;
      await expect(f.controller.reconcileProvider(f.request, f.body)).rejects.toBeInstanceOf(
        ConflictException,
      );
      expect(f.auditRows).toHaveLength(initial);
    }
  });

  it("rechaza empresas fuera del piloto y ajenas", async () => {
    const originalPilot = process.env.ECF_PORTAL_PILOT_COMPANY_IDS;

    const nonPilot = fixture();
    process.env.ECF_PORTAL_PILOT_COMPANY_IDS = OTHER_COMPANY;
    await expect(
      nonPilot.controller.reconcileProvider(nonPilot.request, nonPilot.body),
    ).rejects.toBeInstanceOf(ForbiddenException);

    // Con ambas empresas en el piloto, la empresa ajena no encuentra su intento:
    // el aislamiento por `companyId` la detiene antes de cualquier escritura.
    process.env.ECF_PORTAL_PILOT_COMPANY_IDS = `${COMPANY},${OTHER_COMPANY}`;
    const foreign = fixture();
    foreign.request.user = {
      id: "admin-2",
      companyId: OTHER_COMPANY,
      role: "ADMIN",
    } as TenantUser;
    await expect(
      foreign.controller.reconcileProvider(foreign.request, foreign.body),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(foreign.auditRows).toHaveLength(1);

    process.env.ECF_PORTAL_PILOT_COMPANY_IDS = originalPilot;
  });

  it("exige rol administrador", async () => {
    const f = fixture();
    f.request.user.role = "CAJERO";
    await expect(f.controller.reconcileProvider(f.request, f.body)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
    expect(f.auditRows).toHaveLength(1);
  });
});

describe("atribución: no se acepta un hash correcto pero inconsistente", () => {
  function reconciliation(snapshot: Record<string, unknown>, digest?: string) {
    return [
      {
        id: AUDIT,
        action: "ONBOARDING_STARTED",
        actorUserId: "admin-1",
        metadata: { provider: "ALANUBE", created: true, rnc: "133080206", attemptNo: 1 },
      },
      {
        id: "reconciliacion",
        action: "INTENT_PROVIDER_RECONCILED",
        actorUserId: "admin-2",
        before: { provider: "ALANUBE" },
        after: { provider: "DOSA" },
        metadata: {
          sourceAuditId: AUDIT,
          reviewKind: "INTERNAL",
          internalReviewReference: "internal-audit-2026-11-04",
          ownerApprovalReference: "owner-approval-2026-11-04",
          reason: "Revisión interna documentada del intento local sin actividad externa.",
          internalEvidenceDigest: digest ?? internalEvidenceDigest(snapshot as any),
          evidenceSnapshot: snapshot,
        },
      },
    ];
  }

  const validSnapshot = {
    schema: "fullpos.dosa.internal-review.v1",
    intent: {
      id: INTENT,
      companyId: COMPANY,
      rnc: "133080206",
      attemptNo: 1,
      status: "NOT_STARTED",
      createdAt: CREATED_AT.toISOString(),
      createdByUserId: "admin-1",
      providerPostulationId: null,
      sessionUrl: null,
      lastEventType: null,
      providerConfirmedAt: null,
      closedAt: null,
    },
    audit: {
      total: 1,
      originalAuditId: AUDIT,
      originalActorUserId: "admin-1",
      originalProvider: "ALANUBE",
      originalCreated: true,
      originalRnc: "133080206",
      originalAttemptNo: 1,
    },
    activity: {
      legacyProviderAttempts: 0,
      webhookEvents: 0,
      portalTickets: 0,
      portalSessions: 0,
    },
  };

  it("acepta el snapshot consistente", () => {
    expect(effectiveIntentProvider(reconciliation(validSnapshot) as any)).toBe("DOSA");
  });

  it("rechaza un digest válido en formato pero que no corresponde al snapshot", () => {
    const forged = reconciliation(validSnapshot, "a".repeat(64));
    expect(effectiveIntentProvider(forged as any)).toBe("UNVERIFIED");
    expect(intentReconciliationKind(forged as any)).toBe("UNVERIFIED");
  });

  it("rechaza un snapshot manipulado aunque su digest se recalcule", () => {
    const tampered = {
      ...validSnapshot,
      activity: { ...validSnapshot.activity, legacyProviderAttempts: 1 },
    };
    const forged = reconciliation(tampered);
    expect(effectiveIntentProvider(forged as any)).toBe("UNVERIFIED");
  });

  it("rechaza la variante interna si arrastra una referencia externa", () => {
    const rows = reconciliation(validSnapshot);
    (rows[1].metadata as Record<string, unknown>).externalReviewReference =
      "provider-review-123";
    expect(effectiveIntentProvider(rows as any)).toBe("UNVERIFIED");
  });
});
