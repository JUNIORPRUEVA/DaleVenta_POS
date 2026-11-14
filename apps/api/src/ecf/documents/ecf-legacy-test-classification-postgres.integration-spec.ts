import { randomUUID } from "node:crypto";
import { PrismaService } from "../../prisma/prisma.service";
import { isEcfEphemeralTestTarget } from "../ecf-local-target";
import { validE31WithItbis } from "../fiscal-core/ecf-fixtures";
import { fingerprint } from "./ecf-document-idempotency.service";
import { applyLegacyTestClassification, planLegacyTestClassification } from "./ecf-legacy-test-classification";
import { ecfPrintView } from "./ecf-print-view";
import { EcfSequenceService } from "./ecf-sequence.service";

const local = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;
local("reviewed legacy TEST classification, isolated PostgreSQL", () => {
  let db: PrismaService;
  const companyId = randomUUID();
  const issuerRnc = validE31WithItbis.sender.taxId;
  let rangeId: string;
  beforeAll(async () => {
    if (!isEcfEphemeralTestTarget() || process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") throw Error("ISOLATED_TEST_REQUIRED");
    db = new PrismaService(); await db.$connect();
    await db.company.create({ data: { id: companyId, name: "Synthetic legacy classification", slug: `review-${companyId}` } });
    await db.ecfCompanyConfiguration.create({ data: { companyId, environment: "SANDBOX", enabled: true } });
    const range = await db.ecfSequence.create({ data: { companyId, documentType: "E31", prefix: "E31", environment: "PRODUCTION",
      startNumber: 1, nextNumber: 20, endNumber: 1000 } });
    rangeId = range.id;
  });
  afterAll(async () => { await db?.$disconnect(); });
  async function legacy(number: number, proof = true) {
    const encf = `E31${String(number).padStart(10, "0")}`;
    const document = await db.ecfElectronicDocument.create({ data: {
      companyId, environment: null, documentType: "E31", status: "HUMAN_REVIEW_REQUIRED", sourceType: "MANUAL",
      idempotencyKey: `legacy-synthetic:${randomUUID()}`, payloadFingerprint: fingerprint(validE31WithItbis), fiscalDocument: validE31WithItbis as any,
      payloadSummary: { emission: { encf }, ...(proof ? { controlledTest: { environment: "TEST", plan: "SYNTHETIC_LOCAL_REVIEW",
        responseSha256: "a".repeat(64), outcome: "ACCEPTED", correlated: true } } : {}) },
    } });
    const allocation = await db.ecfSequenceAuditLog.create({ data: { companyId, documentId: document.id, sequenceId: rangeId,
      type: "E31", action: "ALLOCATED", encf, operationKey: `legacy-synthetic:${document.id}` } });
    return { document, allocation };
  }
  function scope(...ids: string[]) { return { companyId, issuerRnc, documentIds: ids }; }

  it("plans read-only, classifies once and preserves fiscal identity, state and counters", async () => {
    const { document, allocation } = await legacy(1);
    const plan = await planLegacyTestClassification(db, scope(document.id));
    expect(plan.minimumTestNext.E31).toBe(20);
    expect((await db.ecfElectronicDocument.findUniqueOrThrow({ where: { id: document.id } })).environment).toBeNull();
    await expect(applyLegacyTestClassification(db, plan, "b".repeat(64), "Synthetic local reviewer")).rejects.toThrow("EXPLICIT_REVIEW_REQUIRED");
    expect((await applyLegacyTestClassification(db, plan, plan.manifestHash, "Synthetic local reviewer")).classified).toBe(1);
    expect((await applyLegacyTestClassification(db, plan, plan.manifestHash, "Synthetic local reviewer")).classified).toBe(0);
    const after = await db.ecfElectronicDocument.findFirstOrThrow({ where: { companyId, id: document.id } });
    expect(after.environment).toBe("SANDBOX");
    expect(after.status).toBe(document.status);
    expect(after.payloadFingerprint).toBe(document.payloadFingerprint);
    expect(after.fiscalDocument).toEqual(document.fiscalDocument);
    expect(after.payloadSummary).toEqual(document.payloadSummary);
    expect(await db.ecfSequenceAuditLog.findFirstOrThrow({ where: { companyId, id: allocation.id } })).toEqual(allocation);
    expect((await db.ecfSequence.findFirstOrThrow({ where: { companyId, id: rangeId } })).nextNumber).toBe(20);
    expect(await db.ecfElectronicDocumentStatusLog.count({ where: { companyId, documentId: document.id,
      reasonCode: "LEGACY_TEST_ENVIRONMENT_CLASSIFIED" } })).toBe(1);
    await expect(db.ecfElectronicDocument.updateMany({ where: { companyId, id: document.id }, data: { environment: "PRODUCTION" } })).rejects.toThrow("ECF_ENVIRONMENT_IMMUTABLE");
  });
  it("database rejects classification without evidence in this exact transaction", async () => {
    const { document } = await legacy(2);
    await expect(db.ecfElectronicDocument.updateMany({ where: { companyId, id: document.id }, data: { environment: "SANDBOX" } })).rejects.toThrow("ECF_ENVIRONMENT_IMMUTABLE");
    const range = await db.ecfSequence.findFirstOrThrow({ where: { companyId, id: rangeId } });
    await expect(db.ecfSequence.updateMany({ where: { companyId, id: range.id }, data: { environment: "SANDBOX" } })).rejects.toThrow("ECF_ENVIRONMENT_IMMUTABLE");
  });
  it("rejects another tenant, wrong issuer, missing proof and altered manifest", async () => {
    const { document } = await legacy(3);
    await expect(planLegacyTestClassification(db, { ...scope(document.id), companyId: randomUUID() })).rejects.toThrow("TEST_CONFIGURATION_REQUIRED");
    await expect(planLegacyTestClassification(db, { ...scope(document.id), issuerRnc: "999999999" })).rejects.toThrow("FISCAL_IDENTITY_OR_FINGERPRINT_MISMATCH");
    const withoutProof = await legacy(4, false);
    await expect(planLegacyTestClassification(db, scope(withoutProof.document.id))).rejects.toThrow("TEST_EVIDENCE_REQUIRED");
    const plan = await planLegacyTestClassification(db, scope(document.id));
    const altered = { ...plan, minimumTestNext: { E31: 1 } };
    await expect(applyLegacyTestClassification(db, altered, plan.manifestHash, "Synthetic local reviewer")).rejects.toThrow("MANIFEST_TAMPERED");
  });
  it("rejects stale plans atomically without classifying another document", async () => {
    const first = await legacy(5); const second = await legacy(6);
    const plan = await planLegacyTestClassification(db, scope(first.document.id, second.document.id));
    await db.ecfElectronicDocument.updateMany({ where: { companyId, id: second.document.id }, data: { status: "DGII_STATUS_PENDING" } });
    await expect(applyLegacyTestClassification(db, plan, plan.manifestHash, "Synthetic local reviewer")).rejects.toThrow("STALE_MANIFEST");
    expect(await db.ecfElectronicDocument.count({ where: { companyId, id: { in: [first.document.id, second.document.id] }, environment: null } })).toBe(2);
    expect(await db.ecfElectronicDocumentStatusLog.count({ where: { companyId, documentId: first.document.id,
      reasonCode: "LEGACY_TEST_ENVIRONMENT_CLASSIFIED" } })).toBe(0);
  });
  it("restores only a validated TEST print stamp without granting fiscal acceptance", async () => {
    const { document } = await legacy(7);
    const summary = document.payloadSummary as Record<string, any>;
    const url = `https://ecf.dgii.gov.do/testecf/ConsultaTimbre?RNCEmisor=${issuerRnc}&RncComprador=${validE31WithItbis.buyer!.taxId}&ENCF=E310000000007&FechaEmision=14-10-2026&MontoTotal=118.00&FechaFirma=14-10-2026%2012:00:00&CodigoSeguridad=ABC123`;
    await db.ecfElectronicDocument.updateMany({ where: { companyId, id: document.id }, data: { payloadSummary: {
      ...summary, controlledTest: { ...summary.controlledTest, safeResponse: JSON.stringify({ estado: "Aceptado", codigo: "1", rnc: issuerRnc,
        encf: "E310000000007", secuenciaUtilizada: true, url, codigoSeguridad: "ABC123", fechaFirma: "14-10-2026 12:00:00", apiKey: "must-not-leak" }) },
    } } });
    const plan = await planLegacyTestClassification(db, scope(document.id));
    expect(plan.documents[0].printStamp?.securityCode).toBe("ABC123");
    expect(JSON.stringify(plan)).not.toContain("must-not-leak");
    await applyLegacyTestClassification(db, plan, plan.manifestHash, "Synthetic local reviewer");
    const after = await db.ecfElectronicDocument.findFirstOrThrow({ where: { companyId, id: document.id } });
    expect(ecfPrintView(after)).toMatchObject({ state: "SIGNED", securityCode: "ABC123" });
    expect(after.status).toBe("HUMAN_REVIEW_REQUIRED");
    expect(after.payloadFingerprint).toBe(document.payloadFingerprint);
  });
  it("cannot reuse a legacy TEST frontier when registering, renewing or allocating a new Sandbox range", async () => {
    const service = new EcfSequenceService(db);
    const user = { id: randomUUID(), companyId, role: "ADMIN" };
    await db.ecfDgiiAuthorizedSequence.create({ data: { companyId, environment: "SANDBOX", documentType: "E31",
      authorizationNumber: "Synthetic reviewed TEST", rangeFrom: 1, rangeTo: 1000, approvedQuantity: 1000,
      declarationVersion: "synthetic-local" } });
    const input = { documentType: "E31", startNumber: 1, endNumber: 1000 };
    await expect(service.register(user, input)).rejects.toThrow("ECF_SEQUENCE_LEGACY_TEST_REVIEW_REQUIRED");
    // A legacy range may predate the review; create that fixture without ever
    // rewinding a persisted counter (the database correctly forbids rewinds).
    const obsolete = await db.ecfSequence.create({ data: { companyId, environment: "SANDBOX", documentType: "E31",
      prefix: "E31", startNumber: 1, nextNumber: 1, endNumber: 1000 } });
    const unclassified = await db.ecfElectronicDocument.findMany({ where: { companyId, environment: null,
      payloadSummary: { path: ["controlledTest", "environment"], equals: "TEST" } }, select: { id: true } });
    const plan = await planLegacyTestClassification(db, scope(...unclassified.map(row => row.id)));
    await applyLegacyTestClassification(db, plan, plan.manifestHash, "Synthetic frontier review");
    await expect(service.register(user, input)).rejects.toMatchObject({ response: { code: "ECF_SEQUENCE_LEGACY_TEST_REUSE_BLOCKED", minimumStartNumber: 20 } });
    await expect(service.allocate(user, "E31")).rejects.toMatchObject({ response: { code: "ECF_SEQUENCE_LEGACY_TEST_REUSE_BLOCKED" } });
    expect(await db.ecfSequenceAuditLog.count({ where: { companyId, environment: "SANDBOX", action: "ALLOCATED" } })).toBe(0);
    await db.ecfSequence.updateMany({ where: { companyId, id: obsolete.id }, data: { active: false } });
    await service.register(user, { ...input, startNumber: 20 });
    expect((await service.allocate(user, "E31")).encf).toBe("E310000000020");
    await expect(service.renew(user, input)).rejects.toMatchObject({ response: { code: "ECF_SEQUENCE_LEGACY_TEST_REUSE_BLOCKED" } });
    expect((await db.ecfSequence.findFirstOrThrow({ where: { companyId, id: rangeId } })).nextNumber).toBe(20);
  });
});
