import { randomUUID } from "node:crypto";
import { PrismaService } from "../../../prisma/prisma.service";
import { isEcfEphemeralTestTarget } from "../../ecf-local-target";
import { claimPersistedDosaRequest, assertDosaClaimOwner } from "./dosa-persisted-recovery";
import { auditDosaSameRequestRecovery, DOSA_REPLAY_REASON } from "./dosa-same-request-recovery";
import type { DosaReplayInfo } from "./dosa-emission.client";

const local = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;
local("autorización y auditoría del replay DOSA — PostgreSQL local", () => {
  let db: PrismaService;
  const companyId = randomUUID(), actor = randomUUID();
  const user = { id: actor, companyId, role: "ADMIN" };
  const decision = { allowed: true, credentialFingerprint: "c".repeat(64) };
  const dosa = { assess: async () => ({ ...decision }) } as never;
  const expected = { environment: "test" as const, rnc: "101000001", documentType: "E31" as const,
    credentialFingerprint: "c".repeat(64), documentFingerprint: "a".repeat(64), requestFingerprint: "b".repeat(64),
    bodyHash: "d".repeat(64), pathHash: "e".repeat(64), requestHash: "f".repeat(64) };
  const info: DosaReplayInfo = { ordinal: 2, reason: "TIMEOUT", httpStatus: null,
    bodyHash: expected.bodyHash, pathHash: expected.pathHash, requestHash: expected.requestHash, previousResponseHash: null };

  beforeAll(async () => {
    if (!isEcfEphemeralTestTarget() || process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") throw Error("ISOLATED_TEST_REQUIRED");
    db = new PrismaService(); await db.$connect();
    await db.company.create({ data: { id: companyId, name: "Synthetic replay", slug: `replay-${companyId}` } });
    await db.ecfCompanyConfiguration.create({ data: { companyId, enabled: true, provider: "DOSA", environment: "SANDBOX",
      certificationStatus: "AUTHORIZED_SANDBOX" } });
    await db.user.create({ data: { id: actor, email: `replay-${actor}@synthetic.test`, passwordHash: "synthetic-not-a-password",
      nombreCompleto: "Synthetic replay user", telefono: "0000000000", edad: 30, role: "ADMIN" } });
  });
  afterAll(async () => { await db?.$disconnect(); });
  beforeEach(async () => {
    decision.allowed = true; decision.credentialFingerprint = expected.credentialFingerprint;
    await db.ecfCompanyConfiguration.update({ where: { companyId }, data: { enabled: true, provider: "DOSA", environment: "SANDBOX",
      certificationStatus: "AUTHORIZED_SANDBOX", productionEnabled: false } });
  });
  async function claim(environment: "SANDBOX" | "PRODUCTION" = "SANDBOX") {
    const key = `synthetic-replay:${randomUUID()}`;
    const document = await db.ecfElectronicDocument.create({ data: { companyId, environment, documentType: "E31",
      status: "SEND_IN_PROGRESS", sourceType: "MANUAL", idempotencyKey: key, payloadFingerprint: expected.documentFingerprint } });
    const parent = await db.ecfElectronicDocumentAttempt.create({ data: { companyId, documentId: document.id,
      operation: "SEND_TO_PROVIDER", idempotencyKey: key, requestFingerprint: expected.requestFingerprint,
      statusBefore: "LOCAL_VALIDATED", statusAfter: "SEND_IN_PROGRESS", createdByUserId: actor } });
    return { document, parent };
  }
  function run(documentId: string, parentId: string, event = info, context = user) {
    return auditDosaSameRequestRecovery(db, dosa, context, documentId, parentId, event, expected);
  }
  function logs(documentId: string) { return db.ecfElectronicDocumentStatusLog.findMany({ where: { companyId, documentId, reasonCode: DOSA_REPLAY_REASON } }); }

  it("serializa dos recuperaciones concurrentes y permite sólo los ordinales 2 y 3", async () => {
    const { document, parent } = await claim();
    const results = await Promise.all([run(document.id, parent.id), run(document.id, parent.id)]);
    expect(results.sort()).toEqual([false, true]);
    expect(await logs(document.id)).toHaveLength(1);
    expect(await run(document.id, parent.id, { ...info, ordinal: 3 })).toBe(true);
    expect(await run(document.id, parent.id, { ...info, ordinal: 3 })).toBe(false);
    expect(await logs(document.id)).toHaveLength(2);
    const after = await db.ecfElectronicDocument.findFirstOrThrow({ where: { companyId, id: document.id } });
    expect(after.payloadFingerprint).toBe(document.payloadFingerprint);
    expect(after.status).toBe("SEND_IN_PROGRESS");
    expect(await db.ecfElectronicDocumentAttempt.count({ where: { companyId, documentId: document.id, operation: "SEND_TO_PROVIDER" } })).toBe(1);
    expect(await db.ecfSequenceAuditLog.count({ where: { companyId, documentId: document.id } })).toBe(0);
  });
  it("no autoriza datos alterados, otro padre u otra empresa", async () => {
    const { document, parent } = await claim();
    for (const field of ["bodyHash", "pathHash", "requestHash"] as const) {
      expect(await run(document.id, parent.id, { ...info, [field]: "0".repeat(64) })).toBe(false);
    }
    expect(await run(document.id, randomUUID())).toBe(false);
    expect(await run(document.id, parent.id, info, { ...user, companyId: randomUUID() })).toBe(false);
    expect(await logs(document.id)).toHaveLength(0);
  });
  it("revocación o cambio de credencial interrumpe antes del transporte", async () => {
    const { document, parent } = await claim();
    decision.allowed = false; expect(await run(document.id, parent.id)).toBe(false);
    decision.allowed = true; decision.credentialFingerprint = "0".repeat(64);
    expect(await run(document.id, parent.id)).toBe(false);
    expect(await logs(document.id)).toHaveLength(0);
  });
  it("recomprueba en la base certificación, módulo, proveedor y ambiente antes de autorizar", async () => {
    const { document, parent } = await claim();
    for (const status of ["SUSPENDED", "BLOCKED", "NOT_STARTED"] as const) {
      await db.ecfCompanyConfiguration.update({ where: { companyId }, data: { certificationStatus: status } });
      expect(await run(document.id, parent.id)).toBe(false);
    }
    await db.ecfCompanyConfiguration.update({ where: { companyId }, data: { certificationStatus: "AUTHORIZED_SANDBOX", enabled: false } });
    expect(await run(document.id, parent.id)).toBe(false);
    await db.ecfCompanyConfiguration.update({ where: { companyId }, data: { enabled: true, provider: "ALANUBE" } });
    expect(await run(document.id, parent.id)).toBe(false);
    await db.ecfCompanyConfiguration.update({ where: { companyId }, data: { provider: "DOSA", environment: "PRODUCTION" } });
    expect(await run(document.id, parent.id)).toBe(false);
    expect(await logs(document.id)).toHaveLength(0);
  });
  it("no reanuda una operación que ya terminó ni un documento de otro ambiente", async () => {
    const { document, parent } = await claim();
    await db.ecfElectronicDocument.updateMany({ where: { companyId, id: document.id }, data: { status: "UNKNOWN_RESULT" } });
    expect(await run(document.id, parent.id)).toBe(false);
    await db.ecfElectronicDocument.updateMany({ where: { companyId, id: document.id }, data: { status: "SEND_IN_PROGRESS" } });
    expect(await auditDosaSameRequestRecovery(db, dosa, user, document.id, parent.id, info, { ...expected, environment: "production" })).toBe(false);
    expect(await logs(document.id)).toHaveLength(0);
  });
  it("en producción requiere autorización productiva y certificación propias además de la compuerta", async () => {
    const { document, parent } = await claim("PRODUCTION");
    const production = { ...expected, environment: "production" as const };
    const replay = () => auditDosaSameRequestRecovery(db, dosa, user, document.id, parent.id, info, production);
    await db.ecfCompanyConfiguration.update({ where: { companyId }, data: { environment: "PRODUCTION",
      certificationStatus: "PRODUCTION_READY", productionEnabled: false } });
    expect(await replay()).toBe(false);
    await db.ecfCompanyConfiguration.update({ where: { companyId }, data: { productionEnabled: true,
      certificationStatus: "AUTHORIZED_SANDBOX" } });
    expect(await replay()).toBe(false);
    expect(await logs(document.id)).toHaveLength(0);
    await db.ecfCompanyConfiguration.update({ where: { companyId }, data: { certificationStatus: "PRODUCTION_READY" } });
    expect(await replay()).toBe(true);
    expect(await logs(document.id)).toHaveLength(1);
  });
  it("durable recovery rejects changed identities, respects leases and fences stale workers", async () => {
    const {document,parent}=await claim();
    const identity={bodyHash:expected.bodyHash,pathHash:expected.pathHash,requestHash:expected.requestHash,
      destinationHash:"1".repeat(64),credentialFingerprint:expected.credentialFingerprint,
      documentFingerprint:expected.documentFingerprint,requestFingerprint:expected.requestFingerprint,environment:"SANDBOX" as const};
    const persist=(attempt:string,recovering:boolean,context=identity)=>db.$transaction(async tx=>{
      await tx.$queryRaw`SELECT id FROM ecf_electronic_documents WHERE company_id=${companyId}::uuid AND id=${document.id}::uuid FOR UPDATE`;
      await claimPersistedDosaRequest(tx,user,document.id,attempt,recovering,context,300000);
    });
    await persist(parent.id,false);
    const next=randomUUID();
    await expect(persist(next,true)).rejects.toThrow("ECF_RECOVERY_WAIT_FOR_ACTIVE_REQUEST");
    const clock=jest.spyOn(Date,"now").mockReturnValue(Date.now()+600000);
    try {
      await expect(persist(next,true,{...identity,credentialFingerprint:"9".repeat(64)})).rejects.toThrow("ECF_RECOVERY_REQUEST_CHANGED_OR_UNPROVEN");
      await expect(persist(next,true,{...identity,bodyHash:"9".repeat(64)})).rejects.toThrow("ECF_RECOVERY_REQUEST_CHANGED_OR_UNPROVEN");
      await persist(next,true);
      await expect(db.$transaction(tx=>assertDosaClaimOwner(tx,companyId,document.id,parent.id))).rejects.toThrow("ECF_RECOVERY_STALE_WORKER");
      await db.$transaction(tx=>assertDosaClaimOwner(tx,companyId,document.id,next));
    }finally{clock.mockRestore();}
  });

});
