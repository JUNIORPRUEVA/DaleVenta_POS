import { EcfElectronicDocumentStatus } from "@prisma/client";
import {
  EcfDocumentIdempotencyService,
  fingerprint,
} from "./ecf-document-idempotency.service";
import { validE31WithItbis } from "../fiscal-core/ecf-fixtures";

const companyId = "00000000-0000-4000-8000-000000000001";

function prismaMock() {
  const tx = {
    ecfElectronicDocument: {
      findUnique: jest.fn().mockResolvedValue(null),
      create: jest.fn().mockImplementation(({ data }) =>
        Promise.resolve({
          id: "00000000-0000-4000-8000-000000000777",
          ...data,
        }),
      ),
    },
    ecfElectronicDocumentAttempt: {
      create: jest.fn().mockResolvedValue({}),
    },
    ecfElectronicDocumentStatusLog: {
      create: jest.fn().mockResolvedValue({}),
    },
  };
  return {
    tx,
    prisma: {
      $transaction: jest.fn((fn) => fn(tx)),
    },
  };
}

describe("EcfDocumentIdempotencyService", () => {
  it("creates a local validated document without marking it emitted", async () => {
    const { prisma, tx } = prismaMock();
    const service = new EcfDocumentIdempotencyService(prisma as any);

    const result = await service.prepareLocalDocument({
      companyId,
      sourceType: "SALE",
      sourceId: "00000000-0000-4000-8000-000000000123",
      document: validE31WithItbis,
    });

    expect(result.status).toBe(EcfElectronicDocumentStatus.LOCAL_VALIDATED);
    expect(tx.ecfElectronicDocument.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          companyId,
          status: EcfElectronicDocumentStatus.LOCAL_VALIDATED,
        }),
      }),
    );
    expect(tx.ecfElectronicDocumentAttempt.create).toHaveBeenCalled();
    expect(tx.ecfElectronicDocumentStatusLog.create).toHaveBeenCalled();
  });

  it("returns the previous document for the same idempotency key and fingerprint", async () => {
    const { prisma, tx } = prismaMock();
    tx.ecfElectronicDocument.findUnique.mockResolvedValueOnce({
      id: "existing",
      payloadFingerprint: fingerprint(validE31WithItbis),
    });
    const service = new EcfDocumentIdempotencyService(prisma as any);

    const result = await service.prepareLocalDocument({
      companyId,
      clientRequestId: "00000000-0000-4000-8000-000000000123",
      document: validE31WithItbis,
    });

    expect(result.id).toBe("existing");
    expect(tx.ecfElectronicDocument.create).not.toHaveBeenCalled();
  });

  it("rejects idempotent retries with modified payloads", async () => {
    const { prisma, tx } = prismaMock();
    tx.ecfElectronicDocument.findUnique.mockResolvedValueOnce({
      id: "existing",
      payloadFingerprint: "different",
    });
    const service = new EcfDocumentIdempotencyService(prisma as any);

    await expect(
      service.prepareLocalDocument({ companyId, clientRequestId: "00000000-0000-4000-8000-000000000123", document: validE31WithItbis }),
    ).rejects.toThrow("IDEMPOTENCY_PAYLOAD_MISMATCH");
  });

  it("requires an explicit operation identity without a source", async () => {
    const { prisma } = prismaMock();
    await expect(new EcfDocumentIdempotencyService(prisma as any).prepareLocalDocument({
      companyId, document: validE31WithItbis,
    })).rejects.toThrow("ECF_CLIENT_REQUEST_ID_REQUIRED");
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it("separates operation identity from content", async () => {
    const { prisma, tx } = prismaMock();
    const service = new EcfDocumentIdempotencyService(prisma as any);
    const first = await service.prepareLocalDocument({ companyId, sourceType: "SALE",
      sourceId: "00000000-0000-4000-8000-000000000123", document: validE31WithItbis });
    const second = await service.prepareLocalDocument({ companyId, sourceType: "SALE",
      sourceId: "00000000-0000-4000-8000-000000000124", document: validE31WithItbis });
    expect(first.payloadFingerprint).toBe(second.payloadFingerprint);
    expect(first.idempotencyKey).not.toBe(second.idempotencyKey);
    tx.ecfElectronicDocument.findUnique.mockResolvedValueOnce(first);
    await expect(service.prepareLocalDocument({ companyId, sourceType: "SALE",
      sourceId: "00000000-0000-4000-8000-000000000123",
      document: { ...validE31WithItbis, issueDate: "2026-10-15" },
    })).rejects.toThrow("IDEMPOTENCY_PAYLOAD_MISMATCH");
  });
});
