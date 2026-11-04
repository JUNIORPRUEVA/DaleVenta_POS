import {
  createDosaSessionUrlCipher,
  DosaSessionUrlCipher,
} from "./dosa-session-url-cipher";

const KEY_V1 = Buffer.alloc(32, 1).toString("base64");
const KEY_V2 = Buffer.alloc(32, 2).toString("base64");
const context = {
  companyId: "11111111-1111-4111-8111-111111111111",
  rnc: "101-00000-1",
  sessionId: "22222222-2222-4222-8222-222222222222",
};

describe("DosaSessionUrlCipher", () => {
  it("cifra y descifra la URL sin dejarla en claro", () => {
    const cipher = new DosaSessionUrlCipher(new Map([[1, Buffer.from(KEY_V1, "base64")]]), 1);
    const url = "https://dosasystem.com/sesion/abc?token=secreto";

    const sealed = cipher.seal({ ...context, url });

    expect(sealed.startsWith("fpv1:1:")).toBe(true);
    expect(sealed).not.toContain("dosasystem.com");
    expect(sealed).not.toContain("secreto");
    expect(cipher.open({ ...context, stored: sealed })).toBe(url);
  });

  it("no permite mover el criptograma a otra empresa, RNC o intento", () => {
    const cipher = new DosaSessionUrlCipher(new Map([[1, Buffer.from(KEY_V1, "base64")]]), 1);
    const sealed = cipher.seal({ ...context, url: "https://dosasystem.com/sesion/abc" });

    expect(
      cipher.open({
        ...context,
        companyId: "33333333-3333-4333-8333-333333333333",
        stored: sealed,
      }),
    ).toBeNull();
    expect(
      cipher.open({ ...context, rnc: "202000002", stored: sealed }),
    ).toBeNull();
    expect(
      cipher.open({
        ...context,
        sessionId: "44444444-4444-4444-8444-444444444444",
        stored: sealed,
      }),
    ).toBeNull();
  });

  it("detecta un criptograma manipulado", () => {
    const cipher = new DosaSessionUrlCipher(new Map([[1, Buffer.from(KEY_V1, "base64")]]), 1);
    const sealed = cipher.seal({ ...context, url: "https://dosasystem.com/sesion/abc" });
    const parts = sealed.split(":");
    parts[4] = `${parts[4].slice(0, -2)}AA`;

    expect(cipher.open({ ...context, stored: parts.join(":") })).toBeNull();
  });

  it("acepta texto plano histórico y lo marca como no cifrado", () => {
    const cipher = new DosaSessionUrlCipher(new Map([[1, Buffer.from(KEY_V1, "base64")]]), 1);
    const legacy = "https://dosasystem.com/sesion/legacy";

    expect(cipher.open({ ...context, stored: legacy })).toBe(legacy);
  });

  it("rota claves: los criptogramas viejos siguen abriéndose y los nuevos usan la versión activa", () => {
    const keys = new Map([
      [1, Buffer.from(KEY_V1, "base64")],
      [2, Buffer.from(KEY_V2, "base64")],
    ]);
    const oldCipher = new DosaSessionUrlCipher(keys, 1);
    const rotated = new DosaSessionUrlCipher(keys, 2);
    const oldSealed = oldCipher.seal({ ...context, url: "https://dosasystem.com/sesion/vieja" });
    const newSealed = rotated.seal({ ...context, url: "https://dosasystem.com/sesion/nueva" });

    expect(rotated.currentKeyVersion).toBe(2);
    expect(newSealed.startsWith("fpv1:2:")).toBe(true);
    expect(rotated.open({ ...context, stored: oldSealed })).toBe(
      "https://dosasystem.com/sesion/vieja",
    );
    expect(rotated.open({ ...context, stored: newSealed })).toBe(
      "https://dosasystem.com/sesion/nueva",
    );
  });

  it("sin claves válidas no está listo y no cifra en claro", () => {
    const cipher = new DosaSessionUrlCipher(new Map(), 1);

    expect(cipher.ready).toBe(false);
    expect(() =>
      cipher.seal({ ...context, url: "https://dosasystem.com/sesion/abc" }),
    ).toThrow("DOSA_SESSION_URL_KEY_MISSING");
  });

  it("construye el key ring desde el entorno y usa la versión activa indicada", () => {
    const cipher = createDosaSessionUrlCipher({
      DOSA_SESSION_URL_KEYS: `1:${KEY_V1},2:${KEY_V2}`,
      DOSA_SESSION_URL_ACTIVE_KEY_VERSION: "1",
    });

    expect(cipher.ready).toBe(true);
    expect(cipher.currentKeyVersion).toBe(1);
    expect(
      cipher.seal({ ...context, url: "https://dosasystem.com/sesion/abc" }),
    ).toMatch(/^fpv1:1:/);
  });
});
