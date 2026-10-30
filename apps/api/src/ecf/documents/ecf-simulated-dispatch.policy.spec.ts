import {
  isSimulatedDispatchAllowed,
  simulatedDispatchRefusal,
} from "./ecf-simulated-dispatch.policy";

/**
 * El despacho simulado es la ÚNICA ruta HTTP que cablea `dispatchOnce`. Estas
 * pruebas fijan su compuerta: fuera de una UAT local, o si el transporte real
 * estuviera activo, la ruta debe negarse.
 */
describe("simulated dispatch policy", () => {
  it("permite el despacho en una UAT local con el transporte real apagado", () => {
    expect(
      simulatedDispatchRefusal({ APP_ENV: "uat", UAT_LOCAL_ONLY: "true" }, false),
    ).toBeNull();
    expect(
      isSimulatedDispatchAllowed({ APP_ENV: "uat", UAT_LOCAL_ONLY: "true" }, false),
    ).toBe(true);
  });

  it("permite UAT por APP_ENV aunque UAT_LOCAL_ONLY no esté definido", () => {
    expect(simulatedDispatchRefusal({ APP_ENV: "UAT" }, false)).toBeNull();
  });

  it("permite UAT local declarada solo por UAT_LOCAL_ONLY", () => {
    expect(simulatedDispatchRefusal({ UAT_LOCAL_ONLY: "true" }, false)).toBeNull();
  });

  it("se niega si el transporte real estaría seleccionado", () => {
    const reason = simulatedDispatchRefusal(
      { APP_ENV: "uat", UAT_LOCAL_ONLY: "true" },
      true,
    );
    expect(reason).toBe("ECF_SIMULATED_DISPATCH_REFUSED_REAL_TRANSPORT");
    expect(
      isSimulatedDispatchAllowed({ APP_ENV: "uat", UAT_LOCAL_ONLY: "true" }, true),
    ).toBe(false);
  });

  it("se niega fuera de una UAT local (producción, staging, entorno vacío)", () => {
    for (const env of [
      { APP_ENV: "production" },
      { APP_ENV: "staging" },
      { APP_ENV: "sandbox" },
      {},
      { APP_ENV: "  " },
      { UAT_LOCAL_ONLY: "false" },
      { APP_ENV: "production", UAT_LOCAL_ONLY: "false" },
    ]) {
      expect(simulatedDispatchRefusal(env, false)).toBe(
        "ECF_SIMULATED_DISPATCH_REFUSED_NOT_LOCAL_UAT",
      );
    }
  });

  it("el transporte real manda sobre cualquier otra condición", () => {
    expect(simulatedDispatchRefusal({}, true)).toBe(
      "ECF_SIMULATED_DISPATCH_REFUSED_REAL_TRANSPORT",
    );
    expect(simulatedDispatchRefusal({ APP_ENV: "production" }, true)).toBe(
      "ECF_SIMULATED_DISPATCH_REFUSED_REAL_TRANSPORT",
    );
  });
});
