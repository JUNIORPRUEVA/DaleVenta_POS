import { randomBytes } from "node:crypto";
import {
  DosaCredentialService,
  type DosaCredentialStore,
  type StoredDosaCredential,
} from "./dosa-credential.service";
import {
  DosaCredentialVault,
  type DosaCredentialEnvironment,
  type DosaCredentialStatus,
} from "./dosa-credential-vault.service";
import {
  DosaEmissionService,
  type DosaCompanyFiscalConfigReader,
} from "./dosa-emission.service";
import {
  DosaEmissionClient,
  type DosaEmissionConfig,
  type DosaHttpResponse,
  type DosaHttpTransport,
  type DosaSendResult,
} from "./dosa-emission.client";
import { assessDosaEmissionGate } from "./dosa-emission.gate";
import type { DosaActivationEvidence } from "./dosa-activation-authority.service";
import { DosaWebhookService, type DosaCompanyResolver } from "./dosa-webhook.service";
import type { DosaSignatureConfig } from "./dosa-webhook-signature.policy";
import type { DosaEcfRequestBody } from "./dosa-ecf.contract";
import { DOSA_MAPPED_TYPES } from "./dosa-ecf.mapper";

/**
 * Recorrido completo DOSA, de extremo a extremo y **con proveedor simulado**.
 *
 * Empresa FullPOS → postulación → evento autenticado → correlación empresa/RNC →
 * credenciales cifradas → compuerta administrativa → envío E31 TEST simulado.
 *
 * Nada de esto toca la red, DGII ni DOSA: el transporte HTTP es un doble y las
 * respuestas son sintéticas, construidas con la forma documentada por el
 * proveedor. Superar esta suite demuestra que el flujo interno es coherente y
 * que las compuertas no se pueden saltar; **no** demuestra que DOSA acepte nada.
 */

const MASTER = randomBytes(32).toString("base64");
const SECRET = "e".repeat(64);
const COMPANY_ECF = "aaaaaaaa-0000-4000-8000-00000000000a";
const COMPANY_PLAIN = "bbbbbbbb-0000-4000-8000-00000000000b";
const RNC_TEST = "133306001";
const RNC_OTHER = "130000002";

const SIGNATURE: DosaSignatureConfig = {
  strategy: "UNVERIFIED_PLAINTEXT_SECRET",
  secret: SECRET,
};

const E31_BODY: DosaEcfRequestBody = {
  encabezado: {
    version: "1.0",
    idDoc: { tipoeCF: "31", eNCF: "E310000000001", fechaEmision: "03-11-2026" },
    emisor: { RNCEmisor: RNC_TEST, RazonSocialEmisor: "EMPRESA ECF SRL" },
    comprador: { RNCComprador: "101742186", RazonSocialComprador: "CLIENTE SRL" },
    totales: {
      MontoGravadoTotal: "100000.00",
      MontoGravadoI1: "100000.00",
      MontoExento: "0.00",
      ITBIS1: "18",
      TotalITBIS: "18000.00",
      MontoTotal: "118000.00",
    },
  },
  detallesItems: [
    {
      numeroLinea: 1,
      indicadorFacturacion: 1,
      nombreItem: "Servicio",
      indicadorBienoServicio: 2,
      unidadMedida: 1,
      cantidadItem: "1",
      precioUnitarioItem: "100000.00",
      montoItem: "100000.00",
    },
  ],
};

/** Almacén de credenciales en memoria. */
class MemoryCredentialStore implements DosaCredentialStore {
  readonly rows = new Map<string, StoredDosaCredential>();
  private key(row: {
    companyId: string;
    rnc: string;
    environment: DosaCredentialEnvironment;
  }) {
    return `${row.companyId}|${row.rnc}|${row.environment}`;
  }
  async upsert(row: StoredDosaCredential) {
    this.rows.set(this.key(row), row);
  }
  async find(row: {
    companyId: string;
    rnc: string;
    environment: DosaCredentialEnvironment;
  }) {
    return this.rows.get(this.key(row)) ?? null;
  }
  async listByCompany(companyId: string) {
    return [...this.rows.values()].filter((row) => row.companyId === companyId);
  }
  async setStatus(row: {
    companyId: string;
    rnc: string;
    environment: DosaCredentialEnvironment;
    status: DosaCredentialStatus;
  }) {
    const current = this.rows.get(this.key(row));
    if (!current) return false;
    this.rows.set(this.key(row), { ...current, status: row.status });
    return true;
  }
}

