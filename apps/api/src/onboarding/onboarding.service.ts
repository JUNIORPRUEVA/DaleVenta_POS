import { BadRequestException, Injectable } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { requireTenant, type TenantUser } from "../auth/tenant-context";
import { PrismaService } from "../prisma/prisma.service";
import {
  ONBOARDING_STATUS,
  ONBOARDING_STEP_STATUS,
  TUTORIAL_STATUS,
  type OnboardingStepKey,
  shouldRequireOnboarding,
} from "./onboarding.constants";

const stepColumns: Record<OnboardingStepKey, string> = {
  company: "onboardingCompanyStep",
  billing: "onboardingBillingStep",
  product: "onboardingProductStep",
  ready: "onboardingReadyStep",
};

@Injectable()
export class OnboardingService {
  constructor(private readonly prisma: PrismaService) {}

  async getState(user: TenantUser) {
    const companyId = requireTenant(user);
    const [company, appConfig, productCount] = await Promise.all([
      this.prisma.company.findUniqueOrThrow({
        where: { id: companyId },
        select: {
          id: true,
          name: true,
          licenseStatus: true,
          trialStartedAt: true,
          trialEndsAt: true,
          taxEnabled: true,
          pricesIncludeTax: true,
          ncfEnabled: true,
          onboardingRequired: true,
          onboardingStatus: true,
          onboardingCompanyStep: true,
          onboardingBillingStep: true,
          onboardingProductStep: true,
          onboardingReadyStep: true,
          onboardingStartedAt: true,
          onboardingCompletedAt: true,
          onboardingSkippedAt: true,
          tutorialStatus: true,
          tutorialCompletedAt: true,
          tutorialSkippedAt: true,
        },
      }),
      this.prisma.appConfig.findFirst({
        where: { companyId },
        select: {
          companyName: true,
          rnc: true,
          phone: true,
          address: true,
          websiteUrl: true,
        },
      }),
      this.prisma.product.count({
        where: { companyId, archivedAt: null },
      }),
    ]);

    return {
      required: shouldRequireOnboarding(company),
      shouldShowWelcome:
        company.onboardingStatus === ONBOARDING_STATUS.WELCOME_PENDING,
      status: company.onboardingStatus,
      tutorialStatus: company.tutorialStatus,
      trial: {
        licenseStatus: company.licenseStatus,
        startedAt: company.trialStartedAt,
        endsAt: company.trialEndsAt,
      },
      steps: {
        company: company.onboardingCompanyStep,
        billing: company.onboardingBillingStep,
        product:
          productCount > 0
            ? ONBOARDING_STEP_STATUS.COMPLETED
            : company.onboardingProductStep,
        ready: company.onboardingReadyStep,
      },
      company: {
        id: company.id,
        name: company.name,
        commercialName: appConfig?.companyName || company.name,
        rnc: appConfig?.rnc ?? "",
        phone: appConfig?.phone ?? "",
        address: appConfig?.address ?? "",
        websiteUrl: appConfig?.websiteUrl ?? "",
        taxEnabled: company.taxEnabled,
        pricesIncludeTax: company.pricesIncludeTax,
        ncfEnabled: company.ncfEnabled,
      },
      productCount,
      timestamps: {
        onboardingStartedAt: company.onboardingStartedAt,
        onboardingCompletedAt: company.onboardingCompletedAt,
        onboardingSkippedAt: company.onboardingSkippedAt,
        tutorialCompletedAt: company.tutorialCompletedAt,
        tutorialSkippedAt: company.tutorialSkippedAt,
      },
    };
  }

  async start(user: TenantUser) {
    const companyId = requireTenant(user);
    await this.prisma.company.updateMany({
      where: { id: companyId, onboardingRequired: true },
      data: {
        onboardingStatus: ONBOARDING_STATUS.IN_PROGRESS,
        onboardingStartedAt: new Date(),
      },
    });
    return this.getState(user);
  }

  async skipAll(user: TenantUser) {
    const companyId = requireTenant(user);
    const now = new Date();
    await this.prisma.company.updateMany({
      where: { id: companyId, onboardingRequired: true },
      data: {
        onboardingStatus: ONBOARDING_STATUS.SKIPPED,
        onboardingSkippedAt: now,
        onboardingCompanyStep: ONBOARDING_STEP_STATUS.SKIPPED,
        onboardingBillingStep: ONBOARDING_STEP_STATUS.SKIPPED,
        onboardingProductStep: ONBOARDING_STEP_STATUS.SKIPPED,
        onboardingReadyStep: ONBOARDING_STEP_STATUS.SKIPPED,
        tutorialStatus: TUTORIAL_STATUS.PENDING,
      },
    });
    return this.getState(user);
  }

  async setStepStatus(
    user: TenantUser,
    step: string,
    status: string,
    completeFlow = false,
  ) {
    const normalizedStep = step.trim() as OnboardingStepKey;
    const column = stepColumns[normalizedStep];
    if (!column) {
      throw new BadRequestException("Paso de onboarding invalido");
    }

    const normalizedStatus = status.trim().toUpperCase();
    if (
      normalizedStatus !== ONBOARDING_STEP_STATUS.COMPLETED &&
      normalizedStatus !== ONBOARDING_STEP_STATUS.SKIPPED
    ) {
      throw new BadRequestException("Estado de paso invalido");
    }

    const companyId = requireTenant(user);
    const data: Prisma.CompanyUncheckedUpdateInput = {
      [column]: normalizedStatus,
      onboardingStatus: completeFlow
        ? ONBOARDING_STATUS.COMPLETED
        : ONBOARDING_STATUS.IN_PROGRESS,
      ...(completeFlow
        ? {
            onboardingCompletedAt: new Date(),
            tutorialStatus: TUTORIAL_STATUS.PENDING,
          }
        : {}),
    };

    await this.prisma.company.updateMany({
      where: { id: companyId, onboardingRequired: true },
      data,
    });
    return this.getState(user);
  }

  async setTutorial(user: TenantUser, status: string) {
    const normalizedStatus = status.trim().toUpperCase();
    if (
      normalizedStatus !== TUTORIAL_STATUS.STARTED &&
      normalizedStatus !== TUTORIAL_STATUS.COMPLETED &&
      normalizedStatus !== TUTORIAL_STATUS.SKIPPED
    ) {
      throw new BadRequestException("Estado de tutorial invalido");
    }

    const companyId = requireTenant(user);
    await this.prisma.company.updateMany({
      where: { id: companyId, onboardingRequired: true },
      data: {
        tutorialStatus: normalizedStatus,
        ...(normalizedStatus === TUTORIAL_STATUS.COMPLETED
          ? { tutorialCompletedAt: new Date() }
          : {}),
        ...(normalizedStatus === TUTORIAL_STATUS.SKIPPED
          ? { tutorialSkippedAt: new Date() }
          : {}),
      },
    });
    return this.getState(user);
  }
}
