import type { PrismaService } from "../../prisma/prisma.service";
import type { TenantUser } from "../../auth/tenant-context";
import { EcfDgiiApplicationService } from "./ecf-dgii-application.service";

const user = (companyId: string): TenantUser => ({
  id: "user-1",
  role: "ADMIN",
  companyId,
});

describe("EcfDgiiApplicationService draft sources", () => {
  const findDraft = jest.fn();
  const findCompany = jest.fn();
  const findConfig = jest.fn();
  const upsert = jest.fn();
  const transaction = jest.fn();
  const findSnapshots = jest.fn();
  const prisma = {
    ecfDgiiHabilitation: { findUnique: findDraft, upsert },
    company: { findUnique: findCompany },
    appConfig: { findFirst: findConfig },
    ecfDgiiApplicationSnapshot: { findMany: findSnapshots },
    $transaction: transaction,
  } as unknown as PrismaService;
  const service = new EcfDgiiApplicationService(prisma);

  beforeEach(() => {
    jest.clearAllMocks();
    findDraft.mockResolvedValue(null);
    findCompany.mockResolvedValue({ name: "Empresa Canónica" });
    findConfig.mockResolvedValue({
      rnc: "131000001",
      address: "Calle Fiscal",
      legalRepresentativeName: "Ana Pérez",
      legalRepresentativeCedula: "00100000001",
    });
  });

  it("suggests only authenticated-company data and does not invent representative email", async () => {
    const result = await service.getDraft(user("company-a"));
    expect(findDraft).toHaveBeenCalledWith(expect.objectContaining({ where: { companyId: "company-a" } }));
    expect(findCompany).toHaveBeenCalledWith(expect.objectContaining({ where: { id: "company-a" } }));
    expect(findConfig).toHaveBeenCalledWith(expect.objectContaining({ where: { companyId: "company-a" } }));
    expect(result.suggested).toEqual({
      company: { rnc: "131000001", legalName: "Empresa Canónica", address: "Calle Fiscal" },
      representative: { fullName: "Ana Pérez", identification: "00100000001" },
    });
    expect(result.missingFields).toContain("representative.email");
  });

  it("keeps a previously saved draft separate from current suggestions", async () => {
    const saved = { company: { address: "Dirección del expediente" } };
    findDraft.mockResolvedValue({
      draftPayload: saved,
      draftRevision: 2,
      currentSnapshotVersion: 0,
      state: "PREPARING_REQUIREMENTS",
    });
    const result = await service.getDraft(user("company-b"));
    expect(result.draft).toEqual(saved);
    expect(result.suggested.company.address).toBe("Calle Fiscal");
    expect(findConfig).toHaveBeenCalledWith(expect.objectContaining({ where: { companyId: "company-b" } }));
  });

  it("refuses to overwrite a submitted application", async () => {
    upsert.mockResolvedValue({ state: "APPLICATION_PENDING", draftRevision: 1 });
    await expect(service.saveDraft(user("company-a"), {
      payload: { company: {} },
      expectedRevision: 1,
    })).rejects.toThrow("ECF_DGII_TRANSITION_NOT_ALLOWED");
    expect(transaction).not.toHaveBeenCalled();
  });

  it("scopes consent history to the authenticated company", async () => {
    findSnapshots.mockResolvedValue([]);
    await service.listSnapshots(user("company-a"));
    await service.listSnapshots(user("company-b"));
    expect(findSnapshots).toHaveBeenNthCalledWith(1, expect.objectContaining({
      where: { companyId: "company-a" },
      select: expect.objectContaining({ consentVersion: true, consentAcceptedAt: true, submittedByUserId: true }),
    }));
    expect(findSnapshots).toHaveBeenNthCalledWith(2, expect.objectContaining({
      where: { companyId: "company-b" },
    }));
  });
});