/** Empresas: una con e-CF (DOSA) y otra que nunca lo pidió. */
class FakeFiscalConfig implements DosaCompanyFiscalConfigReader {
  async read(companyId: string) {
    if (companyId === COMPANY_ECF) return { ecfEnabled: true, provider: "DOSA" };
    return { ecfEnabled: false, provider: "ALANUBE" };
  }
}

class FakeResolver implements DosaCompanyResolver {
  async resolveByRnc(rnc: string) {
    if (rnc === RNC_TEST) return { companyId: COMPANY_ECF, ecfEnabled: true };
    return null;
  }
}

/** Evento del webhook con la forma real del proveedor. */
function webhookEvent(overrides: Record<string, unknown> = {}) {
  const body = {
    postulacion_id: "post-journey-0001",
    rnc: RNC_TEST,
    razon_social: "EMPRESA ECF SRL",
    correo: "fiscal@example.com",
    ambiente: "Test",
    estado_certificacion: "finalizado",
    credenciales: {
      api_key_produccion: "PROD-SECRETA",
      api_key_test: "TEST-SECRETA",
      api_secret: "API-SECRETA",
    },
    credenciales_pendientes: false,
    disponibles_desde: "2026-11-03T10:00:00Z",
    ...overrides,
  };
  return {
    headers: { "x-dosa-signature": SECRET },
    rawBody: Buffer.from(JSON.stringify(body), "utf8"),
    body,
  };
}

/** Transporte HTTP simulado con la respuesta documentada por el proveedor. */
class SimulatedTransport implements DosaHttpTransport {
  readonly calls: Array<{ url: string; body: string }> = [];
  constructor(private readonly respond: (attempt: number) => DosaHttpResponse) {}

  async post(url: string, init: { body: string }) {
    this.calls.push({ url, body: init.body });
    return this.respond(this.calls.length);
  }
}

function emissionConfig(overrides: Partial<DosaEmissionConfig> = {}): DosaEmissionConfig {
  return {
    enabled: true,
    environment: "TEST",
    baseUrl: "https://dosasystem.com",
    apiKey: "",
    apiKeyIsProduction: false,
    productionEnabled: false,
    testRnc: RNC_TEST,
    timeoutMs: 1000,
    breakerThreshold: 3,
    breakerCooldownMs: 60_000,
    ...overrides,
  };
}

function buildJourney(respond: (attempt: number) => DosaHttpResponse) {
  const credentialStore = new MemoryCredentialStore();
  const credentials = new DosaCredentialService(
    credentialStore,
    new DosaCredentialVault(MASTER),
  );
  const transport = new SimulatedTransport(respond);
  const emission = new DosaEmissionService({
    fiscalConfig: new FakeFiscalConfig(),
    credentials,
    config: emissionConfig(),
    transport,
  });
  const webhook = new DosaWebhookService(
    {
      async $queryRaw() {
        return [{ id: "evt-1" }];
      },
    },
    new FakeResolver(),
    SIGNATURE,
    credentials,
  );
  return { credentialStore, credentials, transport, emission, webhook };
}

async function preparedJourney(respond: (attempt: number) => DosaHttpResponse) {
  const journey = buildJourney(respond);
  // 1. Evento autenticado → credenciales cifradas en PENDING_CONFIRMATION.
  await journey.webhook.handle(webhookEvent());
  return journey;
}

/** Evidencia persistida completa, tal como la leería la autoridad real. */
function fullEvidence(overrides: Partial<DosaActivationEvidence> = {}): DosaActivationEvidence {
  return {
    identityLinked: true,
    postulationBound: true,
    providerConfirmed: true,
    dgiiApproved: true,
    administrativeAuthorized: true,
    details: {
      attemptNo: 1,
      attemptStartedAt: "2026-11-02T12:00:00.000Z",
      postulacionId: "post-journey",
      linkedSessions: 1,
      authenticatedProviderEvents: 1,
      providerEventsForOtherPostulations: 0,
      dgiiState: "APPROVED",
      dgiiSource: "DGII_OFFICIAL_RECORD",
      dgiiAuthorizedAt: "2026-11-02T12:05:00.000Z",
      lastDecision: "RECORDED",
      lastDecisionAt: "2026-11-02T12:06:00.000Z",
      lastRecordedAt: "2026-11-02T12:06:00.000Z",
      authorizationsRecorded: 1,
      authorizationsRevoked: 0,
    },
    ...overrides,
  };
}

