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

  it("shows welcome only for WELCOME_PENDING companies", async () => {
    const { service } = buildService({
      onboardingRequired: true,
      onboardingStatus: "WELCOME_PENDING",
    });

    const state = await service.getState({
      id: "user-a",
      role: "ADMIN",
      companyId: "company-a",
    });

    expect(state.required).toBe(true);
    expect(state.shouldShowWelcome).toBe(true);
    expect(state.status).toBe("WELCOME_PENDING");
  });

  it("keeps IN_PROGRESS companies inside onboarding without returning to welcome", async () => {
    const { service } = buildService({
      onboardingRequired: true,
      onboardingStatus: "IN_PROGRESS",
    });

    const state = await service.getState({
      id: "user-a",
      role: "ADMIN",
      companyId: "company-a",
    });

    expect(state.required).toBe(true);
    expect(state.shouldShowWelcome).toBe(false);
    expect(state.status).toBe("IN_PROGRESS");
  });

  it("does not require onboarding after completed or full skip states", async () => {
    for (const status of ["COMPLETED", "SKIPPED", "NOT_REQUIRED"]) {
      const { service } = buildService({
        onboardingRequired: status !== "NOT_REQUIRED",
        onboardingStatus: status,
      });

      const state = await service.getState({
        id: "user-a",
        role: "ADMIN",
        companyId: "company-a",
      });

      expect(state.required).toBe(false);
      expect(state.shouldShowWelcome).toBe(false);
      expect(state.status).toBe(status);
    }
  });

  it("starts onboarding without clearing the active onboarding requirement", async () => {
    const { service, prisma } = buildService({
      onboardingRequired: true,
      onboardingStatus: "WELCOME_PENDING",
    });

    await service.start({
      id: "user-a",
      role: "ADMIN",
      companyId: "company-a",
    });

    expect(prisma.company.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: "company-a", onboardingRequired: true },
        data: expect.objectContaining({
          onboardingStatus: "IN_PROGRESS",
          onboardingStartedAt: expect.any(Date),
        }),
      }),
    );
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
