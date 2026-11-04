import {
  INTERNAL_EVIDENCE_SCHEMA,
  internalEvidenceDigest,
  stableStringify,
  verifyInternalEvidence,
  type DosaInternalEvidenceSnapshot,
} from "./dosa-internal-review-evidence";

/**
 * Integridad y reproducibilidad de la evidencia interna.
 *
 * El punto central: un digest con formato correcto NO basta. La atribución
 * vuelve a verificar la consistencia del snapshot, y aquí se demuestra que
 * cualquier manipulación se detecta.
 */

function snapshot(): DosaInternalEvidenceSnapshot {
  return {
    schema: INTERNAL_EVIDENCE_SCHEMA,
    intent: {
      id: "41414141-0000-4000-8000-0000000000c1",
      companyId: "21212121-0000-4000-8000-0000000000a1",
      rnc: "133080206",
      attemptNo: 1,
      status: "NOT_STARTED",
      createdAt: "2026-11-04T01:33:58.668Z",
      createdByUserId: "admin-1",
      providerPostulationId: null,
      sessionUrl: null,
      lastEventType: null,
      providerConfirmedAt: null,
      closedAt: null,
    },
    audit: {
      total: 1,
      originalAuditId: "51515151-0000-4000-8000-0000000000d1",
      originalActorUserId: "admin-1",
      originalProvider: "ALANUBE",
      originalCreated: true,
      originalRnc: "133080206",
      originalAttemptNo: 1,
    },
    activity: {
      legacyProviderAttempts: 0,
      webhookEvents: 0,
      portalTickets: 0,
      portalSessions: 0,
    },
  };
}

function metadata(overrides: Record<string, unknown> = {}) {
  const evidence = snapshot();
  return {
    sourceAuditId: evidence.audit.originalAuditId,
    reviewKind: "INTERNAL",
    internalReviewReference: "internal-audit-2026-11-04-001",
    ownerApprovalReference: "owner-approval-2026-11-04",
    reason: "Revisión interna documentada del intento local sin actividad externa.",
    internalEvidenceDigest: internalEvidenceDigest(evidence),
    evidenceSnapshot: evidence,
    ...overrides,
  };
}

describe("serialización determinista", () => {
  it("el orden de las claves no cambia el resultado", () => {
    expect(stableStringify({ b: 1, a: { d: 2, c: 3 } })).toBe(
      stableStringify({ a: { c: 3, d: 2 }, b: 1 }),
    );
  });

  it("el orden de los elementos de un array SÍ importa", () => {
    expect(stableStringify([1, 2])).not.toBe(stableStringify([2, 1]));
  });

  it("omite los campos undefined para que ausente y undefined coincidan", () => {
    expect(stableStringify({ a: 1, b: undefined })).toBe(stableStringify({ a: 1 }));
  });

  it("el digest es estable y cambia si cambia cualquier campo", () => {
    const base = snapshot();
    expect(internalEvidenceDigest(base)).toBe(internalEvidenceDigest(snapshot()));
    const changed = {
      ...base,
      activity: { ...base.activity, webhookEvents: 1 },
    };
    expect(internalEvidenceDigest(changed)).not.toBe(internalEvidenceDigest(base));
  });
});