async function activatedJourney(respond: (attempt: number) => DosaHttpResponse) {
  const journey = await preparedJourney(respond);
  // 2. Activación: la evidencia se lee de la base, no la aporta el llamador.
  await journey.credentials.promote({
    companyId: COMPANY_ECF,
    rnc: RNC_TEST,
    environment: "test",
    to: "ACTIVE",
    evidence: fullEvidence(),
  });
  return journey;
}

describe("Recorrido DOSA — empresa sin e-CF", () => {
  it("su operación tradicional queda intacta: no hay evento, ni credenciales, ni emisión", async () => {
    const journey = buildJourney(() => ({ status: 200, body: "{}" }));

    const assessment = await journey.emission.assess({
      companyId: COMPANY_PLAIN,
      rnc: "101000001",
      documentType: "E31",
      senderTaxId: "101000001",
      sequenceAvailable: true,
    });

    expect(assessment.allowed).toBe(false);
    expect(assessment.blockingReasons).toContain("ECF_DOSA_GATE_COMPANY_NOT_OPTED_IN");
    expect(assessment.blockingReasons).toContain("ECF_DOSA_GATE_PROVIDER_NOT_DOSA");
    expect(journey.transport.calls).toHaveLength(0);
  });

  it("un evento para una empresa sin e-CF no entra", async () => {
    const journey = buildJourney(() => ({ status: 200, body: "{}" }));
    const outcome = await journey.webhook.handle(
      webhookEvent({ rnc: RNC_OTHER }),
    );
    expect(outcome).toMatchObject({ accepted: false, status: 404 });
    expect(journey.credentialStore.rows.size).toBe(0);
  });
});

describe("Recorrido DOSA — empresa que solicita e-CF", () => {
  it("el expediente queda accesible y la emisión sigue bloqueada hasta activar", async () => {
    const assessment = await (async () => {
      const journey = await preparedJourney(() => ({ status: 200, body: "{}" }));
      return journey.emission.assess({
        companyId: COMPANY_ECF,
        rnc: RNC_TEST,
        documentType: "E31",
        senderTaxId: RNC_TEST,
        sequenceAvailable: true,
      });
    })();

    expect(assessment.credentialStatus).toBe("PENDING_CONFIRMATION");
    expect(assessment.allowed).toBe(false);
    expect(assessment.blockingReasons).toContain(
      "ECF_DOSA_GATE_CREDENTIALS_NOT_ACTIVE",
    );
  });

  it("recibe el evento autenticado y correlaciona empresa y RNC correctamente", async () => {
    const journey = await preparedJourney(() => ({ status: 200, body: "{}" }));

    const stored = await journey.credentials.inspect({
      companyId: COMPANY_ECF,
      rnc: RNC_TEST,
      environment: "test",
    });
    expect(stored).not.toBeNull();
    expect(stored?.companyId).toBe(COMPANY_ECF);
    expect(stored?.rnc).toBe(RNC_TEST);
  });

  it("las credenciales se protegen: nada en claro en el almacén ni en la inspección", async () => {
    const journey = await preparedJourney(() => ({ status: 200, body: "{}" }));

    const raw = JSON.stringify([...journey.credentialStore.rows.values()]);
    expect(raw).not.toContain("TEST-SECRETA");
    expect(raw).not.toContain("PROD-SECRETA");
    expect(raw).not.toContain("API-SECRETA");

    const inspection = await journey.credentials.inspect({
      companyId: COMPANY_ECF,
      rnc: RNC_TEST,
      environment: "test",
    });
    expect(JSON.stringify(inspection)).not.toContain("TEST-SECRETA");
    expect(inspection?.fingerprint).toHaveLength(64);
  });

  it("la recuperación de credenciales exige el contexto exacto de la empresa", async () => {
    const journey = await preparedJourney(() => ({ status: 200, body: "{}" }));

    await expect(
      journey.credentials.openForEmission({
        companyId: COMPANY_PLAIN,
        rnc: RNC_TEST,
        environment: "test",
        authorized: true,
      }),
    ).rejects.toThrow();

    const ok = await journey.credentials.openForEmission({
      companyId: COMPANY_ECF,
      rnc: RNC_TEST,
      environment: "test",
      authorized: true,
    });
    expect(ok.apiKeyTest).toBe("TEST-SECRETA");
  });
});

