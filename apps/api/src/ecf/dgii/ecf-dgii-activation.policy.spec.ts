import { ECF_DGII_REQUIREMENT_CATALOG } from "./ecf-dgii-habilitation.policy";
import {
  ECF_ACTIVATION_CLASS,
  ECF_ACTIVATION_STATUS,
  activationBlockers,
  activationClassOf,
  activationSummary,
  buildActivationView,
  catalogWithClass,
  initialStepStatus,
  nextExecutableStep,
  resolveStepStatus,
  stageOf,
  stepStatusFromTransport,
  type ActivationStepInput,
} from "./ecf-dgii-activation.policy";

/** Paso del catálogo convertido a la entrada que consume la política. */
function step(key: string, status: string): ActivationStepInput {
  const item = ECF_DGII_REQUIREMENT_CATALOG.find((row) => row.key === key);
  if (!item) throw new Error(`unknown catalog key ${key}`);
  return {
    key: item.key,
    stepKey: item.stepKey,
    label: item.label,
    mandatory: item.mandatory,
    status,
  };
}

const P = ECF_ACTIVATION_STATUS.PENDING;
const DONE = ECF_ACTIVATION_STATUS.COMPLETED;

describe("motor de activación e-CF — clasificación", () => {
  it("cada paso del catálogo tiene una clase y ningún paso queda sin dueño", () => {
    const classified = catalogWithClass();
    expect(classified).toHaveLength(ECF_DGII_REQUIREMENT_CATALOG.length);
    for (const item of classified) {
      expect(Object.values(ECF_ACTIVATION_CLASS)).toContain(item.className);
    }
  });

  it("reparte 2 automáticos, 7 del cliente, 4 del proveedor y 2 de la autoridad", () => {
    const counts = catalogWithClass().reduce<Record<string, number>>(
      (acc, item) => {
        acc[item.className] = (acc[item.className] ?? 0) + 1;
        return acc;
      },
      {},
    );
    expect(counts[ECF_ACTIVATION_CLASS.AUTOMATIC_LOCAL]).toBe(2);
    // 7 desde que DGII_POSTULATION, SERVICE_URLS y ENCF_REQUEST exigen una
    // presentación en el Portal que ningún proveedor documenta: el dueño es el
    // cliente, no el motor.
    expect(counts[ECF_ACTIVATION_CLASS.CLIENT_ACTION]).toBe(7);
    expect(counts[ECF_ACTIVATION_CLASS.PROVIDER_WAIT]).toBe(4);
    expect(counts[ECF_ACTIVATION_CLASS.AUTHORITY_WAIT]).toBe(2);
  });

  it("una clave desconocida falla cerrada como acción del cliente", () => {
    expect(activationClassOf("NO_EXISTE")).toBe(
      ECF_ACTIVATION_CLASS.CLIENT_ACTION,
    );
  });
});

describe("motor de activación e-CF — vista y orden", () => {
  it("solo son ejecutables los pasos del motor sin resolver", () => {
    const view = buildActivationView([
      step("FISCAL_DATA", P),
      step("DIGITAL_CERTIFICATE", P),
      step("ALANUBE_REGISTRATION", P),
      step("FINAL_AUTHORIZATION", P),
    ]);
    expect(view[0].executable).toBe(true); // automático local
    expect(view[1].executable).toBe(false); // acción del cliente
    expect(view[2].executable).toBe(true); // espera proveedor
    expect(view[3].executable).toBe(false); // espera autoridad
    expect(view[1].awaiting).toContain("acto tuyo");
    expect(view[3].awaiting).toContain("DGII");
    expect(view[0].awaiting).toBeNull();
  });

  it("no salta un paso que no puede resolver, aunque los siguientes sí podría", () => {
    const view = buildActivationView([
      step("FISCAL_DATA", DONE),
      step("REQUIREMENTS", P), // cliente: bloquea
      step("ALANUBE_REGISTRATION", P), // proveedor: ejecutable pero posterior
    ]);
    expect(nextExecutableStep(view)).toBeNull();
  });

  it("devuelve el primer paso ejecutable en orden", () => {
    const view = buildActivationView([
      step("FISCAL_DATA", DONE),
      step("PRINTED_REPRESENTATION", P),
    ]);
    expect(nextExecutableStep(view)?.key).toBe("PRINTED_REPRESENTATION");
  });
});

describe("motor de activación e-CF — resultados del transporte", () => {
  it("una simulación correcta completa un paso del proveedor", () => {
    expect(
      stepStatusFromTransport({
        className: ECF_ACTIVATION_CLASS.PROVIDER_WAIT,
        transportOk: true,
        simulated: true,
      }),
    ).toBe(ECF_ACTIVATION_STATUS.COMPLETED);
  });

  it("un fallo del transporte deja el paso en FAILED", () => {
    expect(
      stepStatusFromTransport({
        className: ECF_ACTIVATION_CLASS.PROVIDER_WAIT,
        transportOk: false,
        simulated: true,
      }),
    ).toBe(ECF_ACTIVATION_STATUS.FAILED);
  });

  it("NINGÚN resultado del transporte completa un paso de la autoridad", () => {
    for (const ok of [true, false]) {
      for (const simulated of [true, false]) {
        expect(
          stepStatusFromTransport({
            className: ECF_ACTIVATION_CLASS.AUTHORITY_WAIT,
            transportOk: ok,
            simulated,
          }),
        ).toBe(ECF_ACTIVATION_STATUS.AWAITING_AUTHORITY);
      }
    }
  });

  it("un paso del cliente nunca se completa por el transporte", () => {
    expect(
      stepStatusFromTransport({
        className: ECF_ACTIVATION_CLASS.CLIENT_ACTION,
        transportOk: true,
        simulated: true,
      }),
    ).toBe(ECF_ACTIVATION_STATUS.AWAITING_CLIENT);
  });
});

