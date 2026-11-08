import { EcfCertificationStatus } from "@prisma/client";
import type { PrismaService } from "../../prisma/prisma.service";
import type { DosaActivationService } from "../provider/dosa/dosa-activation.service";
import type { DosaCredentialService } from "../provider/dosa/dosa-credential.service";
import { EcfCertificationActivationService } from "./ecf-certification-activation.service";

/**
 * Pruebas del servicio de activación y autorización SIN intervención de Fulltech.
 *
 * Se sustituyen las tres dependencias externas (base de datos, activación
 * fiscal y bóveda de credenciales) por dobles: lo que se prueba aquí son las
 * REGLAS —qué se activa, qué no se toca, cuándo se escribe el estado y qué se
 * audita—, no el SQL.
 *
 * El camino completo con base de datos real se prueba en
 * `ecf-certification-activation-http.e2e-spec.ts`.
 */
describe("EcfCertificationActivationService", () => {
  type Credential = { rnc: string; environment: string; status: string };

  function build(options: {
    config?: EcfCertificationStatus | null;
    credentialsBefore?: Credential[];
    credentialsAfter?: Credential[];
    activationOk?: boolean;
    activationBlockers?: string[];
  }) {
    const prisma = {
      ecfCompanyConfiguration: {
        findUnique: jest.fn().mockResolvedValue(
          options.config === null
            ? null
            : { certificationStatus: options.config ?? EcfCertificationStatus.NOT_STARTED },
        ),
        update: jest.fn().mockResolvedValue({}),
      },
      ecfAuditLog: { create: jest.fn().mockResolvedValue({}) },
      $transaction: jest.fn(),
    };
    prisma.$transaction.mockImplementation(async (fn: (tx: unknown) => unknown) => fn(prisma));

    const activation = {
      activate: jest.fn().mockResolvedValue(
        options.activationOk === false
          ? { ok: false, blockingReasons: options.activationBlockers ?? ["BLOQUEO"] }
          : { ok: true, status: "ACTIVE", evidence: {} },
      ),
    };

    const credentials = {
      listForCompany: jest
        .fn()
        .mockResolvedValueOnce(options.credentialsBefore ?? [])
        .mockResolvedValueOnce(options.credentialsAfter ?? options.credentialsBefore ?? []),
    };

    const service = new EcfCertificationActivationService(
      prisma as unknown as PrismaService,
      activation as unknown as DosaActivationService,
      credentials as unknown as DosaCredentialService,
    );

    return { service, prisma, activation, credentials };
  }

  it("sin configuración e-CF no activa ni escribe nada", async () => {
    const { service, prisma, activation } = build({
      config: null,
      credentialsBefore: [{ rnc: "101", environment: "test", status: "PENDING_CONFIRMATION" }],
    });

    const result = await service.attempt("company-a");

    expect(result.code).toBe("ECF_CERTIFICATION_CONFIGURATION_NOT_FOUND");
    expect(result.changed).toBe(false);
    expect(activation.activate).not.toHaveBeenCalled();
    expect(prisma.ecfCompanyConfiguration.update).not.toHaveBeenCalled();
  });

  it("activa la credencial pendiente y autoriza sandbox, sin actor humano", async () => {
    const { service, prisma, activation } = build({
      config: EcfCertificationStatus.IN_PROGRESS,
      credentialsBefore: [
        { rnc: "101", environment: "test", status: "PENDING_CONFIRMATION" },
      ],
      credentialsAfter: [{ rnc: "101", environment: "test", status: "ACTIVE" }],
    });

    const result = await service.attempt("company-a");

    // Se activó usando el RNC de la PROPIA credencial, no uno de otra tabla.
    expect(activation.activate).toHaveBeenCalledWith({
      companyId: "company-a",
      rnc: "101",
      environment: "test",
    });
    expect(result.ok).toBe(true);
    expect(result.changed).toBe(true);
    expect(result.certificationStatus).toBe(EcfCertificationStatus.AUTHORIZED_SANDBOX);

    expect(prisma.ecfCompanyConfiguration.update).toHaveBeenCalledWith({
      where: { companyId: "company-a" },
      data: { certificationStatus: EcfCertificationStatus.AUTHORIZED_SANDBOX },
    });
    expect(prisma.ecfAuditLog.create).toHaveBeenCalledTimes(1);
    const audit = prisma.ecfAuditLog.create.mock.calls[0][0].data;
    expect(audit).toMatchObject({
      companyId: "company-a",
      // El sistema no se atribuye la autorización a ninguna persona.
      actorUserId: null,
      before: { certificationStatus: "IN_PROGRESS" },
      after: { certificationStatus: "AUTHORIZED_SANDBOX" },
    });
    expect(audit.metadata).toMatchObject({
      operation: "CERTIFICATION_STATUS_DERIVED",
      derivedFrom: "DOSA_CREDENTIALS_ACTIVE",
    });
  });

  it("una credencial de producción activa autoriza producción", async () => {
    const { service } = build({
      config: EcfCertificationStatus.AUTHORIZED_SANDBOX,
      credentialsBefore: [
        { rnc: "101", environment: "production", status: "PENDING_CONFIRMATION" },
      ],
      credentialsAfter: [{ rnc: "101", environment: "production", status: "ACTIVE" }],
    });

    const result = await service.attempt("company-a");

    expect(result.certificationStatus).toBe(EcfCertificationStatus.PRODUCTION_READY);
  });

  it("una credencial REVOKED no se resucita ni se intenta activar", async () => {
    const { service, activation, prisma } = build({
      config: EcfCertificationStatus.IN_PROGRESS,
      credentialsBefore: [{ rnc: "101", environment: "test", status: "REVOKED" }],
      credentialsAfter: [{ rnc: "101", environment: "test", status: "REVOKED" }],
    });

    const result = await service.attempt("company-a");

    expect(activation.activate).not.toHaveBeenCalled();
    expect(result.environments[0]).toMatchObject({
      environment: "test",
      status: "REVOKED",
      activated: false,
      blockingReasons: ["ECF_DOSA_CREDENTIALS_REVOKED"],
    });
    expect(prisma.ecfCompanyConfiguration.update).not.toHaveBeenCalled();
  });

  it("si falta evidencia, propaga qué falta y no escribe estado", async () => {
    const { service, prisma } = build({
      config: EcfCertificationStatus.IN_PROGRESS,
      credentialsBefore: [{ rnc: "101", environment: "test", status: "PENDING_CONFIRMATION" }],
      credentialsAfter: [{ rnc: "101", environment: "test", status: "PENDING_CONFIRMATION" }],
      activationOk: false,
      activationBlockers: ["ECF_DOSA_ACTIVATION_DGII_NOT_APPROVED"],
    });

    const result = await service.attempt("company-a");

    expect(result.ok).toBe(false);
    expect(result.changed).toBe(false);
    expect(result.environments[0].blockingReasons).toEqual([
      "ECF_DOSA_ACTIVATION_DGII_NOT_APPROVED",
    ]);
    // El cliente conserva su estado anterior: no autorizar no es degradar.
    expect(result.certificationStatus).toBe(EcfCertificationStatus.IN_PROGRESS);
    expect(prisma.ecfCompanyConfiguration.update).not.toHaveBeenCalled();
  });

  it("no salta un bloqueo aunque la credencial se active", async () => {
    const { service, prisma } = build({
      config: EcfCertificationStatus.BLOCKED,
      credentialsBefore: [{ rnc: "101", environment: "test", status: "PENDING_CONFIRMATION" }],
      credentialsAfter: [{ rnc: "101", environment: "test", status: "ACTIVE" }],
    });

    const result = await service.attempt("company-a");

    expect(result.code).toBe("ECF_CERTIFICATION_STATE_BLOCKED");
    expect(result.changed).toBe(false);
    expect(result.certificationStatus).toBe(EcfCertificationStatus.BLOCKED);
    expect(prisma.ecfCompanyConfiguration.update).not.toHaveBeenCalled();
  });

  it("no levanta una suspensión: eso exige una decisión administrativa", async () => {
    const { service, prisma } = build({
      config: EcfCertificationStatus.SUSPENDED,
      credentialsBefore: [{ rnc: "101", environment: "test", status: "PENDING_CONFIRMATION" }],
      credentialsAfter: [{ rnc: "101", environment: "test", status: "ACTIVE" }],
    });

    const result = await service.attempt("company-a");

    expect(result.certificationStatus).toBe(EcfCertificationStatus.SUSPENDED);
    expect(result.changed).toBe(false);
    expect(prisma.ecfCompanyConfiguration.update).not.toHaveBeenCalled();
  });

  it("es idempotente: repetirlo no reescribe ni duplica auditoría", async () => {
    const { service, prisma, activation } = build({
      config: EcfCertificationStatus.AUTHORIZED_SANDBOX,
      credentialsBefore: [{ rnc: "101", environment: "test", status: "ACTIVE" }],
      credentialsAfter: [{ rnc: "101", environment: "test", status: "ACTIVE" }],
    });

    const result = await service.attempt("company-a");

    expect(activation.activate).not.toHaveBeenCalled();
    expect(result.changed).toBe(false);
    expect(result.certificationStatus).toBe(EcfCertificationStatus.AUTHORIZED_SANDBOX);
    expect(prisma.ecfCompanyConfiguration.update).not.toHaveBeenCalled();
    expect(prisma.ecfAuditLog.create).not.toHaveBeenCalled();
  });

  it("sin credenciales registradas no autoriza nada", async () => {
    const { service, prisma } = build({
      config: EcfCertificationStatus.NOT_STARTED,
      credentialsBefore: [],
      credentialsAfter: [],
    });

    const result = await service.attempt("company-a");

    expect(result.ok).toBe(false);
    expect(result.changed).toBe(false);
    expect(result.environments).toEqual([]);
    expect(prisma.ecfCompanyConfiguration.update).not.toHaveBeenCalled();
  });

  it("attemptSafely nunca propaga un fallo", async () => {
    const { service, credentials } = build({ config: EcfCertificationStatus.NOT_STARTED });
    credentials.listForCompany.mockReset();
    credentials.listForCompany.mockRejectedValue(new Error("db down"));

    await expect(service.attemptSafely("company-a")).resolves.toBeNull();
  });

  it("no permite evaluar sin empresa", async () => {
    const { service } = build({ config: EcfCertificationStatus.NOT_STARTED });
    const result = await service.attempt("  ");
    expect(result.code).toBe("COMPANY_REQUIRED");
  });
});