describe("Recorrido DOSA — bloqueo previo a la autorización fiscal", () => {
  it("CONFIRMED sin activación administrativa no emite", async () => {
    const journey = await preparedJourney(() => ({ status: 200, body: "{}" }));
    await journey.credentials.promote({
      companyId: COMPANY_ECF,
      rnc: RNC_TEST,
      environment: "test",
      to: "CONFIRMED",
      evidence: fullEvidence({ dgiiApproved: false, administrativeAuthorized: false }),
    });

    const result = await journey.emission.emit({
      companyId: COMPANY_ECF,
      rnc: RNC_TEST,
      documentType: "E31",
      senderTaxId: RNC_TEST,
      sequenceAvailable: true,
      body: E31_BODY,
    });

    expect(result.ok).toBe(false);
    expect(journey.transport.calls).toHaveLength(0);
  });

  it("sin credenciales activas no se abre la bóveda ni se toca la red", async () => {
    const journey = buildJourney(() => ({ status: 200, body: "{}" }));
    const result = await journey.emission.emit({
      companyId: COMPANY_ECF,
      rnc: RNC_TEST,
      documentType: "E31",
      senderTaxId: RNC_TEST,
      sequenceAvailable: true,
      body: E31_BODY,
    });
    expect(result.ok).toBe(false);
    expect(journey.transport.calls).toHaveLength(0);
  });

  it("un RNC que no es el de prueba no puede emitir en TEST", async () => {
    const decision = assessDosaEmissionGate({
      companyEcfEnabled: true,
      companyProviderIsDosa: true,
      credentialStatus: "ACTIVE",
      credentialEnvironment: "test",
      environment: "test",
      senderTaxId: "101742186",
      configuredTestRnc: RNC_TEST,
      providerEmissionEnabled: true,
      productionEmissionEnabled: false,
      sequenceAvailable: true,
      documentType: "E31",
    });
    expect(decision.allowed).toBe(false);
    expect(decision.blockingReasons.join(" ")).toContain("TEST_RNC_MISMATCH");
  });

  it("sin bandera de emisión no hay emisión", async () => {
    const journey = await activatedJourney(() => ({ status: 200, body: "{}" }));
    const emission = new DosaEmissionService({
      fiscalConfig: new FakeFiscalConfig(),
      credentials: journey.credentials,
      config: emissionConfig({ enabled: false }),
      transport: journey.transport,
    });

    const result = await emission.emit({
      companyId: COMPANY_ECF,
      rnc: RNC_TEST,
      documentType: "E31",
      senderTaxId: RNC_TEST,
      sequenceAvailable: true,
      body: E31_BODY,
    });
    expect(result.ok).toBe(false);
    expect(journey.transport.calls).toHaveLength(0);
  });

  it("en producción, una credencial de TEST no sirve", async () => {
    const decision = assessDosaEmissionGate({
      companyEcfEnabled: true,
      companyProviderIsDosa: true,
      credentialStatus: "ACTIVE",
      credentialEnvironment: "test",
      environment: "production",
      senderTaxId: RNC_TEST,
      configuredTestRnc: RNC_TEST,
      providerEmissionEnabled: true,
      productionEmissionEnabled: true,
      sequenceAvailable: true,
      documentType: "E31",
    });
    expect(decision.allowed).toBe(false);
    expect(decision.blockingReasons).toContain(
      "ECF_DOSA_GATE_CREDENTIALS_ENVIRONMENT_MISMATCH",
    );
  });
});

describe("Recorrido DOSA — activación autorizada", () => {
  it("con las tres condiciones la compuerta se abre", async () => {
    const journey = await activatedJourney(() => ({ status: 200, body: "{}" }));
    const assessment = await journey.emission.assess({
      companyId: COMPANY_ECF,
      rnc: RNC_TEST,
      documentType: "E31",
      senderTaxId: RNC_TEST,
      sequenceAvailable: true,
    });
    expect(assessment.credentialStatus).toBe("ACTIVE");
    expect(assessment.allowed).toBe(true);
    expect(assessment.blockingReasons).toHaveLength(0);
  });
});

