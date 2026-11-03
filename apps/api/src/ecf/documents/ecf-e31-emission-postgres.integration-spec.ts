import { randomUUID } from "node:crypto";
import { isEcfLocalTarget } from "../ecf-local-target";
import { PrismaService } from "../../prisma/prisma.service";
import type { TenantUser } from "../../auth/tenant-context";
import { validE31WithItbis } from "../fiscal-core/ecf-fixtures";
import { EcfEmissionService, type EcfEmissionWire, type EcfEmissionWireRequest } from "./ecf-emission.service";

// Opt-in suite. Runs ONLY against an authorized local target (historical UAT or
// the ephemeral test database) and uses simulated transport: no real Alanube call.
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

uat("E31 emission orchestrator (simulated transport)", () => {
  let prisma: PrismaService;
  let service: EcfEmissionService;
  const actor = randomUUID();
  let sequence = 0;
  const nextEncf = () => `E31${String(++sequence).padStart(10, "0")}`;

  beforeAll(async () => {
    if (!isEcfLocalTarget() || process.env.ALANUBE_ENABLE_REAL_CALLS !== "false" || process.env.ECF_EMISSION_ENABLED === "true") {
      throw new Error("E31_EMISSION_UAT_REFUSED");
    }
    prisma = new PrismaService();
    await prisma.$connect();
    service = new EcfEmissionService(prisma);
  });
  afterAll(async () => { await prisma?.$disconnect(); });

  async function tenant() {
    const companyId = randomUUID();
    await prisma.company.create({ data: { id: companyId, name: "Synthetic E31 emission", slug: `ecf-e31-${companyId}` } });
    return { companyId, user: { id: actor, role: "ADMIN", companyId } as TenantUser };
  }
  const metadata = (encf: string) => ({ encf, sequenceDueDate: "2026-12-31", incomeType: 1, paymentType: 1 } as const);
  function prepared(user: TenantUser, encf: string) {
    return service.prepare(user, { document: validE31WithItbis, metadata: metadata(encf), clientRequestId: randomUUID() });
  }
  function simulated(encf: string, options: { status?: number; body?: Record<string, unknown>; errorCode?: "TIMEOUT" | "NETWORK_ERROR" } = {}) {
    const calls: EcfEmissionWireRequest[] = [];
    const remoteId = "0" + randomUUID().replace(/-/g, "").slice(0, 25).toUpperCase();
    const port: EcfEmissionWire = { async execute(input) {
      calls.push(input);
      if (options.errorCode) return { ok: false, errorCode: options.errorCode, safeMessage: "synthetic" };
      return { ok: true, statusCode: options.status ?? 201, body: options.body ?? { id: remoteId, documentNumber: encf,
        companyIdentification: "101000001", status: "FINISHED", legalStatus: "ACCEPTED", sequenceConsumed: true } };
    } };
    return { port, calls, remoteId };
  }
  const stored = (companyId: string, id: string) =>
    prisma.ecfElectronicDocument.findFirstOrThrow({ where: { companyId, id } });
  const remoteId = () => "0" + randomUUID().replace(/-/g, "").slice(0, 25).toUpperCase();

  it("dispatches a valid E31 into human review, never fiscal acceptance", async () => {
    const { companyId, user } = await tenant();
    const encf = nextEncf();
    const document = await prepared(user, encf);
    expect(document).toMatchObject({ documentType: "E31", status: "LOCAL_VALIDATED" });
    const { port, calls, remoteId: remote } = simulated(encf);
    const outcome = await service.dispatchOnce(user, document.id, port);
    expect(outcome).toMatchObject({ correlated: true, documentType: "E31", sequenceConsumed: true, canRetryPost: false });
    expect(outcome.observation.providerOutcome).toBe("ACCEPTED");
    expect(calls).toHaveLength(1);
    expect(await stored(companyId, document.id)).toMatchObject({ status: "HUMAN_REVIEW_REQUIRED",
      externalProviderId: remote, externalDocumentNumber: encf, fiscalSnapshot: null });
    expect(await prisma.ecfEvidenceReceipt.count({ where: { companyId, documentId: document.id } })).toBe(1);
    expect(await prisma.ecfElectronicDocument.count({ where: { companyId, status: { in: ["DGII_ACCEPTED", "PROVIDER_ACCEPTED"] } } })).toBe(0);
  });

  it("records an explicit rejection for review without releasing the sequence", async () => {
    const { companyId, user } = await tenant();
    const encf = nextEncf();
    const document = await prepared(user, encf);
    const { port } = simulated(encf, { body: { id: remoteId(), documentNumber: encf,
      companyIdentification: "101000001", status: "FINISHED", legalStatus: "REJECTED", sequenceConsumed: true } });
    const outcome = await service.dispatchOnce(user, document.id, port);
    expect(outcome.observation.providerOutcome).toBe("REJECTED");
    expect(await stored(companyId, document.id)).toMatchObject({ status: "HUMAN_REVIEW_REQUIRED",
      safeErrorCode: "ECF_OBSERVED_REJECTED", fiscalSnapshot: null });
  });

  it("records a pending operational status without acceptance", async () => {
    const { companyId, user } = await tenant();
    const encf = nextEncf();
    const document = await prepared(user, encf);
    const { port } = simulated(encf, { body: { id: remoteId(), documentNumber: encf,
      companyIdentification: "101000001", status: "WAITING_RESPONSE", sequenceConsumed: true } });
    const outcome = await service.dispatchOnce(user, document.id, port);
    expect(outcome.observation.providerOutcome).toBe("PENDING");
    expect((await stored(companyId, document.id)).status).toBe("HUMAN_REVIEW_REQUIRED");
  });

  it("never treats HTTP 200 as fiscal acceptance", async () => {
    const { companyId, user } = await tenant();
    const encf = nextEncf();
    const document = await prepared(user, encf);
    const { port } = simulated(encf, { status: 200 });
    const outcome = await service.dispatchOnce(user, document.id, port);
    expect(outcome.correlated).toBe(false);
    expect((await stored(companyId, document.id)).status).toBe("UNKNOWN_RESULT");
  });

  it("keeps timeout unknown and refuses a second dispatch", async () => {
    const { companyId, user } = await tenant();
    const encf = nextEncf();
    const document = await prepared(user, encf);
    const { port, calls } = simulated(encf, { errorCode: "TIMEOUT" });
    await service.dispatchOnce(user, document.id, port);
    expect(await stored(companyId, document.id)).toMatchObject({ status: "UNKNOWN_RESULT", externalProviderId: null });
    await expect(service.dispatchOnce(user, document.id, port)).rejects.toThrow();
    expect(calls).toHaveLength(1);
  });

  it("does not bind a contradictory identity", async () => {
    const { companyId, user } = await tenant();
    const encf = nextEncf();
    const document = await prepared(user, encf);
    const { port } = simulated(encf, { body: { id: remoteId(), documentNumber: "E319999999999",
      companyIdentification: "101000001", status: "FINISHED", legalStatus: "ACCEPTED", sequenceConsumed: true } });
    const outcome = await service.dispatchOnce(user, document.id, port);
    expect(outcome.correlated).toBe(false);
    expect(await stored(companyId, document.id)).toMatchObject({ status: "UNKNOWN_RESULT", externalProviderId: null });
  });

  it("allows only one effective dispatch under concurrency", async () => {
    const { companyId, user } = await tenant();
    const encf = nextEncf();
    const document = await prepared(user, encf);
    const a = simulated(encf), b = simulated(encf);
    const results = await Promise.allSettled([
      service.dispatchOnce(user, document.id, a.port),
      service.dispatchOnce(user, document.id, b.port),
    ]);
    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    expect(a.calls.length + b.calls.length).toBe(1);
    expect((await stored(companyId, document.id)).status).toBe("HUMAN_REVIEW_REQUIRED");
  });

  it("blocks an E31 lacking the required buyer at preparation", async () => {
    const { user } = await tenant();
    const { buyer, ...withoutBuyer } = validE31WithItbis;
    expect(buyer).toBeDefined();
    await expect(service.prepare(user, { document: withoutBuyer, metadata: metadata(nextEncf()), clientRequestId: randomUUID() })).rejects.toThrow();
  });

  it("is idempotent per operation and refuses a divergent retry", async () => {
    const { user } = await tenant();
    const encf = nextEncf(), requestId = randomUUID();
    const first = await service.prepare(user, { document: validE31WithItbis, metadata: metadata(encf), clientRequestId: requestId });
    const again = await service.prepare(user, { document: validE31WithItbis, metadata: metadata(encf), clientRequestId: requestId });
    expect(again.id).toBe(first.id);
    await expect(service.prepare(user, { document: { ...validE31WithItbis, issueDate: "2026-10-15" },
      metadata: metadata(encf), clientRequestId: requestId })).rejects.toThrow();
  });

  it("isolates companies and refuses cross-tenant dispatch", async () => {
    const { user } = await tenant();
    const other = await tenant();
    const document = await prepared(user, nextEncf());
    const { port, calls } = simulated(nextEncf());
    await expect(service.dispatchOnce(other.user, document.id, port)).rejects.toThrow();
    expect(calls).toHaveLength(0);
  });
});
