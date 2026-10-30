import { randomUUID } from "node:crypto";
import { ConfigService } from "@nestjs/config";
import { isEcfLocalTarget } from "../ecf-local-target";
import { PrismaService } from "../../prisma/prisma.service";
import type { TenantUser } from "../../auth/tenant-context";
import { EcfDgiiHabilitationService } from "./ecf-dgii-habilitation.service";

/**
 * Habilitación DGII por empresa — integración real con PostgreSQL.
 *
 * Opt-in: solo corre contra una base local autorizada (efímera de pruebas). No
 * contacta a la DGII, no contacta a Alanube y no emite nada.
 */
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

function configWith(values: Record<string, string>): ConfigService {
  return { get: (key: string) => values[key] } as unknown as ConfigService;
}

const LOCAL_UAT = configWith({ APP_ENV: "uat" });

uat("E-CF habilitación DGII por empresa — PostgreSQL", () => {
  let prisma: PrismaService;
  let service: EcfDgiiHabilitationService;
  const createdCompanies: string[] = [];
  const actor = randomUUID();

  beforeAll(async () => {
    if (!isEcfLocalTarget()) throw new Error("ECF_DGII_HABILITATION_UAT_REFUSED");
    prisma = new PrismaService();
    await prisma.$connect();
    service = new EcfDgiiHabilitationService(prisma, LOCAL_UAT);
  });

  afterAll(async () => {
    if (createdCompanies.length > 0) {
      await prisma.ecfDgiiHabilitation.deleteMany({
        where: { companyId: { in: createdCompanies } },
      });
      await prisma.company.deleteMany({ where: { id: { in: createdCompanies } } });
    }
    await prisma?.$disconnect();
  });

  async function tenant(name: string) {
    const companyId = randomUUID();
    await prisma.company.create({
      data: { id: companyId, name, slug: `dgii-hab-${companyId}` },
    });
    createdCompanies.push(companyId);
    return { companyId, user: { id: actor, role: "ADMIN", companyId } as TenantUser };
  }

  async function setSteps(
    companyId: string,
    steps: { stepKey: string; status: string }[],
  ) {
    for (const step of steps) {
      await prisma.ecfOnboardingStep.create({
        data: {
          companyId,
          stepKey: step.stepKey as never,
          status: step.status as never,
        },
      });
    }
  }

  it("crea el registro al consultar, sin conceder ninguna autorización", async () => {
    const { companyId, user } = await tenant("Synthetic DGII untouched");
    const view = await service.getHabilitation(user);

    expect(view.companyId).toBe(companyId);
    expect(view.state).toBe("NOT_STARTED");
    expect(view.officialAuthorization).toBe(false);
    expect(view.authorizedAt).toBeNull();
    expect(view.isInternalTrackingOnly).toBe(true);
    // Sin condiciones cumplidas, la emisión real no está autorizada.
    expect(view.emission.realEmissionAuthorized).toBe(false);
    expect(view.emission.productionEmissionImplemented).toBe(false);
  });

  it("aísla los datos entre empresas: A no ve nada de B", async () => {
    const a = await tenant("Synthetic DGII A");
    const b = await tenant("Synthetic DGII B");

    await service.updateHabilitation(a.user, {
      state: "PREPARING_REQUIREMENTS",
      observations: "Observación privada de A",
      reviewState: "revision-a",
    });

    const viewA = await service.getHabilitation(a.user);
    const viewB = await service.getHabilitation(b.user);

    expect(viewA.observations).toBe("Observación privada de A");
    expect(viewA.reviewState).toBe("revision-a");
    expect(viewA.state).toBe("PREPARING_REQUIREMENTS");

    expect(viewB.companyId).toBe(b.companyId);
    expect(viewB.observations).toBeNull();
    expect(viewB.reviewState).toBeNull();
    expect(viewB.state).toBe("NOT_STARTED");

    // Ni el historial ni las evidencias cruzan la frontera de empresa.
    const historyB = await service.listHistory(b.user);
    expect(historyB).toHaveLength(0);
    const aRows = await prisma.ecfDgiiHabilitation.findMany({
      where: { companyId: { in: [a.companyId, b.companyId] } },
    });
    expect(aRows).toHaveLength(2);
  });

  it("no permite falsificar una aprobación oficial con una acción administrativa", async () => {
    const { user } = await tenant("Synthetic DGII forgery");
    await service.updateHabilitation(user, { state: "PREPARING_REQUIREMENTS" });
    await service.updateHabilitation(user, { state: "APPLICATION_PENDING" });

    // Propiedad del estado: la empresa ya no puede declarar ni el estado de
    // proveedor ni el de la DGII. La comprobación es más estricta que antes —
    // no llega a IN_CERTIFICATION siquiera.
    await expect(
      service.updateHabilitation(user, { state: "IN_CERTIFICATION" }),
    ).rejects.toThrow(/ECF_DGII_STATE_REQUIRES_EXTERNAL_EVIDENCE/);
    await expect(
      service.updateHabilitation(user, { state: "APPROVED" }),
    ).rejects.toThrow(/ECF_DGII_STATE_REQUIRES_EXTERNAL_EVIDENCE/);

    const view = await service.getHabilitation(user);
    expect(view.state).toBe("APPLICATION_PENDING");
    expect(view.officialAuthorization).toBe(false);
  });

  it("una declaración manual del operador NO produce autorización", async () => {
    const { user } = await tenant("Synthetic DGII manual claim");
    await service.recordAuthorization(user, {
      source: "MANUAL_OPERATOR_DECLARATION",
      externalId: "DECLARADO-A-MANO",
    });

    const view = await service.getHabilitation(user);
    expect(view.officialAuthorization).toBe(false);
    expect(view.authorizedAt).toBeNull();
    expect(view.state).toBe("NOT_STARTED");
    expect(view.officialAuthorizationBlockers.map((b) => b.code)).toContain(
      "ECF_DGII_AUTHORIZATION_SOURCE_NOT_OFFICIAL",
    );
  });

  it("la fuente oficial exige evidencia e identificador externo", async () => {
    const { user } = await tenant("Synthetic DGII official missing");
    await expect(
      service.recordAuthorization(user, { source: "DGII_OFFICIAL_RECORD" }),
    ).rejects.toThrow(/ECF_DGII_OFFICIAL_EVIDENCE_REQUIRED/);
    await expect(
      service.recordAuthorization(user, {
        source: "DGII_OFFICIAL_RECORD",
        evidenceId: randomUUID(),
      }),
    ).rejects.toThrow(/ECF_DGII_OFFICIAL_EXTERNAL_ID_REQUIRED/);
  });

  it("no permite vincular evidencia de otra empresa", async () => {
    const a = await tenant("Synthetic DGII evidence owner");
    const b = await tenant("Synthetic DGII evidence intruder");
    const evidence = await service.registerEvidence(a.user, {
      source: "OFFICIAL_DOCUMENT",
      kind: "dgii-resolution",
      storageRef: "uat://synthetic-official/resolucion-1",
    });

    await expect(
      service.recordAuthorization(b.user, {
        source: "DGII_OFFICIAL_RECORD",
        evidenceId: evidence.id,
        externalId: "OFICIAL-X",
      }),
    ).rejects.toThrow(/Evidencia e-CF no encontrada/);
  });

  it("con registro oficial la empresa queda aprobada, pero emisión real sigue bloqueada", async () => {
    const { user } = await tenant("Synthetic DGII officially approved");
    const evidence = await service.registerEvidence(user, {
      source: "OFFICIAL_DOCUMENT",
      kind: "dgii-resolution",
      storageRef: "uat://synthetic-official/resolucion-2",
    });
    // Un documento oficial sin revisar todavía no sustenta nada.
    await service.reviewEvidence(user, evidence.id, {
      decision: "REVIEWED",
      note: "Resolución cotejada contra el portal",
    });

    await service.recordAuthorization(user, {
      source: "DGII_OFFICIAL_RECORD",
      evidenceId: evidence.id,
      externalId: "DGII-OFICIAL-2026-1",
    });

    const view = await service.getHabilitation(user);
    expect(view.state).toBe("APPROVED");
    expect(view.officialAuthorization).toBe(true);
    expect(view.authorizedAt).not.toBeNull();
    expect(view.authorizationSource).toBe("DGII_OFFICIAL_RECORD");
    expect(view.officialAuthorizationBlockers).toHaveLength(0);

    // Aun con autorización oficial, la emisión real NO está implementada.
    expect(view.emission.realEmissionAuthorized).toBe(false);
    expect(
      view.blockers.map((b) => b.code),
    ).toContain("ECF_REAL_EMISSION_NOT_IMPLEMENTED");
  });

  it("revocar devuelve la empresa a corrección y retira la autorización", async () => {
    const { user } = await tenant("Synthetic DGII revoked");
    const evidence = await service.registerEvidence(user, {
      source: "OFFICIAL_DOCUMENT",
      kind: "dgii-resolution",
      storageRef: "uat://synthetic-official/resolucion-3",
    });
    await service.reviewEvidence(user, evidence.id, { decision: "REVIEWED" });
    await service.recordAuthorization(user, {
      source: "DGII_OFFICIAL_RECORD",
      evidenceId: evidence.id,
      externalId: "DGII-OFICIAL-2026-2",
    });

    const view = await service.revokeAuthorization(user);
    expect(view.state).toBe("REQUIRES_CORRECTION");
    expect(view.officialAuthorization).toBe(false);
    expect(view.authorizedAt).toBeNull();
    expect(view.authorizationSource).toBe("NONE");
  });

  it("la evidencia distingue documento oficial de declaración manual", async () => {
    const { user } = await tenant("Synthetic DGII evidence sources");
    const official = await service.registerEvidence(user, {
      source: "OFFICIAL_DOCUMENT",
      kind: "certificado",
      storageRef: "uat://synthetic-official/certificado",
    });
    const manual = await service.registerEvidence(user, {
      source: "MANUAL_DECLARATION",
      kind: "nota-interna",
      storageRef: "uat://synthetic-manual/nota",
    });

    expect(official.isOfficialDocument).toBe(true);
    expect(manual.isOfficialDocument).toBe(false);

    const listed = await service.listEvidence(user);
    expect(listed).toHaveLength(2);
    // La referencia de almacenamiento no se expone en la vista: es interna.
    expect(Object.keys(listed[0])).not.toContain("storageRef");
  });

  it("refleja el progreso real de los requisitos obligatorios", async () => {
    const { companyId, user } = await tenant("Synthetic DGII progress");
    await setSteps(companyId, [
      { stepKey: "FISCAL_CONFIG", status: "COMPLETED" },
      { stepKey: "REQUIREMENTS", status: "CONFIRMED" },
      { stepKey: "DIGITAL_CERTIFICATE", status: "IN_PROGRESS" },
    ]);

    const view = await service.getHabilitation(user);
    expect(view.progress.resolvedCount).toBe(2);
    expect(view.progress.pendingMandatory).toContain("DIGITAL_CERTIFICATE");
    expect(view.progress.pendingMandatory).not.toContain("REQUIREMENTS");
    expect(view.blockers.map((b) => b.code)).toContain("ECF_DGII_REQUIREMENTS_PENDING");
  });

  it("registra el historial de cambios y conserva el progreso tras reconectar", async () => {
    const { companyId, user } = await tenant("Synthetic DGII history");
    await service.updateHabilitation(user, {
      state: "PREPARING_REQUIREMENTS",
      reviewState: "en-preparacion",
    });
    await service.registerEvidence(user, {
      source: "MANUAL_DECLARATION",
      kind: "nota",
      storageRef: "uat://synthetic-manual/nota-2",
    });

    const history = await service.listHistory(user);
    expect(history.map((row) => row.action)).toEqual(
      expect.arrayContaining([
        "DGII_HABILITATION_UPDATED",
        "DGII_EVIDENCE_REGISTERED",
      ]),
    );

    // "Reinicio": un servicio nuevo sobre la misma base conserva el estado.
    const restarted = new EcfDgiiHabilitationService(prisma, LOCAL_UAT);
    const view = await restarted.getHabilitation(user);
    expect(view.companyId).toBe(companyId);
    expect(view.state).toBe("PREPARING_REQUIREMENTS");
    expect(view.reviewState).toBe("en-preparacion");
    expect(view.evidence).toHaveLength(1);
  });

  it("rechaza una transición no permitida y una actualización concurrente", async () => {
    const { user } = await tenant("Synthetic DGII transitions");
    await service.updateHabilitation(user, { state: "APPLICATION_PENDING" });
    // Transición inválida entre estados QUE SON DE LA EMPRESA: la rechaza la
    // tabla de transiciones. (Un destino ajeno lo rechaza antes la propiedad del
    // estado, que tiene su propia prueba.)
    await expect(
      service.updateHabilitation(user, { state: "PREPARING_REQUIREMENTS" }),
    ).rejects.toThrow(/ECF_DGII_TRANSITION_NOT_ALLOWED/);

    // Dos actualizaciones en paralelo: la segunda debe detectar la carrera por
    // `updatedAt` y fallar en vez de sobrescribir en silencio.
    const results = await Promise.allSettled([
      service.updateHabilitation(user, { observations: "primera" }),
      service.updateHabilitation(user, { observations: "segunda" }),
    ]);
    const rejected = results.filter((item) => item.status === "rejected");
    expect(rejected.length).toBe(1);
    expect(String((rejected[0] as PromiseRejectedResult).reason)).toMatch(
      /ECF_DGII|modificada por otra solicitud/i,
    );
  });

  it("revisar una evidencia no la convierte en autorización y queda auditado", async () => {
    const { user } = await tenant("Synthetic DGII evidence review");
    const manual = await service.registerEvidence(user, {
      source: "MANUAL_DECLARATION",
      kind: "nota",
      storageRef: "uat://synthetic-manual/nota-revisada",
    });
    expect(manual.reviewStatus).toBe("PENDING");
    expect(manual.level).toBe("DECLARED_BY_COMPANY");
    expect(manual.grantsOfficialAuthorization).toBe(false);

    const reviewed = await service.reviewEvidence(user, manual.id, {
      decision: "REVIEWED",
      note: "Nota interna revisada por administración",
    });
    expect(reviewed.reviewStatus).toBe("REVIEWED");
    expect(reviewed.reviewedAt).not.toBeNull();
    expect(reviewed.reviewNote).toBe("Nota interna revisada por administración");
    // Revisar una declaración manual NO la vuelve oficial.
    expect(reviewed.level).toBe("INTERNALLY_REVIEWED");
    expect(reviewed.isOfficialDocument).toBe(false);
    expect(reviewed.grantsOfficialAuthorization).toBe(false);
    expect(reviewed.supportsOfficialAuthorization).toBe(false);

    const view = await service.getHabilitation(user);
    expect(view.officialAuthorization).toBe(false);
    expect(view.state).not.toBe("APPROVED");

    const history = await service.listHistory(user);
    expect(history.map((row) => row.action)).toContain("DGII_EVIDENCE_REVIEWED");
  });

  it("rechazar exige motivo, no repite la misma decisión y no cruza empresas", async () => {
    const a = await tenant("Synthetic DGII review owner");
    const b = await tenant("Synthetic DGII review intruder");
    const evidence = await service.registerEvidence(a.user, {
      source: "MANUAL_DECLARATION",
      kind: "nota",
      storageRef: "uat://synthetic-manual/nota-rechazo",
    });

    await expect(
      service.reviewEvidence(a.user, evidence.id, { decision: "REJECTED" }),
    ).rejects.toThrow(/ECF_DGII_EVIDENCE_REJECTION_REASON_REQUIRED/);

    // La evidencia de A no es revisable desde B.
    await expect(
      service.reviewEvidence(b.user, evidence.id, { decision: "REVIEWED" }),
    ).rejects.toThrow(/Evidencia e-CF no encontrada/);

    // Repetir la misma decisión del mismo usuario no aporta nada.
    await service.reviewEvidence(a.user, evidence.id, { decision: "REVIEWED" });
    await expect(
      service.reviewEvidence(a.user, evidence.id, { decision: "REVIEWED" }),
    ).rejects.toThrow(/ECF_DGII_EVIDENCE_REVIEW_UNCHANGED/);

    const rows = await service.listEvidence(a.user);
    expect(rows[0].reviewStatus).toBe("REVIEWED");
    const rowsB = await service.listEvidence(b.user);
    expect(rowsB).toHaveLength(0);
  });

  it("una declaración manual revisada sigue sin sustentar la autorización oficial", async () => {
    const { user } = await tenant("Synthetic DGII manual reviewed");
    const manual = await service.registerEvidence(user, {
      source: "MANUAL_DECLARATION",
      kind: "nota-interna",
      storageRef: "uat://synthetic-manual/nota-oficial-falsa",
    });
    await service.reviewEvidence(user, manual.id, {
      decision: "REVIEWED",
      note: "Revisada, pero es una declaración nuestra",
    });

    await expect(
      service.recordAuthorization(user, {
        source: "DGII_OFFICIAL_RECORD",
        evidenceId: manual.id,
        externalId: "DGII-OFICIAL-FALSA",
      }),
    ).rejects.toThrow(/ECF_DGII_AUTHORIZATION_REQUIRES_OFFICIAL_EVIDENCE/);

    const view = await service.getHabilitation(user);
    expect(view.officialAuthorization).toBe(false);
    expect(view.authorizedAt).toBeNull();
    expect(view.state).not.toBe("APPROVED");
  });

  it("un documento oficial sin revisar no autoriza; revisado, sí", async () => {
    const { user } = await tenant("Synthetic DGII official pending review");
    const official = await service.registerEvidence(user, {
      source: "OFFICIAL_DOCUMENT",
      kind: "dgii-resolution",
      storageRef: "uat://synthetic-official/resolucion-pendiente",
    });
    expect(official.level).toBe("OFFICIAL_DOCUMENT_PENDING_REVIEW");
    expect(official.supportsOfficialAuthorization).toBe(false);

    await expect(
      service.recordAuthorization(user, {
        source: "DGII_OFFICIAL_RECORD",
        evidenceId: official.id,
        externalId: "DGII-OFICIAL-2026-PENDIENTE",
      }),
    ).rejects.toThrow(/ECF_DGII_AUTHORIZATION_REQUIRES_REVIEWED_EVIDENCE/);

    const reviewed = await service.reviewEvidence(user, official.id, {
      decision: "REVIEWED",
      note: "Cotejada contra el portal de la DGII",
    });
    expect(reviewed.level).toBe("OFFICIAL_DOCUMENT_REVIEWED");
    expect(reviewed.supportsOfficialAuthorization).toBe(true);

    const view = await service.recordAuthorization(user, {
      source: "DGII_OFFICIAL_RECORD",
      evidenceId: official.id,
      externalId: "DGII-OFICIAL-2026-3",
    });
    expect(view.state).toBe("APPROVED");
    expect(view.officialAuthorization).toBe(true);
    // La autorización oficial sigue sin habilitar la emisión real.
    expect(view.emission.realEmissionAuthorized).toBe(false);
  });

  it("guarda el seguimiento por requisito sin inventar requisitos nuevos", async () => {
    const { user } = await tenant("Synthetic DGII requirement tracking");
    const view = await service.updateRequirement(user, "SET_TESTS", {
      status: "IN_PROGRESS",
      note: "Faltan las pruebas de contingencia",
      dueDate: "2026-11-30",
    });

    const tracked = view.progress.requirements.find((r) => r.key === "SET_TESTS");
    expect(tracked?.tracking?.status).toBe("IN_PROGRESS");
    expect(tracked?.tracking?.note).toBe("Faltan las pruebas de contingencia");
    expect(tracked?.tracking?.dueDate).toBe("2026-11-30");
    expect(tracked?.tracking?.updatedByUserId).toBe(user.id);
    // El seguimiento es gestión interna: NO altera el progreso real del backend.
    expect(tracked?.status).not.toBe("IN_PROGRESS");

    // El catálogo es cerrado: un requisito inventado no existe.
    await expect(
      service.updateRequirement(user, "REQUISITO_INVENTADO", { status: "COMPLETED" }),
    ).rejects.toThrow(/Requisito de habilitación no encontrado/);

    const after = await service.getHabilitation(user);
    expect(
      after.progress.requirements.some((r) => r.key === "REQUISITO_INVENTADO"),
    ).toBe(false);

    // El seguimiento persiste y es por empresa.
    const other = await tenant("Synthetic DGII requirement tracking other");
    const otherView = await service.getHabilitation(other.user);
    expect(
      otherView.progress.requirements.every((r) => r.tracking === null),
    ).toBe(true);
  });
});
