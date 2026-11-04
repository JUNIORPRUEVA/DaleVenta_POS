import { ConflictException, ForbiddenException } from "@nestjs/common";
import { PERMISSIONS_KEY } from "../../../auth/roles.decorator";
import type { TenantUser } from "../../../auth/tenant-context";
import type { PrismaService } from "../../../prisma/prisma.service";
import { DosaCertificationIntentController, type ReconcileDosaIntentDto } from "./dosa-certification-intent.controller";
import { effectiveIntentProvider } from "./dosa-intent-attribution";
import type { DosaCertificationIntentService } from "./dosa-certification-intent.service";
import type { DosaCredentialService } from "./dosa-credential.service";

const COMPANY = "21212121-0000-4000-8000-000000000021";
const OTHER = "31313131-0000-4000-8000-000000000031";
const INTENT = "41414141-0000-4000-8000-000000000041";
const AUDIT = "51515151-0000-4000-8000-000000000051";
const createdAt = new Date("2026-11-01T00:00:00Z");

function fixture(overrides: { sourceCreated?: boolean; externalActivity?: boolean;
  sessionUrl?: string; owner?: string } = {}) {
  const original = { id: AUDIT, companyId: COMPANY, targetId: INTENT,
    action: "ONBOARDING_STARTED", actorUserId: "admin-1", createdAt,
    metadata: { provider: "ALANUBE", created: overrides.sourceCreated ?? true,
      rnc: "133306001", attemptNo: 1 }, before: null, after: null };
  const audits: Array<Record<string, unknown>> = [original];
  const intent = { id: INTENT, companyId: COMPANY, rnc: "133306001", attemptNo: 1,
    status: "NOT_STARTED", sessionUrl: overrides.sessionUrl ?? null,
    providerPostulationId: null, lastEventType: null, providerConfirmedAt: null,
    closedAt: null, createdAt, createdByUserId: "admin-1" };
  const prisma: any = {
    ecfDosaCertificationSession: { findFirst: async ({ where }: any) =>
      where.companyId === COMPANY && (!where.id || where.id === INTENT) ? intent : null },
    ecfAuditLog: {
      findMany: async ({ where }: any) => audits.filter((entry) =>
        entry.companyId === where.companyId && entry.targetId === where.targetId),
      create: async ({ data }: any) => {
        if (audits.some((entry) => entry.action === "INTENT_PROVIDER_RECONCILED"))
          throw new Error("unique reconciliation");
        audits.push({ id: "audit-2", createdAt: new Date(), ...data });
      },
    },
    ecfCertificationAttempt: { count: async () => overrides.externalActivity ? 1 : 0 },
    ecfDosaWebhookEvent: { count: async () => 0 },
    ecfCertificationPortalTicket: { count: async () => 0 },
    ecfCertificationPortalSession: { count: async () => 0 },
    $transaction: async (callback: (tx: unknown) => Promise<unknown>) => callback(prisma),
  };
  const controller = new DosaCertificationIntentController(prisma as PrismaService,
    {} as DosaCertificationIntentService, {} as DosaCredentialService,
    { read: async () => null });
  const user = { id: "admin-2", companyId: overrides.owner ?? COMPANY,
    role: "ADMIN" } as TenantUser;
  const request = { user } as any;
  const body = { intentId: INTENT, sourceAuditId: AUDIT,
    externalReviewReference: "provider-review-123",
    ownerApprovalReference: "owner-approval-123",
    reason: "Revisión documentada: intención local sin actividad externa confirmada.",
    confirmation: "RECONCILE_EXISTING_DOSA_INTENT" } as ReconcileDosaIntentDto;
  return { controller, prisma, audits, intent, request, body };
}