describe("motor de activación e-CF — una respuesta OK no es una aprobación", () => {
  const OFFICIAL_STEPS = [
    "DGII_POSTULATION",
    "SERVICE_URLS",
    "SWORN_DECLARATION",
    "ENCF_REQUEST",
    "FINAL_AUTHORIZATION",
    "PRODUCTION_ENABLEMENT",
  ];

  it("ningún paso con confirmación oficial se completa con un OK del transporte", () => {
    for (const key of OFFICIAL_STEPS) {
      for (const className of [
        ECF_ACTIVATION_CLASS.PROVIDER_WAIT,
        ECF_ACTIVATION_CLASS.CLIENT_ACTION,
        ECF_ACTIVATION_CLASS.AUTHORITY_WAIT,
      ]) {
        for (const simulated of [true, false]) {
          const status = resolveStepStatus({
            key,
            className,
            transportOk: true,
            simulated,
          });
          expect(status).not.toBe(ECF_ACTIVATION_STATUS.COMPLETED);
        }
      }
    }
  });

  it("los pasos de presentación DGII quedan esperando al cliente", () => {
    for (const key of ["DGII_POSTULATION", "SERVICE_URLS", "ENCF_REQUEST"]) {
      expect(
        resolveStepStatus({
          key,
          className: ECF_ACTIVATION_CLASS.CLIENT_ACTION,
          transportOk: true,
          simulated: true,
        }),
      ).toBe(ECF_ACTIVATION_STATUS.AWAITING_CLIENT);
    }
  });

  it("la autorización final espera a la autoridad incluso si el transporte dice OK", () => {
    expect(
      resolveStepStatus({
        key: "FINAL_AUTHORIZATION",
        className: ECF_ACTIVATION_CLASS.AUTHORITY_WAIT,
        transportOk: true,
        simulated: false,
      }),
    ).toBe(ECF_ACTIVATION_STATUS.AWAITING_AUTHORITY);
  });

  it("los pasos puramente técnicos del proveedor sí se completan con un OK", () => {
    for (const key of ["ALANUBE_REGISTRATION", "XML_SIGNATURE", "SET_TESTS"]) {
      expect(
        resolveStepStatus({
          key,
          className: ECF_ACTIVATION_CLASS.PROVIDER_WAIT,
          transportOk: true,
          simulated: true,
        }),
      ).toBe(ECF_ACTIVATION_STATUS.COMPLETED);
    }
  });

  it("un fallo del transporte sigue siendo FAILED y no se disfraza", () => {
    expect(
      resolveStepStatus({
        key: "SET_TESTS",
        className: ECF_ACTIVATION_CLASS.PROVIDER_WAIT,
        transportOk: false,
        simulated: true,
      }),
    ).toBe(ECF_ACTIVATION_STATUS.FAILED);
  });
});

describe("motor de activación e-CF — bloqueos y etapa", () => {
  it("exige datos fiscales y expediente enviado", () => {
    expect(
      activationBlockers({ fiscalDataReady: false, applicationSubmitted: false }),
    ).toEqual([
      "ECF_ACTIVATION_FISCAL_DATA_MISSING",
      "ECF_ACTIVATION_APPLICATION_NOT_SUBMITTED",
    ]);
    expect(
      activationBlockers({ fiscalDataReady: true, applicationSubmitted: true }),
    ).toEqual([]);
  });

  it("el estado inicial del cliente es de espera, no 'pendiente de motor'", () => {
    expect(initialStepStatus("DIGITAL_CERTIFICATE")).toBe(
      ECF_ACTIVATION_STATUS.AWAITING_CLIENT,
    );
    expect(initialStepStatus("FINAL_AUTHORIZATION")).toBe(
      ECF_ACTIVATION_STATUS.AWAITING_AUTHORITY,
    );
    expect(initialStepStatus("FISCAL_DATA")).toBe(ECF_ACTIVATION_STATUS.PENDING);
  });

  it("describe la etapa con el primer paso no resuelto", () => {
    const base = [
      step("FISCAL_DATA", DONE),
      step("REQUIREMENTS", ECF_ACTIVATION_STATUS.AWAITING_CLIENT),
      step("DIGITAL_CERTIFICATE", P),
    ];
    const view = buildActivationView(base);
    expect(stageOf(view)).toBe("BLOCKED_ON_CLIENT");
    expect(activationSummary(view).resolvedCount).toBe(1);
    expect(activationSummary(view).awaitingClient).toContain("REQUIREMENTS");
  });

  it("no inventa porcentaje: todo pendiente es 0 % y todo resuelto es 100 %", () => {
    const none = buildActivationView([step("FISCAL_DATA", P)]);
    expect(activationSummary(none).percent).toBe(0);
    // Nada ejecutado todavía: la etapa honesta es "sin iniciar", no "en proceso".
    expect(stageOf(none)).toBe("NOT_STARTED");

    const all = buildActivationView([step("FISCAL_DATA", DONE)]);
    expect(activationSummary(all).percent).toBe(100);
    expect(stageOf(all)).toBe("COMPLETED");
  });

  it("en proceso solo cuando el primer paso pendiente es del motor y algo avanzó", () => {
    const view = buildActivationView([
      step("FISCAL_DATA", DONE),
      step("PRINTED_REPRESENTATION", P),
    ]);
    expect(stageOf(view)).toBe("RUNNING");
  });

  it("sin pasos no se declara completado", () => {
    expect(stageOf([])).toBe("NOT_STARTED");
    expect(activationSummary([]).percent).toBe(0);
  });
});