describe("verificación de la decisión interna", () => {
  it("acepta el caso excepcional exacto", () => {
    expect(verifyInternalEvidence(metadata())).toEqual({ ok: true });
  });

  it("rechaza que no sea una decisión interna", () => {
    expect(verifyInternalEvidence(metadata({ reviewKind: "EXTERNAL" }))).toEqual({
      ok: false,
      reason: "REVIEW_KIND_NOT_INTERNAL",
    });
  });

  it("rechaza una referencia interna ausente o demasiado corta", () => {
    expect(verifyInternalEvidence(metadata({ internalReviewReference: "" }))).toMatchObject({
      ok: false,
      reason: "INTERNAL_REFERENCE_MISSING",
    });
    expect(verifyInternalEvidence(metadata({ internalReviewReference: "corto" }))).toMatchObject({
      ok: false,
      reason: "INTERNAL_REFERENCE_MISSING",
    });
  });

  it("exige la aprobación del propietario y un motivo suficiente", () => {
    expect(verifyInternalEvidence(metadata({ ownerApprovalReference: "" }))).toMatchObject({
      ok: false,
      reason: "OWNER_APPROVAL_MISSING",
    });
    expect(verifyInternalEvidence(metadata({ reason: "corto" }))).toMatchObject({
      ok: false,
      reason: "REASON_MISSING",
    });
  });

  it("rechaza arrastrar una referencia externa", () => {
    expect(
      verifyInternalEvidence(metadata({ externalReviewReference: "provider-review-123" })),
    ).toMatchObject({ ok: false, reason: "EXTERNAL_REFERENCE_PRESENT" });
  });

  it("rechaza un digest con formato válido que no corresponde al snapshot", () => {
    expect(verifyInternalEvidence(metadata({ internalEvidenceDigest: "b".repeat(64) }))).toMatchObject({
      ok: false,
      reason: "DIGEST_MISMATCH",
    });
    expect(verifyInternalEvidence(metadata({ internalEvidenceDigest: "no-es-un-digest" }))).toMatchObject({
      ok: false,
      reason: "DIGEST_INVALID",
    });
  });

  it("rechaza un snapshot ausente o incompleto", () => {
    expect(verifyInternalEvidence(metadata({ evidenceSnapshot: undefined }))).toMatchObject({
      ok: false,
      reason: "SNAPSHOT_MISSING",
    });
    expect(
      verifyInternalEvidence(metadata({ evidenceSnapshot: { schema: INTERNAL_EVIDENCE_SCHEMA } })),
    ).toMatchObject({ ok: false, reason: "SNAPSHOT_INCOMPLETE" });
  });

  it("solo acepta el primer intento en NOT_STARTED", () => {
    const attempt2 = snapshot();
    attempt2.intent.attemptNo = 2;
    expect(
      verifyInternalEvidence(metadata({
        evidenceSnapshot: attempt2,
        internalEvidenceDigest: internalEvidenceDigest(attempt2),
      })),
    ).toMatchObject({ ok: false, reason: "INTENT_NOT_FIRST" });

    const started = snapshot();
    started.intent.status = "IN_PROGRESS";
    expect(
      verifyInternalEvidence(metadata({
        evidenceSnapshot: started,
        internalEvidenceDigest: internalEvidenceDigest(started),
      })),
    ).toMatchObject({ ok: false, reason: "INTENT_NOT_STARTED" });
  });

  it("rechaza cualquier referencia de proveedor en el intento", () => {
    for (const field of [
      "providerPostulationId",
      "sessionUrl",
      "lastEventType",
      "providerConfirmedAt",
      "closedAt",
    ] as const) {
      const withReference = snapshot();
      (withReference.intent as unknown as Record<string, unknown>)[field] = "x";
      expect(
        verifyInternalEvidence(metadata({
          evidenceSnapshot: withReference,
          internalEvidenceDigest: internalEvidenceDigest(withReference),
        })),
      ).toMatchObject({ ok: false });
    }
  });

  it("rechaza actividad externa aunque el digest sea coherente", () => {
    for (const field of [
      "legacyProviderAttempts",
      "webhookEvents",
      "portalTickets",
      "portalSessions",
    ] as const) {
      const withActivity = snapshot();
      (withActivity.activity as unknown as Record<string, number>)[field] = 1;
      expect(
        verifyInternalEvidence(metadata({
          evidenceSnapshot: withActivity,
          internalEvidenceDigest: internalEvidenceDigest(withActivity),
        })),
      ).toMatchObject({ ok: false });
    }
  });

  it("rechaza una auditoría original no única, no creada o no ALANUBE", () => {
    const duplicated = snapshot();
    duplicated.audit.total = 2;
    expect(
      verifyInternalEvidence(metadata({
        evidenceSnapshot: duplicated,
        internalEvidenceDigest: internalEvidenceDigest(duplicated),
      })),
    ).toMatchObject({ ok: false, reason: "AUDIT_NOT_UNIQUE" });

    const notCreated = snapshot();
    notCreated.audit.originalCreated = false;
    expect(
      verifyInternalEvidence(metadata({
        evidenceSnapshot: notCreated,
        internalEvidenceDigest: internalEvidenceDigest(notCreated),
      })),
    ).toMatchObject({ ok: false, reason: "ORIGINAL_NOT_CREATED" });

    const otherProvider = snapshot();
    otherProvider.audit.originalProvider = "DOSA";
    expect(
      verifyInternalEvidence(metadata({
        evidenceSnapshot: otherProvider,
        internalEvidenceDigest: internalEvidenceDigest(otherProvider),
      })),
    ).toMatchObject({ ok: false, reason: "HISTORICAL_NOT_ALANUBE" });
  });

  it("rechaza incoherencias entre auditoría original e intento", () => {
    const otherRnc = snapshot();
    otherRnc.audit.originalRnc = "999999999";
    expect(
      verifyInternalEvidence(metadata({
        evidenceSnapshot: otherRnc,
        internalEvidenceDigest: internalEvidenceDigest(otherRnc),
      })),
    ).toMatchObject({ ok: false, reason: "ORIGINAL_RNC_MISMATCH" });

    const otherActor = snapshot();
    otherActor.audit.originalActorUserId = "otro-usuario";
    expect(
      verifyInternalEvidence(metadata({
        evidenceSnapshot: otherActor,
        internalEvidenceDigest: internalEvidenceDigest(otherActor),
      })),
    ).toMatchObject({ ok: false, reason: "ORIGINAL_ACTOR_MISMATCH" });

    expect(verifyInternalEvidence(metadata({ sourceAuditId: "otro-id" }))).toMatchObject({
      ok: false,
      reason: "SOURCE_AUDIT_MISMATCH",
    });
  });
});
