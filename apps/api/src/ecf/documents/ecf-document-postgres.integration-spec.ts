import { randomUUID } from "node:crypto";
import { isEcfLocalTarget, matchEcfLocalTarget } from "../ecf-local-target";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { Client } from "pg";
import { PrismaService } from "../../prisma/prisma.service";
import { validE31WithItbis } from "../fiscal-core/ecf-fixtures";
import { canTransitionEcfDocument } from "./ecf-document-state-machine";
import { EcfDocumentIdempotencyService } from "./ecf-document-idempotency.service";

// Opt-in: normal test runs never connect to a database.
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

uat("ECF isolated PostgreSQL UAT", () => {
  let prisma: PrismaService;
  let service: EcfDocumentIdempotencyService;
  const companies = [randomUUID(), randomUUID()];
  const input = (companyId = companies[0], clientRequestId = randomUUID()) => ({
    companyId, clientRequestId, document: validE31WithItbis,
  });

  beforeAll(async () => {
    if (!isEcfLocalTarget()) throw new Error("ECF_UAT_TARGET_REFUSED");
    if (process.env.ALANUBE_ENABLE_REAL_CALLS !== "false" || process.env.ECF_EMISSION_ENABLED === "true") {
      throw new Error("ECF_UAT_EXTERNAL_CALLS_REFUSED");
    }
    prisma = new PrismaService();
    await prisma.$connect();
    const identity = await prisma.$queryRaw<Array<{ name: string }>>`SELECT current_database() AS name`;
    expect(identity[0].name).toBe(matchEcfLocalTarget()?.name);
    await prisma.company.createMany({ data: companies.map((id) => ({
      id, name: "Synthetic ECF 61-70 UAT", slug: `ecf-61-70-${id}`,
    })) });
    service = new EcfDocumentIdempotencyService(prisma);
  });

  afterAll(async () => {
    if (!prisma) return;
    try {
      // Only this run's random synthetic companies; cascade removes their fixtures.
      await prisma.company.deleteMany({ where: { id: { in: companies }, slug: { startsWith: "ecf-61-70-" } } });
    } finally { await prisma.$disconnect(); }
  });

  it("1: permits two independent operations with identical content", async () => {
    const a = await service.prepareLocalDocument(input());
    const b = await service.prepareLocalDocument(input());
    expect(a.id).not.toBe(b.id);
    expect(a.payloadFingerprint).toBe(b.payloadFingerprint);
  });

  it("2: replays the same operation once", async () => {
    const request = input();
    const a = await service.prepareLocalDocument(request);
    const b = await service.prepareLocalDocument(request);
    expect(b.id).toBe(a.id);
    expect(await prisma.ecfElectronicDocumentAttempt.count({ where: { companyId: request.companyId, documentId: a.id } })).toBe(1);
  });

  it("3: rejects changed content for an existing source operation", async () => {
    const request = { companyId: companies[0], sourceType: "SALE" as const, sourceId: randomUUID(), document: validE31WithItbis };
    const a = await service.prepareLocalDocument(request);
    await expect(service.prepareLocalDocument({ ...request, document: { ...validE31WithItbis, issueDate: "2026-10-15" } }))
      .rejects.toThrow("IDEMPOTENCY_PAYLOAD_MISMATCH");
    expect((await prisma.ecfElectronicDocument.findFirstOrThrow({ where: { id: a.id, companyId: request.companyId } })).payloadFingerprint).toBe(a.payloadFingerprint);
  });

  it("4: serializes concurrent same-operation creates and rejects divergent racers", async () => {
    const request = input();
    const results = await Promise.all(Array.from({ length: 8 }, () => service.prepareLocalDocument(request)));
    expect(new Set(results.map((r) => r.id)).size).toBe(1);
    const divergent = input();
    const races = await Promise.allSettled([
      service.prepareLocalDocument(divergent),
      service.prepareLocalDocument({ ...divergent, document: { ...validE31WithItbis, issueDate: "2026-10-15" } }),
    ]);
    expect(races.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    const rejected = races.find((r) => r.status === "rejected") as PromiseRejectedResult;
    expect(rejected.reason.message).toContain("IDEMPOTENCY_PAYLOAD_MISMATCH");
  });

  it("5: scopes the same request identity independently to two companies", async () => {
    const requestId = randomUUID();
    const a = await service.prepareLocalDocument(input(companies[0], requestId));
    const b = await service.prepareLocalDocument(input(companies[1], requestId));
    expect(a.id).not.toBe(b.id);
    expect(await prisma.ecfElectronicDocument.findFirst({ where: { id: a.id, companyId: companies[1] } })).toBeNull();
  });

  it("6: rolls back an expired PostgreSQL transaction", async () => {
    const key = `timeout-${randomUUID()}`;
    await expect(prisma.$transaction(async (tx) => {
      await tx.ecfElectronicDocument.create({ data: {
        companyId: companies[0], documentType: "E31", idempotencyKey: key, payloadFingerprint: "a".repeat(64),
      } });
      await tx.$queryRaw`SELECT pg_sleep(0.2)`;
    }, { timeout: 50 })).rejects.toThrow();
    expect(await prisma.ecfElectronicDocument.count({ where: { companyId: companies[0], idempotencyKey: key } })).toBe(0);
  });

  it("7: survives client/service recreation without duplicating the operation", async () => {
    const request = input();
    const a = await service.prepareLocalDocument(request);
    const restarted = new PrismaService();
    try {
      const b = await new EcfDocumentIdempotencyService(restarted).prepareLocalDocument(request);
      expect(b.id).toBe(a.id);
    } finally { await restarted.$disconnect(); }
  });

  it("8: persists an unknown result and never resets it on replay", async () => {
    const request = input();
    const a = await service.prepareLocalDocument(request);
    // Synthetic crash fixture only; no provider request was sent.
    await prisma.ecfElectronicDocument.updateMany({ where: { id: a.id, companyId: request.companyId }, data: { status: "SEND_IN_PROGRESS" } });
    await service.recordUnknownOutcome(request.companyId, a.id, "TIMEOUT");
    const b = await service.prepareLocalDocument(request);
    expect(b.status).toBe("UNKNOWN_RESULT");
    expect(canTransitionEcfDocument(b.status, "READY_TO_SEND").ok).toBe(false);
    await expect(service.recordUnknownOutcome(companies[1], a.id, "PROCESS_RESTART")).rejects.toThrow("ECF_DOCUMENT_NOT_IN_PROGRESS");
  });

  it("9: keeps atomic preparation and outcome history without duplicate logs", async () => {
    const request = input();
    const a = await service.prepareLocalDocument(request);
    await prisma.ecfElectronicDocument.updateMany({ where: { id: a.id, companyId: request.companyId }, data: { status: "SEND_IN_PROGRESS" } });
    await Promise.all([service.recordUnknownOutcome(request.companyId, a.id, "PROCESS_RESTART"), service.recordUnknownOutcome(request.companyId, a.id, "PROCESS_RESTART")]);
    expect(await prisma.ecfElectronicDocumentStatusLog.count({ where: { documentId: a.id, companyId: request.companyId } })).toBe(2);
    expect(await prisma.ecfElectronicDocumentAttempt.count({ where: { documentId: a.id, companyId: request.companyId } })).toBe(1);
  });

  it("10: retains unique-operation and foreign-key constraints", async () => {
    const a = await service.prepareLocalDocument(input());
    await expect(prisma.ecfElectronicDocument.create({ data: {
      companyId: companies[0], documentType: "E31", idempotencyKey: a.idempotencyKey, payloadFingerprint: a.payloadFingerprint,
    } })).rejects.toMatchObject({ code: "P2002" });
    await expect(prisma.ecfElectronicDocument.create({ data: {
      companyId: randomUUID(), documentType: "E31", idempotencyKey: randomUUID(), payloadFingerprint: a.payloadFingerprint,
    } })).rejects.toMatchObject({ code: "P2003" });
  });

  async function legacyMigrationFixture(run: (client: Client, sql: string) => Promise<void>) {
    const client = new Client({ connectionString: process.env.DATABASE_URL });
    await client.connect();
    try {
      // Session-local tables shadow public tables. No production or UAT row is rewritten.
      await client.query(`CREATE TEMP TABLE ecf_electronic_documents (
        id uuid PRIMARY KEY, company_id uuid, document_type text, source_type text,
        source_id uuid, idempotency_key text, payload_fingerprint text);
        CREATE UNIQUE INDEX ecf_electronic_documents_company_id_payload_fingerprint_key
          ON ecf_electronic_documents(company_id,payload_fingerprint);
        CREATE UNIQUE INDEX ecf_temp_operation_key ON ecf_electronic_documents(company_id,idempotency_key);
        CREATE TEMP TABLE ecf_electronic_document_attempts (
          document_id uuid, company_id uuid, idempotency_key text);`);
      const sql = readFileSync(join(__dirname, "../../../prisma/migrations/20261014160000_ecf_stable_operation_identity/migration.sql"), "utf8");
      await run(client, sql);
    } finally { await client.end(); }
  }

  it("11: migrates legacy source/manual keys and their attempts without losing rows", async () => {
    await legacyMigrationFixture(async (client, sql) => {
      const sourceId = randomUUID();
      const ids = [randomUUID(), randomUUID()];
      for (let i = 0; i < 2; i++) {
        const oldKey = `ecf:${companies[0]}:E31:MANUAL:legacy-${i}`;
        await client.query("INSERT INTO ecf_electronic_documents VALUES ($1,$2,'E31',$3,$4,$5,$6)",
          [ids[i], companies[0], i === 0 ? "SALE" : null, i === 0 ? sourceId : null, oldKey, String(i).repeat(64)]);
        await client.query("INSERT INTO ecf_electronic_document_attempts VALUES ($1,$2,$3)", [ids[i], companies[0], oldKey]);
      }
      await client.query(sql);
      const result = await client.query("SELECT id,idempotency_key FROM ecf_electronic_documents ORDER BY id");
      expect(result.rows).toHaveLength(2);
      expect(result.rows.find((r) => r.id === ids[0]).idempotency_key).toBe(`ecf:v2:${companies[0]}:E31:SOURCE:SALE:${sourceId}`);
      expect(result.rows.find((r) => r.id === ids[1]).idempotency_key).toBe(`ecf:v2:${companies[0]}:E31:REQUEST:${ids[1]}`);
      expect((await client.query(`SELECT count(*)::int AS n FROM ecf_electronic_document_attempts a
        JOIN ecf_electronic_documents d ON a.document_id=d.id AND a.company_id=d.company_id
        WHERE a.idempotency_key=d.idempotency_key`)).rows[0].n).toBe(2);
    });
  });

  it("12: aborts migration on divergent legacy operations and preserves old keys", async () => {
    await legacyMigrationFixture(async (client, sql) => {
      const sourceId = randomUUID();
      for (let i = 0; i < 2; i++) {
        await client.query("INSERT INTO ecf_electronic_documents VALUES ($1,$2,'E31','SALE',$3,$4,$5)",
          [randomUUID(), companies[0], sourceId, `ecf:${companies[0]}:E31:SALE:${i}`, String(i).repeat(64)]);
      }
      await expect(client.query(sql)).rejects.toThrow("ECF_LEGACY_OPERATION_CONFLICT");
      await client.query("ROLLBACK");
      expect((await client.query("SELECT count(*)::int AS n FROM ecf_electronic_documents WHERE idempotency_key LIKE 'ecf:v2:%'")).rows[0].n).toBe(0);
      expect((await client.query("SELECT count(*)::int AS n FROM ecf_electronic_documents")).rows[0].n).toBe(2);
    });
  });
});