describe("Recorrido DOSA — envío E31 TEST simulado", () => {
  it("aceptado: se envía una sola vez y la clasificación no es aprobación fiscal", async () => {
    const journey = await activatedJourney(() => ({
      status: 200,
      body: JSON.stringify({
        trackId: "4cdc9917-8008-4564-a85c-c3f13a4e0ec8",
        codigo: "1",
        estado: "Aceptado",
        rnc: RNC_TEST,
        encf: "E310000000001",
        url: "https://ecf.dgii.gov.do/testecf/consulta?encf=E310000000001",
        codigoSeguridad: "EAkbyR",
        fechaFirma: "03-11-2026 10:00:00",
        secuenciaUtilizada: true,
        mensajes: [],
      }),
    }));

    const result = await journey.emission.emit({
      companyId: COMPANY_ECF,
      rnc: RNC_TEST,
      documentType: "E31",
      senderTaxId: RNC_TEST,
      sequenceAvailable: true,
      body: E31_BODY,
      idempotencyKey: "attempt-1",
    });

    expect(result.ok).toBe(true);
    expect(journey.transport.calls).toHaveLength(1);
    expect(journey.transport.calls[0].url).toBe(
      "https://dosasystem.com/fe/api/emision/ecf/EnviarFactura",
    );
    if (result.ok && result.result.ok) {
      expect(result.result.classification.outcome).toBe("ACCEPTED");
      expect(result.result.classification.secuenciaUtilizada).toBe(true);
      expect(result.result.classification.impliesFiscalAuthorization).toBe(false);
      expect(result.result.classification.isDgiiApproval).toBe(false);
      expect(result.result.classification.qr?.complete).toBe(true);
    }
  });

  it("rechazado: se propaga el motivo de la DGII", async () => {
    const journey = await activatedJourney(() => ({
      status: 200,
      body: JSON.stringify({
        codigo: "2",
        estado: "Rechazado",
        mensajes: [{ valor: "El campo MontoGravadoI1 no coincide", codigo: 1934 }],
      }),
    }));

    const result = await journey.emission.emit({
      companyId: COMPANY_ECF,
      rnc: RNC_TEST,
      documentType: "E31",
      senderTaxId: RNC_TEST,
      sequenceAvailable: true,
      body: E31_BODY,
      idempotencyKey: "attempt-1",
    });

    expect(result.ok).toBe(true);
    if (result.ok && result.result.ok) {
      expect(result.result.classification.outcome).toBe("REJECTED");
      expect(result.result.classification.mensajes[0]).toContain("MontoGravadoI1");
    }
  });

  it("condicional: cuenta como aprobado según el proveedor, pero sigue sin ser aprobación nuestra", async () => {
    const journey = await activatedJourney(() => ({
      status: 200,
      body: JSON.stringify({
        codigo: "4",
        estado: "Aceptado Condicional",
        mensajes: [{ valor: "Observacion menor", codigo: 1934 }],
        secuenciaUtilizada: true,
      }),
    }));

    const result = await journey.emission.emit({
      companyId: COMPANY_ECF,
      rnc: RNC_TEST,
      documentType: "E31",
      senderTaxId: RNC_TEST,
      sequenceAvailable: true,
      body: E31_BODY,
      idempotencyKey: "attempt-1",
    });

    expect(result.ok).toBe(true);
    if (result.ok && result.result.ok) {
      expect(result.result.classification.outcome).toBe("CONDITIONALLY_ACCEPTED");
      expect(result.result.classification.isDgiiApproval).toBe(false);
    }
  });

  it("incierto (timeout): no se reintenta automáticamente", async () => {
    const transport: DosaHttpTransport = {
      async post(_url, init) {
        await new Promise<void>((_resolve, reject) => {
          init.signal.addEventListener("abort", () => reject(new Error("aborted")));
        });
        return { status: 200, body: "{}" };
      },
    };
    const journey = await activatedJourney(() => ({ status: 200, body: "{}" }));
    const emission = new DosaEmissionService({
      fiscalConfig: new FakeFiscalConfig(),
      credentials: journey.credentials,
      config: emissionConfig({ timeoutMs: 20 }),
      transport,
    });

    const result = await emission.emit({
      companyId: COMPANY_ECF,
      rnc: RNC_TEST,
      documentType: "E31",
      senderTaxId: RNC_TEST,
      sequenceAvailable: true,
      body: E31_BODY,
      idempotencyKey: "attempt-1",
    });

    expect(result.ok).toBe(true);
    if (result.ok) {
      const send = result.result as Extract<DosaSendResult, { ok: false }>;
      expect(send.unconfirmed).toBe(true);
      expect(send.retryPermitted).toBe(false);
    }
  });

  it("incierto (código 0): queda sin resolver, no se marca aceptado ni rechazado", async () => {
    const journey = await activatedJourney(() => ({
      status: 200,
      body: JSON.stringify({ codigo: "0", estado: "No encontrado" }),
    }));

    const result = await journey.emission.emit({
      companyId: COMPANY_ECF,
      rnc: RNC_TEST,
      documentType: "E31",
      senderTaxId: RNC_TEST,
      sequenceAvailable: true,
      body: E31_BODY,
      idempotencyKey: "attempt-1",
    });

    expect(result.ok).toBe(true);
    if (result.ok && result.result.ok) {
      expect(result.result.classification.outcome).toBe("UNRESOLVED");
      expect(result.result.classification.unresolvedReason).toContain(
        "DOSA_STATUS_TABLE_CONFLICT",
      );
    }
  });
});