describe("DOSA intent provider reconciliation", () => {
  const oldSwitch = process.env.ECF_DOSA_INTENT_RECONCILIATION_ENABLED;
  const oldPilot = process.env.ECF_PORTAL_PILOT_COMPANY_IDS;
  beforeEach(() => {
    process.env.ECF_DOSA_INTENT_RECONCILIATION_ENABLED = "true";
    process.env.ECF_PORTAL_PILOT_COMPANY_IDS = COMPANY;
  });
  afterAll(() => {
    if (oldSwitch === undefined) delete process.env.ECF_DOSA_INTENT_RECONCILIATION_ENABLED;
    else process.env.ECF_DOSA_INTENT_RECONCILIATION_ENABLED = oldSwitch;
    if (oldPilot === undefined) delete process.env.ECF_PORTAL_PILOT_COMPANY_IDS;
    else process.env.ECF_PORTAL_PILOT_COMPANY_IDS = oldPilot;
  });

  it("requires the existing onboarding permission and an administrator", async () => {
    expect(Reflect.getMetadata(PERMISSIONS_KEY,
      DosaCertificationIntentController.prototype.reconcileProvider))
      .toEqual(["manageEcfOnboarding"]);
    const f = fixture();
    f.request.user.role = "ASISTENTE";
    await expect(f.controller.reconcileProvider(f.request, f.body))
      .rejects.toBeInstanceOf(ForbiddenException);
    expect(f.audits).toHaveLength(1);
  });

  it("fails closed when owner-controlled enablement is absent", async () => {
    process.env.ECF_DOSA_INTENT_RECONCILIATION_ENABLED = "false";
    const f = fixture();
    await expect(f.controller.reconcileProvider(f.request, f.body))
      .rejects.toThrow("DOSA_INTENT_RECONCILIATION_DISABLED");
    expect(f.audits).toHaveLength(1);
  });

  it("retains original ALANUBE audit and records evidence, actor and reason", async () => {
    const f = fixture();
    const result = await f.controller.reconcileProvider(f.request, f.body);
    expect(result).toMatchObject({ attemptNo: 1, historicalProvider: "ALANUBE",
      effectiveProvider: "DOSA", fiscalAuthorizationGranted: false });
    expect(f.audits).toHaveLength(2);
    expect(f.audits[0].metadata).toMatchObject({ provider: "ALANUBE" });
    expect(f.audits[1]).toMatchObject({ actorUserId: "admin-2",
      action: "INTENT_PROVIDER_RECONCILED", before: { provider: "ALANUBE" },
      after: { provider: "DOSA" }, metadata: {
        sourceAuditId: AUDIT, externalReviewReference: f.body.externalReviewReference,
        ownerApprovalReference: f.body.ownerApprovalReference, reason: f.body.reason } });
    expect(f.audits[1].createdAt).toBeInstanceOf(Date);
    expect(effectiveIntentProvider(f.audits as any)).toBe("DOSA");
    expect(f.intent.status).toBe("NOT_STARTED");
    expect(f.intent.sessionUrl).toBeNull();
  });

  it("rejects insufficient origin or external evidence without writing", async () => {
    for (const f of [fixture({ sourceCreated: false }),
      fixture({ externalActivity: true }), fixture({ sessionUrl: "https://example.test" })]) {
      await expect(f.controller.reconcileProvider(f.request, f.body))
        .rejects.toBeInstanceOf(ConflictException);
      expect(f.audits).toHaveLength(1);
    }
    const f = fixture();
    f.body.externalReviewReference = "";
    await expect(f.controller.reconcileProvider(f.request, f.body)).rejects.toThrow();
    expect(f.audits).toHaveLength(1);
    f.body.externalReviewReference = "provider-review-123";
    f.body.ownerApprovalReference = "";
    await expect(f.controller.reconcileProvider(f.request, f.body)).rejects.toThrow();
    expect(f.audits).toHaveLength(1);
  });

  it("does not create a second attempt and rejects replay", async () => {
    const f = fixture();
    await f.controller.reconcileProvider(f.request, f.body);
    await expect(f.controller.reconcileProvider(f.request, f.body))
      .rejects.toBeInstanceOf(ConflictException);
    expect(f.audits).toHaveLength(2);
  });

  it("rejects another tenant before any write", async () => {
    process.env.ECF_PORTAL_PILOT_COMPANY_IDS = `${COMPANY},${OTHER}`;
    const f = fixture({ owner: OTHER });
    await expect(f.controller.reconcileProvider(f.request, f.body))
      .rejects.toThrow("DOSA_INTENT_NOT_FOUND");
    expect(f.audits).toHaveLength(1);
  });
});
