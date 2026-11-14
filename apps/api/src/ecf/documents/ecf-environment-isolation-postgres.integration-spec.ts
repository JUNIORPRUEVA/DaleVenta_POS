import { randomUUID } from "node:crypto";
import { PrismaService } from "../../prisma/prisma.service";
import { isEcfEphemeralTestTarget } from "../ecf-local-target";
import { EcfSequenceService } from "./ecf-sequence.service";
import { EcfDgiiAuthorizedSequencesService } from "./ecf-dgii-authorized-sequences.service";
import { EcfDocumentIdempotencyService } from "./ecf-document-idempotency.service";
import { validE31WithItbis } from "../fiscal-core/ecf-fixtures";

const local = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

local("Numbering environment boundaries on isolated PostgreSQL", () => {
  let db: PrismaService;
  const companyId = randomUUID();
  const otherCompanyId = randomUUID();
  const user = { id: randomUUID(), companyId, role: "ADMIN" };
  let sequences: EcfSequenceService;
  let authorizations: EcfDgiiAuthorizedSequencesService;

  beforeAll(async () => {
    if (!isEcfEphemeralTestTarget() || process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") throw Error("ISOLATED_TEST_REQUIRED");
    db = new PrismaService();
    await db.$connect();
    await db.company.createMany({ data: [companyId, otherCompanyId].map(id => ({ id, name: "Synthetic environment boundary", slug: `environment-${id}` })) });
    await db.ecfCompanyConfiguration.create({ data: { companyId, environment: "PRODUCTION", enabled: true } });
    await db.ecfCompanyConfiguration.create({ data: { companyId: otherCompanyId, environment: "SANDBOX", enabled: true } });
    sequences = new EcfSequenceService(db);
    authorizations = new EcfDgiiAuthorizedSequencesService(db);
  });
  afterAll(async () => { await db?.$disconnect(); });

  function declare() {
    return authorizations.declare(user, { documentType: "E31", authorizationNumber: "SYNTHETIC-TEST-ONLY", rangeFrom: 1, rangeTo: 10,
      approvedQuantity: 10, expiresAt: "2028-12-31", declarationAccepted: true });
  }

  it("keeps existing production numbering while TEST has no range", async () => {
    await declare();
    await sequences.register(user, { documentType: "E31", startNumber: 1, endNumber: 10 });
    expect((await sequences.allocate(user, "E31", { operationKey: "same-operation" })).encf).toBe("E310000000001");
    await db.ecfCompanyConfiguration.update({ where: { companyId }, data: { environment: "SANDBOX" } });
    expect(await sequences.list(user)).toEqual([]);
    expect((await authorizations.list(user)).items).toEqual([]);
    await expect(sequences.allocate(user, "E31")).rejects.toThrow("ECF_SEQUENCE_EXHAUSTED");
    await expect(sequences.register(user, { documentType: "E31", startNumber: 1, endNumber: 10 })).rejects.toThrow("NOT_AUTHORIZED");
    expect((await db.ecfSequence.findFirstOrThrow({ where: { companyId, environment: "PRODUCTION" } })).nextNumber).toBe(2);
  });

  it("allows the same approved numbers in TEST without consuming production or borrowing its idempotency record", async () => {
    await declare();
    await sequences.register(user, { documentType: "E31", startNumber: 1, endNumber: 10 });
    expect((await sequences.allocate(user, "E31", { operationKey: "same-operation" })).encf).toBe("E310000000001");
    expect((await sequences.allocate(user, "E31", { operationKey: "same-operation" })).encf).toBe("E310000000001");
    expect((await db.ecfSequence.findFirstOrThrow({ where: { companyId, environment: "SANDBOX" } })).nextNumber).toBe(2);
    expect((await db.ecfSequence.findFirstOrThrow({ where: { companyId, environment: "PRODUCTION" } })).nextNumber).toBe(2);
    expect(await db.ecfSequenceAuditLog.count({ where: { companyId, operationKey: "same-operation" } })).toBe(2);
  });

  it("rejects a different tenant even when its TEST mode matches", async () => {
    await expect(sequences.allocate({ ...user, companyId: otherCompanyId }, "E31")).rejects.toThrow("ECF_SEQUENCE_EXHAUSTED");
  });

  it("does not reuse an operation number when the configured environment changed after preparation began", async () => {
    await expect(sequences.allocate(user, "E31", { environment: "PRODUCTION" })).rejects.toThrow("ECF_NUMBERING_ENVIRONMENT_CHANGED");
    await expect(sequences.allocate(user, "E31", { environment: "PRODUCTION", operationKey: "same-operation" })).rejects.toThrow("ECF_NUMBERING_ENVIRONMENT_CHANGED");
    await expect(authorizations.declare(user, { documentType: "E31", authorizationNumber: "SYNTHETIC-STALE", rangeFrom: 1, rangeTo: 10,
      approvedQuantity: 10, expiresAt: "2028-12-31", declarationAccepted: true, expectedEnvironment: "PRODUCTION" })).rejects.toThrow("ECF_NUMBERING_ENVIRONMENT_CHANGED");
    await expect(sequences.renew(user, { documentType: "E31", startNumber: 2, endNumber: 10, expectedEnvironment: "PRODUCTION" })).rejects.toThrow("ECF_NUMBERING_ENVIRONMENT_CHANGED");
  });

  it("preserves the immutable environment of a numbering row", async () => {
    const range = await db.ecfSequence.findFirstOrThrow({ where: { companyId, environment: "SANDBOX" } });
    await expect(db.ecfSequence.updateMany({ where: { companyId, id: range.id }, data: { environment: "PRODUCTION" } })).rejects.toThrow("ECF_ENVIRONMENT_IMMUTABLE");
  });

  it("isolates document identity and allows equal e-NCFs only in separate confirmed environments", async () => {
    const service = new EcfDocumentIdempotencyService(db);
    const requestId = randomUUID();
    const a = await service.prepareLocalDocument({ companyId, clientRequestId: requestId, environment: "SANDBOX", document: validE31WithItbis });
    const b = await service.prepareLocalDocument({ companyId, clientRequestId: requestId, environment: "PRODUCTION", document: validE31WithItbis });
    expect(a.id).not.toBe(b.id);
    await db.ecfElectronicDocument.updateMany({ where: { companyId, id: a.id }, data: { externalDocumentNumber: "E310000000009" } });
    await db.ecfElectronicDocument.updateMany({ where: { companyId, id: b.id }, data: { externalDocumentNumber: "E310000000009" } });
    expect(await db.ecfElectronicDocument.count({ where: { companyId, externalDocumentNumber: "E310000000009" } })).toBe(2);
    await expect(db.ecfElectronicDocument.updateMany({ where: { companyId, id: a.id }, data: { environment: "PRODUCTION" } })).rejects.toThrow("ECF_ENVIRONMENT_IMMUTABLE");
  });
});