describe("Recorrido DOSA — recuperación sin duplicar secuencias ni comprobantes", () => {
  it("reenviar con la misma clave de idempotencia no produce un segundo POST", async () => {
    const journey = await activatedJourney(() => ({
      status: 200,
      body: JSON.stringify({ codigo: "1", secuenciaUtilizada: true }),
    }));

    const input = {
      companyId: COMPANY_ECF,
      rnc: RNC_TEST,
      documentType: "E31" as const,
      senderTaxId: RNC_TEST,
      sequenceAvailable: true,
      body: E31_BODY,
      idempotencyKey: "attempt-1",
    };

    await journey.emission.emit(input);
    const second = await journey.emission.emit(input);

    expect(journey.transport.calls).toHaveLength(1);
    expect(second.ok).toBe(true);
    if (second.ok && "blockedReason" in second.result) {
      expect(second.result.blockedReason).toBe("DOSA_IDEMPOTENCY_KEY_ALREADY_SENT");
    }
  });

  it("la doble entrega del webhook no duplica el evento ni regraba credenciales a ciegas", async () => {
    let inserts = 0;
    const store = {
      async $queryRaw(_q: TemplateStringsArray, ...values: unknown[]) {
        const dedupeKey = String(values[1]);
        if (dedupeKey.length > 0 && inserts === 0) {
          inserts += 1;
          return [{ id: "evt-1" }];
        }
        return [];
      },
    };
    const credentialStore = new MemoryCredentialStore();
    const credentials = new DosaCredentialService(
      credentialStore,
      new DosaCredentialVault(MASTER),
    );
    const webhook = new DosaWebhookService(
      store,
      new FakeResolver(),
      SIGNATURE,
      credentials,
    );

    const first = await webhook.handle(webhookEvent());
    const second = await webhook.handle(webhookEvent());

    expect(first).toMatchObject({ accepted: true, duplicate: false });
    expect(second).toMatchObject({ accepted: true, duplicate: true });
  });

  it("un 502 'Error de envío' es el único caso reenviable con el mismo eNCF", async () => {
    const journey = await activatedJourney(() => ({
      status: 502,
      body: JSON.stringify({ estado: "Error de envío", mensaje: "sin DGII" }),
    }));

    const result = await journey.emission.emit({
      companyId: COMPANY_ECF,
      rnc: RNC_TEST,
      documentType: "E31",
      senderTaxId: RNC_TEST,
      sequenceAvailable: true,
      body: E31_BODY,
      idempotencyKey: "attempt-1",
    });

    expect(result.ok).toBe(true);
    if (result.ok && !result.result.ok) {
      expect(result.result.retryPermitted).toBe(true);
      expect(result.result.unconfirmed).toBe(false);
    }
  });
});

describe("Recorrido DOSA — coherencia del catálogo de tipos", () => {
  it("el adaptador solo declara los tipos que el mapeador cubre", () => {
    expect([...DOSA_MAPPED_TYPES].sort()).toEqual(["E31", "E32", "E34"]);
  });
});
