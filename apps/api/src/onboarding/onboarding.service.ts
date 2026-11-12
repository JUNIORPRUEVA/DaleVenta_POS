import { BadRequestException, Injectable } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { requireTenant, type TenantUser } from "../auth/tenant-context";
import { PrismaService } from "../prisma/prisma.service";
import {
  ONBOARDING_STATUS,
  ONBOARDING_STEP_STATUS,
  TUTORIAL_STATUS,
  WELCOME_BUSINESS_AGE_RANGES,
  WELCOME_BUSINESS_SIZES,
  WELCOME_BUSINESS_TYPES,
  type OnboardingStepKey,
  type WelcomeProfileInput,
  shouldRequireOnboarding,
} from "./onboarding.constants";
import {
  ACTIVATION_PHASES,
  ACTIVATION_TASKS,
  ACTIVATION_TASK_BY_KEY,
  ACTIVATION_TASK_STATE,
  isActivationTaskKey,
  type ActivationTaskDefinition,
  type ActivationTaskKey,
  type ActivationTaskState,
} from "./activation.catalog";

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

  /** Valida una respuesta de la bienvenida contra la lista permitida. */
  private assertWelcomeOption<T extends string>(
    values: readonly T[],
    raw: unknown,
    label: string,
  ): T {
    const text = typeof raw === "string" ? raw.trim() : "";
    if (!values.includes(text as T)) {
      throw new BadRequestException(`Selecciona una opcion valida de ${label}`);
    }
    return text as T;
  }

  /**
   * Respuestas de la pantalla de bienvenida de la empresa autenticada.
   *
   * Solo lectura de `AppConfig`; nunca crea ni modifica plan, licencia,
   * almacenes, cajas, permisos o trial.
   */
  async getWelcomeProfile(user: TenantUser) {
    const companyId = requireTenant(user);
    const [company, appConfig] = await Promise.all([
      this.prisma.company.findUniqueOrThrow({
        where: { id: companyId },
        select: { id: true, name: true },
      }),
      this.prisma.appConfig.findFirst({
        where: { companyId },
        select: {
          companyName: true,
          businessType: true,
          businessAgeRange: true,
          businessSize: true,
          welcomeCompletedAt: true,
        },
      }),
    ]);

    return {
      companyId,
      companyName: (appConfig?.companyName ?? "").trim() || company.name,
      businessType: appConfig?.businessType ?? "",
      businessAgeRange: appConfig?.businessAgeRange ?? "",
      businessSize: appConfig?.businessSize ?? "",
      completedAt: appConfig?.welcomeCompletedAt ?? null,
      requiresWelcome: appConfig?.welcomeCompletedAt == null,
      options: {
        businessTypes: WELCOME_BUSINESS_TYPES,
        businessAgeRanges: WELCOME_BUSINESS_AGE_RANGES,
        businessSizes: WELCOME_BUSINESS_SIZES,
      },
    };
  }

  /**
   * Guarda las respuestas de la bienvenida una sola vez por empresa.
   *
   * Idempotente: un segundo envio actualiza la misma fila de `AppConfig`
   * (clave unica `companyId`) y conserva la fecha original de finalizacion,
   * de modo que nunca se duplican registros ni se reinicia el estado.
   */
  async saveWelcomeProfile(user: TenantUser, input: WelcomeProfileInput) {
    const companyId = requireTenant(user);

    const businessType = this.assertWelcomeOption(
      WELCOME_BUSINESS_TYPES,
      input?.businessType,
      "tipo de negocio",
    );
    const businessAgeRange = this.assertWelcomeOption(
      WELCOME_BUSINESS_AGE_RANGES,
      input?.businessAgeRange,
      "tiempo del negocio",
    );
    const businessSize = this.assertWelcomeOption(
      WELCOME_BUSINESS_SIZES,
      input?.businessSize,
      "tamano del negocio",
    );

    const existing = await this.prisma.appConfig.findFirst({
      where: { companyId },
      select: { welcomeCompletedAt: true },
    });
    const completedAt = existing?.welcomeCompletedAt ?? new Date();

    await this.prisma.appConfig.upsert({
      where: { companyId },
      create: {
        id: `company_${companyId}`,
        companyId,
        businessType,
        businessAgeRange,
        businessSize,
        welcomeCompletedAt: completedAt,
      },
      update: {
        businessType,
        businessAgeRange,
        businessSize,
        welcomeCompletedAt: completedAt,
      },
    });

    return this.getWelcomeProfile(user);
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

  // ---------------------------------------------------------------------------
  // Onboarding de activación «Activa tu FullPOS»
  //
  // El estado de cada tarea se DERIVA de los datos reales de la empresa. La
  // tabla `company_onboarding_tasks` solo guarda overrides (omitir + avance del
  // recorrido). Así el progreso nunca puede mentir: si la empresa borra sus
  // productos, la tarea vuelve a quedar pendiente.
  //
  // Todas las consultas van filtradas por `companyId` obtenido de
  // `requireTenant`, de modo que ninguna empresa puede leer ni escribir el
  // estado de otra.
  // ---------------------------------------------------------------------------

  /** Señales reales usadas para deducir el estado de cada tarea. */
  private async readActivationSignals(companyId: string) {
    const [
      company,
      appConfig,
      productCount,
      saleCount,
      logoConfig,
      ecfConfiguration,
      habilitation,
    ] = await Promise.all([
      this.prisma.company.findUniqueOrThrow({
        where: { id: companyId },
        select: {
          id: true,
          name: true,
          taxEnabled: true,
          ncfEnabled: true,
          activationWelcomeSeenAt: true,
          activationDismissedAt: true,
          onboardingRequired: true,
          onboardingStatus: true,
        },
      }),
      this.prisma.appConfig.findFirst({
        where: { companyId },
        select: { companyName: true, rnc: true, phone: true },
      }),
      this.prisma.product.count({ where: { companyId, archivedAt: null } }),
      this.prisma.sale.count({ where: { companyId, isDeleted: false } }),
      // Un logo borrado puede quedar como cadena vacía: se exige no nulo Y no
      // vacío. Solo se comprueba presencia, nunca se transfiere el base64.
      this.prisma.appConfig.count({
        where: {
          companyId,
          AND: [{ logoBase64: { not: null } }, { logoBase64: { not: "" } }],
        },
      }),
      this.prisma.ecfCompanyConfiguration.findFirst({
        where: { companyId },
        select: {
          enabled: true,
          certificationStatus: true,
          productionEnabled: true,
        },
      }),
      this.prisma.ecfDgiiHabilitation.findFirst({
        where: { companyId },
        select: { state: true },
      }),
    ]);

    return {
      company,
      commercialName: (appConfig?.companyName ?? "").trim(),
      rnc: (appConfig?.rnc ?? "").trim(),
      phone: (appConfig?.phone ?? "").trim(),
      productCount,
      saleCount,
      hasLogo: logoConfig > 0,
      ecfConfiguration: ecfConfiguration,
      habilitationState: habilitation?.state ?? null,
    };
  }

  /**
   * Estado real del proceso de facturación electrónica.
   *
   * El proceso tiene tres etapas distintas y no se puede dar por terminado
   * solo con que exista una configuración: hace falta NCF habilitado,
   * configuración activa, habilitación APROBADA de la DGII y certificación en
   * producción. El detalle viaja al cliente para explicar en qué punto está.
   */
  private ecfStage(signals: {
    company: { ncfEnabled: boolean };
    ecfConfiguration: {
      enabled: boolean;
      certificationStatus: string;
      productionEnabled: boolean;
    } | null;
    habilitationState: string | null;
  }): { done: boolean; detail: string | null } {
    if (!signals.company.ncfEnabled) {
      return {
        done: false,
        detail: "Falta activar los comprobantes fiscales (NCF).",
      };
    }
    const configuration = signals.ecfConfiguration;
    if (!configuration || !configuration.enabled) {
      return {
        done: false,
        detail: "Configuración fiscal: falta habilitar la facturación electrónica.",
      };
    }
    if (signals.habilitationState !== "APPROVED") {
      return {
        done: false,
        detail: `Habilitación DGII: ${this.habilitationLabel(signals.habilitationState)}.`,
      };
    }
    if (
      !configuration.productionEnabled &&
      configuration.certificationStatus !== "PRODUCTION_READY"
    ) {
      return {
        done: false,
        detail: `Certificación: ${this.certificationLabel(configuration.certificationStatus)}.`,
      };
    }
    return { done: true, detail: null };
  }

  private habilitationLabel(state: string | null): string {
    switch (state) {
      case "PREPARING_REQUIREMENTS":
        return "preparando requisitos";
      case "APPLICATION_PENDING":
        return "solicitud pendiente";
      case "IN_PROGRESS":
        return "en proceso";
      case "TESTS_PENDING":
        return "pruebas pendientes";
      case "IN_CERTIFICATION":
        return "en certificación";
      case "REJECTED":
        return "rechazada";
      case "REQUIRES_CORRECTION":
        return "requiere correcciones";
      case "NOT_STARTED":
      case null:
      default:
        return "sin iniciar";
    }
  }

  private certificationLabel(status: string): string {
    switch (status) {
      case "IN_PROGRESS":
        return "en progreso";
      case "BLOCKED":
        return "bloqueada";
      case "READY_FOR_REVIEW":
        return "lista para revisión";
      case "AUTHORIZED_SANDBOX":
        return "autorizada solo en sandbox";
      case "SUSPENDED":
        return "suspendida";
      case "NOT_STARTED":
      default:
        return "sin iniciar";
    }
  }

  /** Regla de derivación por tarea. `true` = hecha. */
  private isTaskDoneFromData(
    key: ActivationTaskKey,
    signals: Awaited<ReturnType<OnboardingService["readActivationSignals"]>>,
  ): boolean {
    switch (key) {
      case "account":
        return true;
      case "products":
        return signals.productCount > 0;
      case "firstSale":
        return signals.saleCount > 0;
      case "business":
        // El nombre comercial es lo mínimo para dejar el negocio configurado:
        // en cuanto está guardado, el paso «Datos de tu empresa» se completa.
        // El RNC se sigue exigiendo al emitir comprobantes fiscales (e-CF), no
        // para avanzar en el asistente: no todos los negocios lo tienen.
        return signals.commercialName.length > 0;
      case "taxes":
        return signals.company.taxEnabled === true;
      case "tickets":
        return signals.hasLogo;
      case "ecf":
        return this.ecfStage(signals).done;
      default:
        return false;
    }
  }

  private async readOverrides(companyId: string) {
    return this.prisma.companyOnboardingTask.findMany({
      where: { companyId },
      select: {
        taskKey: true,
        status: true,
        tourStep: true,
        tourSeenAt: true,
        skippedAt: true,
        completedAt: true,
      },
    });
  }

  /**
   * Estado completo del onboarding de activación.
   *
   * Disponible para cualquier empresa autenticada: el panel se puede reabrir
   * en cualquier momento, no es un flujo de una sola vez.
   */
  async getActivation(user: TenantUser) {
    const companyId = requireTenant(user);
    const [signals, overrides] = await Promise.all([
      this.readActivationSignals(companyId),
      this.readOverrides(companyId),
    ]);

    const overrideByKey = new Map(
      overrides.map((row) => [row.taskKey, row] as const),
    );

    const buildTask = (definition: ActivationTaskDefinition) => {
      const override = overrideByKey.get(definition.key);
      const done = this.isTaskDoneFromData(definition.key, signals);
      const skipped = !done && override?.status === ACTIVATION_TASK_STATE.SKIPPED;

      const state: ActivationTaskState = done
        ? ACTIVATION_TASK_STATE.DONE
        : skipped
          ? ACTIVATION_TASK_STATE.SKIPPED
          : ACTIVATION_TASK_STATE.PENDING;

      // La facturación electrónica informa de la etapa exacta en la que está:
      // configuración fiscal, habilitación DGII o certificación.
      const detail =
        definition.key === "ecf" ? this.ecfStage(signals).detail : null;

      return {
        key: definition.key,
        phase: definition.phase,
        title: definition.title,
        description: definition.description,
        detail,
        minutes: definition.minutes,
        actionLabel: definition.actionLabel,
        destination: definition.destination,
        icon: definition.icon,
        optional: definition.optional,
        tourSteps: definition.tourSteps,
        state,
        tourStep: override?.tourStep ?? 0,
        tourSeen: override?.tourSeenAt != null,
        skippedAt: state === ACTIVATION_TASK_STATE.SKIPPED ? override?.skippedAt ?? null : null,
      };
    };

    const tasks = ACTIVATION_TASKS.map(buildTask);

    const phases = ACTIVATION_PHASES.map((phase) => {
      const phaseTasks = tasks.filter((task) => task.phase === phase.key);
      const done = phaseTasks.filter(
        (task) => task.state === ACTIVATION_TASK_STATE.DONE,
      ).length;
      const skipped = phaseTasks.filter(
        (task) => task.state === ACTIVATION_TASK_STATE.SKIPPED,
      ).length;
      return {
        key: phase.key,
        title: phase.title,
        subtitle: phase.subtitle,
        total: phaseTasks.length,
        done,
        skipped,
        resolved: done + skipped,
        // Una fase está resuelta cuando no le queda ninguna tarea pendiente,
        // sea porque se completó o porque el usuario la omitió.
        complete: done + skipped === phaseTasks.length,
        tasks: phaseTasks,
      };
    });

    const done = tasks.filter(
      (task) => task.state === ACTIVATION_TASK_STATE.DONE,
    ).length;
    const skipped = tasks.filter(
      (task) => task.state === ACTIVATION_TASK_STATE.SKIPPED,
    ).length;
    const total = tasks.length;
    const nextTask = tasks.find(
      (task) => task.state === ACTIVATION_TASK_STATE.PENDING,
    );

    return {
      companyId,
      required: shouldRequireOnboarding(signals.company),
      legacyStatus: signals.company.onboardingStatus,
      welcomeSeen: signals.company.activationWelcomeSeenAt != null,
      dismissed: signals.company.activationDismissedAt != null,
      progress: {
        total,
        done,
        skipped,
        pending: total - done - skipped,
        percent: total === 0 ? 100 : Math.round((done / total) * 100),
      },
      phases,
      tasks,
      nextTaskKey: nextTask?.key ?? null,
      allResolved: done + skipped === total,
      signals: {
        productCount: signals.productCount,
        saleCount: signals.saleCount,
        hasLogo: signals.hasLogo,
        taxEnabled: signals.company.taxEnabled,
        ncfEnabled: signals.company.ncfEnabled,
        ecfEnabled: signals.ecfConfiguration?.enabled === true,
        ecfCertificationStatus:
          signals.ecfConfiguration?.certificationStatus ?? null,
        dgiiHabilitationState: signals.habilitationState,
      },
    };
  }

  /** Marca que el usuario ya vio la bienvenida de activación. */
  async markActivationWelcomeSeen(user: TenantUser) {
    const companyId = requireTenant(user);
    await this.prisma.company.updateMany({
      where: { id: companyId, activationWelcomeSeenAt: null },
      data: { activationWelcomeSeenAt: new Date() },
    });
    return this.getActivation(user);
  }

  /** El usuario cerró el panel: no se reabre solo en el próximo inicio. */
  async dismissActivation(user: TenantUser) {
    const companyId = requireTenant(user);
    await this.prisma.company.updateMany({
      where: { id: companyId },
      data: { activationDismissedAt: new Date() },
    });
    return this.getActivation(user);
  }

  /** El usuario volvió a abrir el panel: se limpia la marca de cierre. */
  async reopenActivation(user: TenantUser) {
    const companyId = requireTenant(user);
    await this.prisma.company.updateMany({
      where: { id: companyId },
      data: { activationDismissedAt: null },
    });
    return this.getActivation(user);
  }

  /**
   * Omite una tarea opcional.
   *
   * Omitir NO marca la tarea como completada: el estado SKIPPED es explícito y
   * deja de contar como pendiente. Si la tarea era obligatoria o ya estaba
   * resuelta por datos, no se hace nada.
   */
  async skipActivationTask(user: TenantUser, rawKey: string) {
    const key = this.assertActivationTaskKey(rawKey);
    const companyId = requireTenant(user);

    const [signals, override] = await Promise.all([
      this.readActivationSignals(companyId),
      this.prisma.companyOnboardingTask.findUnique({
        where: { companyId_taskKey: { companyId, taskKey: key } },
        select: { status: true },
      }),
    ]);

    const definition = ACTIVATION_TASK_BY_KEY[key];
    if (!definition.optional) {
      throw new BadRequestException(
        "Esta tarea es obligatoria y no se puede omitir",
      );
    }
    if (this.isTaskDoneFromData(key, signals)) {
      throw new BadRequestException("Esta tarea ya esta completada");
    }
    if (override?.status === ACTIVATION_TASK_STATE.SKIPPED) {
      return this.getActivation(user);
    }

    const now = new Date();
    await this.prisma.companyOnboardingTask.upsert({
      where: { companyId_taskKey: { companyId, taskKey: key } },
      create: {
        companyId,
        taskKey: key,
        status: ACTIVATION_TASK_STATE.SKIPPED,
        skippedAt: now,
      },
      update: { status: ACTIVATION_TASK_STATE.SKIPPED, skippedAt: now },
    });

    return this.getActivation(user);
  }

  /** Deshace una omisión. */
  async restoreActivationTask(user: TenantUser, rawKey: string) {
    const key = this.assertActivationTaskKey(rawKey);
    const companyId = requireTenant(user);

    await this.prisma.companyOnboardingTask.updateMany({
      where: { companyId, taskKey: key },
      data: { status: ACTIVATION_TASK_STATE.PENDING, skippedAt: null },
    });

    return this.getActivation(user);
  }

  /** Persiste el avance de un recorrido guiado asociado a una tarea. */
  async setActivationTour(user: TenantUser, rawKey: string, rawStep: unknown) {
    const key = this.assertActivationTaskKey(rawKey);
    const companyId = requireTenant(user);

    const stepNumber = Number(rawStep);
    if (!Number.isFinite(stepNumber) || stepNumber < 0) {
      throw new BadRequestException("Paso de recorrido invalido");
    }
    const definition = ACTIVATION_TASK_BY_KEY[key];
    const step = Math.min(Math.floor(stepNumber), definition.tourSteps);
    const finished = step >= definition.tourSteps;
    const now = new Date();

    await this.prisma.companyOnboardingTask.upsert({
      where: { companyId_taskKey: { companyId, taskKey: key } },
      create: {
        companyId,
        taskKey: key,
        status: ACTIVATION_TASK_STATE.PENDING,
        tourStep: step,
        ...(finished ? { tourSeenAt: now } : {}),
      },
      update: {
        tourStep: step,
        ...(finished ? { tourSeenAt: now } : {}),
      },
    });

    return this.getActivation(user);
  }

  private assertActivationTaskKey(rawKey: string): ActivationTaskKey {
    const key = (rawKey ?? "").toString().trim();
    if (!isActivationTaskKey(key)) {
      throw new BadRequestException("Tarea de activacion invalida");
    }
    return key;
  }
}
