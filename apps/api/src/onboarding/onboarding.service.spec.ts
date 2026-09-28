import { OnboardingService } from "./onboarding.service";

describe("OnboardingService", () => {
  function buildService(companyOverrides: Record<string, unknown> = {}) {
    const company = {
      id: "company-a",
      name: "Company A",
      licenseStatus: "TRIAL",
      trialStartedAt: new Date("2026-09-27T00:00:00.000Z"),
      trialEndsAt: new Date("2026-10-04T00:00:00.000Z"),
      taxEnabled: false,
      pricesIncludeTax: false,
      ncfEnabled: false,
      onboardingRequired: false,
      onboardingStatus: "NOT_REQUIRED",
      onboardingCompanyStep: "SKIPPED",
      onboardingBillingStep: "SKIPPED",
      onboardingProductStep: "SKIPPED",
      onboardingReadyStep: "SKIPPED",
      onboardingStartedAt: null,
      onboardingCompletedAt: null,
      onboardingSkippedAt: null,
      tutorialStatus: "NOT_REQUIRED",
      tutorialCompletedAt: null,
      tutorialSkippedAt: null,
      ...companyOverrides,
    };
    const prisma = {
      company: {
        findUniqueOrThrow: jest.fn().mockResolvedValue(company),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      appConfig: {
        findFirst: jest.fn().mockResolvedValue({
          companyName: "Company A",
          rnc: "",
          phone: "8090000000",
          address: "",
          websiteUrl: "",
        }),
      },
      product: {
        count: jest.fn().mockResolvedValue(0),
      },
    };

    return { service: new OnboardingService(prisma as any), prisma };
  }

  it("keeps existing companies out of automatic onboarding", async () => {
    const { service } = buildService();

    const state = await service.getState({
      id: "user-a",
      role: "ADMIN",
      companyId: "company-a",
    });

    expect(state.required).toBe(false);
    expect(state.shouldShowWelcome).toBe(false);
    expect(state.status).toBe("NOT_REQUIRED");
  });

  it("scopes reads to the authenticated company", async () => {
    const { service, prisma } = buildService({
      onboardingRequired: true,
      onboardingStatus: "WELCOME_PENDING",
    });

    await service.getState({
      id: "user-a",
      role: "ADMIN",
      companyId: "company-a",
    });

    expect(prisma.company.findUniqueOrThrow).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: "company-a" } }),
    );
    expect(prisma.appConfig.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({ where: { companyId: "company-a" } }),
    );
    expect(prisma.product.count).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { companyId: "company-a", archivedAt: null },
      }),
    );
  });

  it("records full skip without marking individual steps completed", async () => {
    const { service, prisma } = buildService({
      onboardingRequired: true,
      onboardingStatus: "WELCOME_PENDING",
    });

    await service.skipAll({
      id: "user-a",
      role: "ADMIN",
      companyId: "company-a",
    });

    expect(prisma.company.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: "company-a", onboardingRequired: true },
        data: expect.objectContaining({
          onboardingStatus: "SKIPPED",
          onboardingCompanyStep: "SKIPPED",
          onboardingBillingStep: "SKIPPED",
          onboardingProductStep: "SKIPPED",
          onboardingReadyStep: "SKIPPED",
        }),
      }),
    );
  });
});
