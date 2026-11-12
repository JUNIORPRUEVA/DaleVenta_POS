import { BadRequestException } from "@nestjs/common";
import { OnboardingService } from "./onboarding.service";
import { ACTIVATION_TASKS } from "./activation.catalog";

/**
 * Pruebas del onboarding de activación «Activa tu FullPOS».
 *
 * Lo importante que se demuestra aquí:
 *  - el estado "completada" se DERIVA de datos reales, no de una bandera;
 *  - omitir una tarea NO la marca como completada;
 *  - toda consulta y escritura queda acotada al tenant del token.
 */
describe("OnboardingService — activación", () => {
  type Signals = {
    company?: Record<string, unknown>;
    appConfig?: Record<string, unknown> | null;
    productCount?: number;
    saleCount?: number;
    logoRows?: number;
    ecfConfig?: {
      enabled: boolean;
      certificationStatus: string;
      productionEnabled: boolean;
    } | null;
    habilitation?: { state: string } | null;
    overrides?: Array<Record<string, unknown>>;
  };

  const TENANT_A = { id: "user-a", role: "ADMIN", companyId: "company-a" };
  const TENANT_B = { id: "user-b", role: "ADMIN", companyId: "company-b" };

  function buildService(signals: Signals = {}) {
    const company = {
      id: "company-a",
      name: "Company A",
      taxEnabled: false,
      ncfEnabled: false,
      activationWelcomeSeenAt: null,
      activationDismissedAt: null,
      onboardingRequired: false,
      onboardingStatus: "NOT_REQUIRED",
      ...signals.company,
    };
    const prisma = {
      company: {
        findUniqueOrThrow: jest.fn().mockResolvedValue(company),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      appConfig: {
        findFirst: jest
          .fn()
          .mockResolvedValue(
            signals.appConfig === undefined
              ? { companyName: "", rnc: "", phone: "" }
              : signals.appConfig,
          ),
        count: jest.fn().mockResolvedValue(signals.logoRows ?? 0),
      },
      product: { count: jest.fn().mockResolvedValue(signals.productCount ?? 0) },
      sale: { count: jest.fn().mockResolvedValue(signals.saleCount ?? 0) },
      ecfCompanyConfiguration: {
        findFirst: jest.fn().mockResolvedValue(signals.ecfConfig ?? null),
      },
      ecfDgiiHabilitation: {
        findFirst: jest
          .fn()
          .mockResolvedValue(signals.habilitation ?? null),
      },
      companyOnboardingTask: {
        findMany: jest.fn().mockResolvedValue(signals.overrides ?? []),
        findUnique: jest.fn().mockResolvedValue(null),
        upsert: jest.fn().mockResolvedValue({}),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
    };
    return { service: new OnboardingService(prisma as any), prisma, company };
  }

  function taskOf(state: any, key: string) {
    const task = state.tasks.find((t: any) => t.key === key);
    if (!task) throw new Error(`Tarea ${key} no encontrada`);
    return task;
  }

  it("declara siete tareas repartidas en dos fases", () => {
    expect(ACTIVATION_TASKS).toHaveLength(7);
    expect(ACTIVATION_TASKS.filter((t) => t.phase === "sell")).toHaveLength(3);
    expect(ACTIVATION_TASKS.filter((t) => t.phase === "customize")).toHaveLength(4);
  });

  it("una empresa recién creada solo tiene la cuenta como completada", async () => {
    const { service } = buildService();

    const state = await service.getActivation(TENANT_A as any);

    expect(taskOf(state, "account").state).toBe("DONE");
    expect(taskOf(state, "products").state).toBe("PENDING");
    expect(taskOf(state, "firstSale").state).toBe("PENDING");
    expect(state.progress.done).toBe(1);
    expect(state.progress.total).toBe(7);
    expect(state.progress.pending).toBe(6);
    expect(state.nextTaskKey).toBe("products");
    expect(state.allResolved).toBe(false);
  });

  it("deriva la tarea de productos del recuento real de productos", async () => {
    const { service } = buildService({ productCount: 3 });

    const state = await service.getActivation(TENANT_A as any);

    expect(taskOf(state, "products").state).toBe("DONE");
    expect(state.progress.done).toBe(2);
    expect(state.nextTaskKey).toBe("firstSale");
  });

  it("deriva la primera venta del recuento real de ventas", async () => {
    const { service } = buildService({ productCount: 1, saleCount: 1 });

    const state = await service.getActivation(TENANT_A as any);

    expect(taskOf(state, "firstSale").state).toBe("DONE");
    expect(state.phases.find((p: any) => p.key === "sell")!.complete).toBe(true);
  });

  it("no da por hechos los datos del negocio si falta el nombre comercial", async () => {
    const { service } = buildService({
      appConfig: { companyName: "", rnc: "", phone: "" },
    } as any);

    const state = await service.getActivation(TENANT_A as any);

    expect(taskOf(state, "business").state).toBe("PENDING");
  });

  it("da por hechos los datos del negocio en cuanto el nombre comercial está guardado", async () => {
    const { service } = buildService({
      appConfig: { companyName: "Ferretería QA", rnc: "", phone: "" },
    });

    const state = await service.getActivation(TENANT_A as any);

    // El RNC se exige al emitir comprobantes fiscales, no para avanzar aquí.
    expect(taskOf(state, "business").state).toBe("DONE");
  });

  it("también lo da por hecho con nombre, RNC y teléfono", async () => {
    const { service } = buildService({
      appConfig: { companyName: "Ferretería QA", rnc: "131-12345-6", phone: "" },
    });

    const state = await service.getActivation(TENANT_A as any);

    expect(taskOf(state, "business").state).toBe("DONE");
  });

  it("no marca la facturación electrónica sin comprobantes fiscales habilitados", async () => {
    const { service } = buildService({ company: { ncfEnabled: false } });

    const state = await service.getActivation(TENANT_A as any);

    expect(taskOf(state, "ecf").state).toBe("PENDING");
    expect(taskOf(state, "ecf").detail).toContain("NCF");
  });

  it("informa la etapa de configuración cuando falta habilitar la e-CF", async () => {
    const { service } = buildService({
      company: { ncfEnabled: true },
      ecfConfig: null,
    });

    const state = await service.getActivation(TENANT_A as any);

    expect(taskOf(state, "ecf").state).toBe("PENDING");
    expect(taskOf(state, "ecf").detail).toContain("Configuración fiscal");
  });

  it("informa la etapa de habilitación DGII cuando aún no está aprobada", async () => {
    const { service } = buildService({
      company: { ncfEnabled: true },
      ecfConfig: {
        enabled: true,
        certificationStatus: "NOT_STARTED",
        productionEnabled: false,
      },
      habilitation: { state: "IN_CERTIFICATION" },
    });

    const state = await service.getActivation(TENANT_A as any);

    expect(taskOf(state, "ecf").state).toBe("PENDING");
    expect(taskOf(state, "ecf").detail).toContain("Habilitación DGII");
    expect(taskOf(state, "ecf").detail).toContain("en certificación");
  });

  it("informa la etapa de certificación cuando la DGII ya aprobó", async () => {
    const { service } = buildService({
      company: { ncfEnabled: true },
      ecfConfig: {
        enabled: true,
        certificationStatus: "AUTHORIZED_SANDBOX",
        productionEnabled: false,
      },
      habilitation: { state: "APPROVED" },
    });

    const state = await service.getActivation(TENANT_A as any);

    expect(taskOf(state, "ecf").state).toBe("PENDING");
    expect(taskOf(state, "ecf").detail).toContain("Certificación");
    expect(taskOf(state, "ecf").detail).toContain("sandbox");
  });

  it("da la facturación electrónica por completada solo con producción lista", async () => {
    const { service } = buildService({
      company: { ncfEnabled: true },
      ecfConfig: {
        enabled: true,
        certificationStatus: "PRODUCTION_READY",
        productionEnabled: true,
      },
      habilitation: { state: "APPROVED" },
    });

    const state = await service.getActivation(TENANT_A as any);

    expect(taskOf(state, "ecf").state).toBe("DONE");
    expect(taskOf(state, "ecf").detail).toBeNull();
  });

  it("no da por subido el logo cuando la columna existe pero está vacía", async () => {
    const { service, prisma } = buildService({ logoRows: 0 });

    const state = await service.getActivation(TENANT_A as any);

    expect(taskOf(state, "tickets").state).toBe("PENDING");
    const where = prisma.appConfig.count.mock.calls[0][0].where;
    expect(where.AND).toEqual([
      { logoBase64: { not: null } },
      { logoBase64: { not: "" } },
    ]);
  });

  it("da por subido el logo cuando hay una imagen guardada", async () => {
    const { service } = buildService({ logoRows: 1 });

    const state = await service.getActivation(TENANT_A as any);

    expect(taskOf(state, "tickets").state).toBe("DONE");
  });

  it("omitir una tarea la deja SKIPPED y nunca DONE", async () => {
    const { service, prisma } = buildService({ productCount: 0 });

    const state = await service.skipActivationTask(TENANT_A as any, "products");

    expect(prisma.companyOnboardingTask.upsert).toHaveBeenCalledTimes(1);
    const payload = prisma.companyOnboardingTask.upsert.mock.calls[0][0];
    expect(payload.create.status).toBe("SKIPPED");
    expect(payload.create.status).not.toBe("DONE");
    expect(payload.create.companyId).toBe("company-a");
    expect(state).toBeDefined();
  });

  it("al omitir, la tarea sigue sin contar como completada", async () => {
    const { service } = buildService({
      overrides: [{ taskKey: "products", status: "SKIPPED", tourStep: 0 }],
    });

    const state = await service.getActivation(TENANT_A as any);

    expect(taskOf(state, "products").state).toBe("SKIPPED");
    expect(state.progress.done).toBe(1);
    expect(state.progress.skipped).toBe(1);
    // Sigue pendiente la primera venta, así que hay siguiente tarea.
    expect(state.nextTaskKey).toBe("firstSale");
  });

  it("los datos reales mandan sobre una omisión previa", async () => {
    const { service } = buildService({
      productCount: 5,
      overrides: [{ taskKey: "products", status: "SKIPPED", tourStep: 0 }],
    });

    const state = await service.getActivation(TENANT_A as any);

    expect(taskOf(state, "products").state).toBe("DONE");
    expect(state.progress.skipped).toBe(0);
  });

  it("rechaza omitir una tarea obligatoria", async () => {
    const { service } = buildService();

    await expect(
      service.skipActivationTask(TENANT_A as any, "account"),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it("rechaza omitir una tarea que ya está completada por datos", async () => {
    const { service } = buildService({ productCount: 2 });

    await expect(
      service.skipActivationTask(TENANT_A as any, "products"),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it("rechaza claves de tarea desconocidas", async () => {
    const { service } = buildService();

    await expect(
      service.skipActivationTask(TENANT_A as any, "no-existe"),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it("restaurar una omisión vuelve a dejarla pendiente", async () => {
    const { service, prisma } = buildService();

    await service.restoreActivationTask(TENANT_A as any, "products");

    const call = prisma.companyOnboardingTask.updateMany.mock.calls[0][0];
    expect(call.where).toEqual({ companyId: "company-a", taskKey: "products" });
    expect(call.data.status).toBe("PENDING");
  });

  it("acota el avance del recorrido al número real de pasos", async () => {
    const { service, prisma } = buildService();

    await service.setActivationTour(TENANT_A as any, "products", 99);

    const payload = prisma.companyOnboardingTask.upsert.mock.calls[0][0];
    expect(payload.create.tourStep).toBe(2);
    expect(payload.create.tourSeenAt).toBeInstanceOf(Date);
  });

  it("no marca el recorrido como visto mientras no se termina", async () => {
    const { service, prisma } = buildService();

    await service.setActivationTour(TENANT_A as any, "products", 1);

    const payload = prisma.companyOnboardingTask.upsert.mock.calls[0][0];
    expect(payload.create.tourStep).toBe(1);
    expect(payload.create.tourSeenAt).toBeUndefined();
  });

  it("rechaza pasos de recorrido negativos o no numéricos", async () => {
    const { service } = buildService();

    await expect(
      service.setActivationTour(TENANT_A as any, "products", -1),
    ).rejects.toBeInstanceOf(BadRequestException);
    await expect(
      service.setActivationTour(TENANT_A as any, "products", "abc"),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it("marca la bienvenida como vista sin duplicar la escritura", async () => {
    const { service, prisma } = buildService();

    await service.markActivationWelcomeSeen(TENANT_A as any);

    const call = prisma.company.updateMany.mock.calls[0][0];
    expect(call.where).toEqual({
      id: "company-a",
      activationWelcomeSeenAt: null,
    });
    expect(call.data.activationWelcomeSeenAt).toBeInstanceOf(Date);
  });

  it("acota todas las consultas al tenant del token", async () => {
    const { service, prisma } = buildService();

    await service.getActivation(TENANT_B as any);

    expect(prisma.product.count.mock.calls[0][0].where.companyId).toBe(
      "company-b",
    );
    expect(prisma.sale.count.mock.calls[0][0].where).toEqual({
      companyId: "company-b",
      isDeleted: false,
    });
    expect(prisma.appConfig.count.mock.calls[0][0].where.companyId).toBe(
      "company-b",
    );
    expect(prisma.ecfCompanyConfiguration.findFirst.mock.calls[0][0].where).toEqual(
      { companyId: "company-b" },
    );
    expect(prisma.companyOnboardingTask.findMany.mock.calls[0][0].where).toEqual({
      companyId: "company-b",
    });
  });

  it("omitir todas las opcionales no declara el flujo resuelto mientras falte una obligatoria", async () => {
    const { service } = buildService({
      overrides: [
        { taskKey: "products", status: "SKIPPED", tourStep: 0 },
        { taskKey: "firstSale", status: "SKIPPED", tourStep: 0 },
        { taskKey: "taxes", status: "SKIPPED", tourStep: 0 },
        { taskKey: "tickets", status: "SKIPPED", tourStep: 0 },
        { taskKey: "ecf", status: "SKIPPED", tourStep: 0 },
      ],
    });

    const state = await service.getActivation(TENANT_A as any);

    // "business" es obligatoria: no se puede omitir, así que el flujo no puede
    // darse por resuelto aunque el usuario haya omitido todo lo demás.
    expect(state.allResolved).toBe(false);
    expect(state.progress.done).toBe(1);
    expect(state.progress.skipped).toBe(5);
    expect(state.progress.pending).toBe(1);
    expect(state.nextTaskKey).toBe("business");
  });
});
