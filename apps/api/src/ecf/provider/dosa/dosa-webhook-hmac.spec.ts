import { createHmac } from "node:crypto";
import {
  DOSA_DEFAULT_TOLERANCE_SECONDS,
  DOSA_SIGNATURE_HEADER,
  DOSA_WEBHOOK_PENDING_QUESTIONS,
  parseSignatureHeader,
  readDosaSignatureConfig,
  resolveTimestampUnit,
  verifyDosaSignature,
  type DosaResolvedInterpretation,
  type DosaSignatureConfig,
} from "./dosa-webhook-signature.policy";

/**
 * Verificación `X-Dosa-Signature` con el contrato CONFIRMADO por el proveedor:
 *
 *   `t=<hora>,v1=HMAC-SHA256(secret, t + "." + rawBody)`
 *
 * La firma de estas pruebas se calcula aquí, con la fórmula documentada, para
 * que el verificador se contraste contra una implementación independiente y no
 * contra sí mismo.
 */

const SECRET = "secreto-de-prueba-para-hmac-no-real";
const NOW = 1_790_000_000_000; // instante fijo: pruebas deterministas
const NOW_SECONDS = Math.floor(NOW / 1000);

function hmc(
  raw: Buffer,
  options: { t?: string; secret?: string; encoding?: "hex" | "base64" } = {},
): string {
  const t = options.t ?? String(NOW_SECONDS);
  const secret = options.secret ?? SECRET;
  return createHmac("sha256", secret)
    .update(`${t}.`, "utf8")
    .update(raw)
    .digest(options.encoding ?? "hex");
}

function header(raw: Buffer, options: { t?: string; encoding?: "hex" | "base64" } = {}) {
  const t = options.t ?? String(NOW_SECONDS);
  return `t=${t},v1=${hmc(raw, { t, encoding: options.encoding })}`;
}

function hmacConfig(
  overrides: Partial<DosaSignatureConfig> = {},
): DosaSignatureConfig {
  return {
    strategy: "HMAC_SHA256_TIMESTAMPED",
    secret: SECRET,
    timestampUnit: "seconds",
    toleranceSeconds: DOSA_DEFAULT_TOLERANCE_SECONDS,
    ...overrides,
  };
}

function verify(
  headerValue: string | undefined,
  rawBody: Buffer | undefined,
  config = hmacConfig(),
) {
  return verifyDosaSignature({
    headers: headerValue === undefined ? {} : { [DOSA_SIGNATURE_HEADER]: headerValue },
    config,
    rawBody,
    nowMs: NOW,
  });
}

// Cuerpo con formato NO canónico (sangría y espacios): si el verificador
// re-serializara el JSON, el digest cambiaría y este caso fallaría. Un cuerpo
// real del proveedor llega con el formato que él decida, no con el nuestro.
const BODY = {
  postulacion_id: "post-1",
  rnc: "13199988001",
  ambiente: "Test",
  credenciales_pendientes: false,
  disponibles_desde: "2026-11-01T22:50:12Z",
  razon_social: "EMPRESA DE PRUEBA",
  estado_certificacion: "finalizado",
};
const RAW = Buffer.from(JSON.stringify(BODY, null, 2), "utf8");

describe("X-Dosa-Signature — HMAC-SHA256 con timestamp", () => {
  it("acepta una firma correcta en hexadecimal", () => {
    const result = verify(header(RAW), RAW);
    expect(result).toEqual({ ok: true, strategy: "HMAC_SHA256_TIMESTAMPED" });
  });

  it("acepta una firma correcta en base64", () => {
    const result = verify(header(RAW, { encoding: "base64" }), RAW);
    expect(result.ok).toBe(true);
  });

  it("usa los BYTES originales: un cuerpo re-serializado NO valida", () => {
    // Mismo contenido semántico, otros bytes: la firma se calculó sobre RAW.
    const reserialized = Buffer.from(JSON.stringify(JSON.parse(RAW.toString())), "utf8");
    expect(reserialized.equals(RAW)).toBe(false);

    const result = verify(header(RAW), reserialized);
    expect(result).toEqual({
      ok: false,
      strategy: "HMAC_SHA256_TIMESTAMPED",
      reason: "SIGNATURE_MISMATCH",
    });
  });

  it("rechaza si el cuerpo se altera después de firmar", () => {
    const tampered = Buffer.from(RAW);
    // Cambia un solo byte de un valor del cuerpo.
    const index = tampered.indexOf("post-1");
    tampered[index] = "P".charCodeAt(0);

    const result = verify(header(RAW), tampered);
    expect(result.ok).toBe(false);
    expect((result as { reason: string }).reason).toBe("SIGNATURE_MISMATCH");
  });

  it("rechaza una firma hecha con otro secreto", () => {
    const forged = `t=${NOW_SECONDS},v1=${hmc(RAW, { secret: "otro-secreto" })}`;
    const result = verify(forged, RAW);
    expect((result as { reason: string }).reason).toBe("SIGNATURE_MISMATCH");
  });

  it("rechaza una firma calculada con otro timestamp", () => {
    // Firma de t-1000 pero cabecera con t: el mensaje firmado no coincide.
    const stale = header(RAW, { t: String(NOW_SECONDS - 1000) });
    const swapped = stale.replace(`t=${NOW_SECONDS - 1000}`, `t=${NOW_SECONDS}`);
    const result = verify(swapped, RAW);
    expect((result as { reason: string }).reason).toBe("SIGNATURE_MISMATCH");
  });

  it("protege contra replay: fuera de la ventana se rechaza", () => {
    const oldT = String(NOW_SECONDS - DOSA_DEFAULT_TOLERANCE_SECONDS - 5);
    // La firma es criptográficamente válida; lo que falla es la antigüedad.
    const result = verify(header(RAW, { t: oldT }), RAW);
    expect(result).toEqual({
      ok: false,
      strategy: "HMAC_SHA256_TIMESTAMPED",
      reason: "SIGNATURE_TIMESTAMP_OUT_OF_TOLERANCE",
    });
  });

  it("rechaza un timestamp demasiado en el futuro", () => {
    const futureT = String(NOW_SECONDS + DOSA_DEFAULT_TOLERANCE_SECONDS + 5);
    const result = verify(header(RAW, { t: futureT }), RAW);
    expect((result as { reason: string }).reason).toBe(
      "SIGNATURE_TIMESTAMP_OUT_OF_TOLERANCE",
    );
  });

  it("acepta justo dentro de la ventana", () => {
    const edgeT = String(NOW_SECONDS - DOSA_DEFAULT_TOLERANCE_SECONDS + 1);
    const result = verify(header(RAW, { t: edgeT }), RAW);
    expect(result.ok).toBe(true);
  });

  it("respeta la unidad configurada en milisegundos", () => {
    const tMs = String(NOW);
    const result = verify(
      `t=${tMs},v1=${hmc(RAW, { t: tMs })}`,
      RAW,
      hmacConfig({ timestampUnit: "milliseconds" }),
    );
    expect(result.ok).toBe(true);

    // Con la unidad equivocada, el mismo evento se rechaza (nunca se acepta).
    const asSeconds = verify(`t=${tMs},v1=${hmc(RAW, { t: tMs })}`, RAW);
    expect((asSeconds as { reason: string }).reason).toBe(
      "SIGNATURE_TIMESTAMP_OUT_OF_TOLERANCE",
    );
  });

  it("sin cuerpo original no verifica: falla cerrado", () => {
    const result = verify(header(RAW), undefined);
    expect((result as { reason: string }).reason).toBe("RAW_BODY_UNAVAILABLE");
  });

  it("sin secreto configurado no verifica", () => {
    const result = verify(header(RAW), RAW, hmacConfig({ secret: null }));
    expect((result as { reason: string }).reason).toBe("SECRET_NOT_CONFIGURED");
  });

  it("con la estrategia bloqueada no verifica aunque la firma sea válida", () => {
    const result = verify(header(RAW), RAW, hmacConfig({ strategy: "BLOCKED" }));
    expect((result as { reason: string }).reason).toBe("STRATEGY_BLOCKED");
  });

  it("sin cabecera no verifica", () => {
    const result = verify(undefined, RAW);
    expect((result as { reason: string }).reason).toBe("SIGNATURE_HEADER_MISSING");
  });

  it("la respuesta no filtra el secreto", () => {
    const serialized = JSON.stringify(verify(header(RAW), RAW));
    expect(serialized).not.toContain(SECRET);
  });
});

describe("parseSignatureHeader — validación estricta", () => {
  const value = "abcdef0123456789abcdef0123456789";

  it("acepta el formato confirmado", () => {
    expect(parseSignatureHeader(`t=1790000000,v1=${value}`)).toEqual({
      ok: true,
      timestampRaw: "1790000000",
      signature: value,
    });
  });

  it("tolera espacios alrededor de las partes", () => {
    expect(parseSignatureHeader(` t=1790000000 , v1=${value} `).ok).toBe(true);
  });

  it.each([
    ["sin t", `v1=${value}`, "SIGNATURE_HEADER_MALFORMED"],
    ["sin v1", "t=1790000000", "SIGNATURE_HEADER_MALFORMED"],
    ["parte sin igual", `t=1790000000,v1=${value},basura`, "SIGNATURE_HEADER_MALFORMED"],
    ["valor vacío", "t=1790000000,v1=", "SIGNATURE_HEADER_MALFORMED"],
    ["t duplicado", `t=1790000000,t=1790000001,v1=${value}`, "SIGNATURE_HEADER_MALFORMED"],
    ["v1 duplicado", `t=1790000000,v1=${value},v1=${value}`, "SIGNATURE_HEADER_MALFORMED"],
    ["t no numérico", `t=ayer,v1=${value}`, "SIGNATURE_TIMESTAMP_INVALID"],
    ["t negativo", `t=-5,v1=${value}`, "SIGNATURE_TIMESTAMP_INVALID"],
    ["esquema no confirmado", `t=1790000000,v0=${value}`, "SIGNATURE_ALGORITHM_UNSUPPORTED"],
    ["firma demasiado corta", "t=1790000000,v1=abcd", "SIGNATURE_HEADER_MALFORMED"],
  ])("rechaza %s", (_label, headerValue, reason) => {
    const parsed = parseSignatureHeader(headerValue);
    expect(parsed.ok).toBe(false);
    expect((parsed as { reason: string }).reason).toBe(reason);
  });
});

describe("readDosaSignatureConfig", () => {
  const lab = {
    NODE_ENV: "test",
    APP_ENV: "lab",
    DATABASE_URL: "postgresql://u:p@127.0.0.1:5432/db",
  };

  it("sin variable queda bloqueado", () => {
    expect(readDosaSignatureConfig({}).strategy).toBe("BLOCKED");
  });

  it("la estrategia HMAC se acepta en cualquier entorno", () => {
    const config = readDosaSignatureConfig({
      DOSA_WEBHOOK_SIGNATURE_STRATEGY: "HMAC_SHA256_TIMESTAMPED",
      DOSA_WEBHOOK_SECRET: "x",
      NODE_ENV: "production",
      APP_ENV: "production",
    });
    expect(config.strategy).toBe("HMAC_SHA256_TIMESTAMPED");
  });

  it("la estrategia no verificada sigue degradando fuera del laboratorio", () => {
    const config = readDosaSignatureConfig({
      DOSA_WEBHOOK_SIGNATURE_STRATEGY: "UNVERIFIED_PLAINTEXT_SECRET",
      DOSA_WEBHOOK_SECRET: "x",
      NODE_ENV: "production",
      APP_ENV: "production",
    });
    expect(config.strategy).toBe("BLOCKED");
    expect(config.downgradeReason).toBe("NOT_A_LOCAL_LAB_ENVIRONMENT");
  });

  it("en laboratorio la estrategia no verificada se aplica", () => {
    const config = readDosaSignatureConfig({
      ...lab,
      DOSA_WEBHOOK_SIGNATURE_STRATEGY: "UNVERIFIED_PLAINTEXT_SECRET",
      DOSA_WEBHOOK_SECRET: "x",
    });
    expect(config.strategy).toBe("UNVERIFIED_PLAINTEXT_SECRET");
  });

  it("por defecto la unidad se deduce (`auto`) y la tolerancia es 300", () => {
    const config = readDosaSignatureConfig({
      DOSA_WEBHOOK_SIGNATURE_STRATEGY: "HMAC_SHA256_TIMESTAMPED",
      DOSA_WEBHOOK_SECRET: "x",
    });
    expect(config.timestampUnit).toBe("auto");
    expect(config.toleranceSeconds).toBe(DOSA_DEFAULT_TOLERANCE_SECONDS);
  });

  it("la tolerancia no puede volverse infinita", () => {
    const config = readDosaSignatureConfig({
      DOSA_WEBHOOK_SIGNATURE_STRATEGY: "HMAC_SHA256_TIMESTAMPED",
      DOSA_WEBHOOK_SECRET: "x",
      DOSA_WEBHOOK_TOLERANCE_SECONDS: "99999999",
    });
    expect(config.toleranceSeconds).toBe(86_400);
  });

  it("una tolerancia inválida cae al valor por defecto", () => {
    const config = readDosaSignatureConfig({
      DOSA_WEBHOOK_SIGNATURE_STRATEGY: "HMAC_SHA256_TIMESTAMPED",
      DOSA_WEBHOOK_SECRET: "x",
      DOSA_WEBHOOK_TOLERANCE_SECONDS: "-1",
    });
    expect(config.toleranceSeconds).toBe(DOSA_DEFAULT_TOLERANCE_SECONDS);
  });
});

describe("codificación del secreto (pendiente de confirmar por DOSA)", () => {
  // Secreto con forma real: 64 caracteres hexadecimales. Admite dos lecturas
  // incompatibles: texto literal (64 bytes) o 32 bytes decodificados.
  const HEX_SECRET = "a".repeat(64);

  function signedWithSecret(body: Buffer, key: Buffer | string, t = String(NOW_SECONDS)) {
    const digest = createHmac("sha256", key)
      .update(`${t}.`, "utf8")
      .update(body)
      .digest("hex");
    return `t=${t},v1=${digest}`;
  }

  it("por defecto interpreta el secreto como texto literal (utf8)", () => {
    const result = verifyDosaSignature({
      headers: { [DOSA_SIGNATURE_HEADER]: signedWithSecret(RAW, HEX_SECRET) },
      config: { strategy: "HMAC_SHA256_TIMESTAMPED", secret: HEX_SECRET },
      rawBody: RAW,
      nowMs: NOW,
    });
    expect(result.ok).toBe(true);
  });

  it("con `hex` usa los 32 bytes decodificados y no los 64 caracteres", () => {
    const key = Buffer.from(HEX_SECRET, "hex");
    expect(key.length).toBe(32);

    const withHexKey = verifyDosaSignature({
      headers: { [DOSA_SIGNATURE_HEADER]: signedWithSecret(RAW, key) },
      config: {
        strategy: "HMAC_SHA256_TIMESTAMPED",
        secret: HEX_SECRET,
        secretEncoding: "hex",
      },
      rawBody: RAW,
      nowMs: NOW,
    });
    expect(withHexKey.ok).toBe(true);

    // La firma hecha con el texto literal NO vale en modo hex: las dos lecturas
    // son distintas de verdad, no un detalle cosmético.
    const withLiteralKey = verifyDosaSignature({
      headers: { [DOSA_SIGNATURE_HEADER]: signedWithSecret(RAW, HEX_SECRET) },
      config: {
        strategy: "HMAC_SHA256_TIMESTAMPED",
        secret: HEX_SECRET,
        secretEncoding: "hex",
      },
      rawBody: RAW,
      nowMs: NOW,
    });
    expect((withLiteralKey as { reason: string }).reason).toBe("SIGNATURE_MISMATCH");
  });

  it("si se pide `hex` y el secreto no es hex, no se reinterpreta en silencio", () => {
    const result = verifyDosaSignature({
      headers: { [DOSA_SIGNATURE_HEADER]: signedWithSecret(RAW, "no-es-hex") },
      config: {
        strategy: "HMAC_SHA256_TIMESTAMPED",
        secret: "no-es-hex",
        secretEncoding: "hex",
      },
      rawBody: RAW,
      nowMs: NOW,
    });
    expect((result as { reason: string }).reason).toBe("CONFIG_INVALID");
  });

  it("la codificación se lee de entorno y por defecto es `auto`", () => {
    // `auto` prueba las DOS lecturas acotadas del mismo secreto (texto y los 32
    // bytes que codifica), así que un secreto hex funciona sin adivinar cuál de
    // las dos usa el proveedor. La firma sigue teniendo que ser el HMAC exacto.
    expect(
      readDosaSignatureConfig({
        DOSA_WEBHOOK_SIGNATURE_STRATEGY: "HMAC_SHA256_TIMESTAMPED",
        DOSA_WEBHOOK_SECRET: HEX_SECRET,
      }).secretEncoding,
    ).toBe("auto");
    expect(
      readDosaSignatureConfig({
        DOSA_WEBHOOK_SIGNATURE_STRATEGY: "HMAC_SHA256_TIMESTAMPED",
        DOSA_WEBHOOK_SECRET: HEX_SECRET,
        DOSA_WEBHOOK_SECRET_ENCODING: "HEX",
      }).secretEncoding,
    ).toBe("hex");
  });
});

describe("dudas externas documentadas", () => {
  it("la unidad del timestamp y la codificación del digest siguen declaradas como pendientes", () => {
    expect(DOSA_WEBHOOK_PENDING_QUESTIONS.length).toBeGreaterThanOrEqual(2);
    expect(DOSA_WEBHOOK_PENDING_QUESTIONS.join(" ")).toMatch(
      /segundos o milisegundos/i,
    );
    expect(DOSA_WEBHOOK_PENDING_QUESTIONS.join(" ")).toMatch(/hex o en base64/i);
  });
});

/**
 * Firmas de referencia para P1 y P5, calculadas aquí con la fórmula confirmada
 * sobre una clave concreta: el verificador se contrasta contra una
 * implementación independiente, no contra sí mismo.
 */
function signedHmac(input: {
  raw: Buffer;
  key: string | Buffer;
  t: string;
  encoding?: "hex" | "base64";
}): string {
  const digest = createHmac("sha256", input.key)
    .update(`${input.t}.`, "utf8")
    .update(input.raw)
    .digest(input.encoding ?? "hex");
  return `t=${input.t},v1=${digest}`;
}

describe("P1 — unidad de `t` resuelta por magnitud (`auto`)", () => {
  const verifyWith = (headerValue: string, config = hmacConfig({ timestampUnit: "auto" })) =>
    verifyDosaSignature({
      headers: { [DOSA_SIGNATURE_HEADER]: headerValue },
      config,
      rawBody: RAW,
      nowMs: NOW,
    });

  it("acepta un `t` en segundos sin configurar la unidad", () => {
    const t = String(NOW_SECONDS);
    expect(verifyWith(signedHmac({ raw: RAW, key: SECRET, t })).ok).toBe(true);
  });

  it("acepta un `t` en milisegundos sin configurar la unidad", () => {
    const t = String(NOW);
    expect(verifyWith(signedHmac({ raw: RAW, key: SECRET, t })).ok).toBe(true);
  });

  it("un mensaje antiguo en segundos sigue rechazándose por la ventana", () => {
    // La deducción de la unidad NO relaja el anti-replay: el mensaje es
    // auténtico y aun así se rechaza por viejo.
    const t = String(Math.floor(NOW / 1000) - 600);
    expect(
      (verifyWith(signedHmac({ raw: RAW, key: SECRET, t })) as { reason: string })
        .reason,
    ).toBe("SIGNATURE_TIMESTAMP_OUT_OF_TOLERANCE");
  });

  it("un mensaje antiguo en milisegundos sigue rechazándose por la ventana", () => {
    const t = String(NOW - 600_000);
    expect(
      (verifyWith(signedHmac({ raw: RAW, key: SECRET, t })) as { reason: string })
        .reason,
    ).toBe("SIGNATURE_TIMESTAMP_OUT_OF_TOLERANCE");
  });

  it("un `t` del futuro lejano se rechaza igual", () => {
    const t = String(NOW + 86_400_000);
    expect(
      (verifyWith(signedHmac({ raw: RAW, key: SECRET, t })) as { reason: string })
        .reason,
    ).toBe("SIGNATURE_TIMESTAMP_OUT_OF_TOLERANCE");
  });

  it("informa qué unidad validó la firma (evidencia, no suposición)", () => {
    const seen: DosaResolvedInterpretation[] = [];
    const run = (t: string) =>
      verifyDosaSignature({
        headers: { [DOSA_SIGNATURE_HEADER]: signedHmac({ raw: RAW, key: SECRET, t }) },
        config: hmacConfig({ timestampUnit: "auto" }),
        rawBody: RAW,
        nowMs: NOW,
        onResolved: (info) => seen.push(info),
      });

    expect(run(String(NOW_SECONDS)).ok).toBe(true);
    expect(run(String(NOW)).ok).toBe(true);
    expect(seen.map((info) => info.timestampUnit)).toEqual([
      "seconds",
      "milliseconds",
    ]);
  });

  it("el ajuste explícito sigue mandando sobre la deducción", () => {
    // Declarado en segundos, un `t` de 13 dígitos no es «un segundo de 1970».
    const t = String(NOW);
    const result = verifyDosaSignature({
      headers: { [DOSA_SIGNATURE_HEADER]: signedHmac({ raw: RAW, key: SECRET, t }) },
      config: hmacConfig({ timestampUnit: "seconds" }),
      rawBody: RAW,
      nowMs: NOW,
    });
    expect((result as { reason: string }).reason).toBe(
      "SIGNATURE_TIMESTAMP_OUT_OF_TOLERANCE",
    );
  });

  it.each([
    ["1790000000", "seconds"],
    ["1790000000000", "milliseconds"],
    ["0", "seconds"],
    ["", "seconds"],
    ["no-numerico", "seconds"],
  ] as const)("resolveTimestampUnit(%s) → %s", (raw, expected) => {
    expect(resolveTimestampUnit(raw, "auto")).toBe(expected);
  });

  it("un ajuste explícito ignora la magnitud", () => {
    expect(resolveTimestampUnit("1790000000000", "seconds")).toBe("seconds");
    expect(resolveTimestampUnit("1790000000", "milliseconds")).toBe(
      "milliseconds",
    );
  });
});

describe("P5 — lectura del secreto por compatibilidad acotada (`auto`)", () => {
  // 64 caracteres hex: exactamente la forma que tiene el secreto real, y la
  // única en la que existen las dos lecturas (texto vs 32 bytes).
  const HEX_SECRET = "0123456789abcdef".repeat(4);
  const t = String(NOW_SECONDS);
  const autoConfig = () =>
    hmacConfig({ secret: HEX_SECRET, secretEncoding: "auto", timestampUnit: "auto" });

  const verifyWith = (
    headerValue: string,
    config: DosaSignatureConfig = autoConfig(),
  ) =>
    verifyDosaSignature({
      headers: { [DOSA_SIGNATURE_HEADER]: headerValue },
      config,
      rawBody: RAW,
      nowMs: NOW,
    });

  it("acepta el secreto leído como TEXTO literal", () => {
    const headerValue = signedHmac({ raw: RAW, key: HEX_SECRET, t });
    const seen: DosaResolvedInterpretation[] = [];
    const result = verifyDosaSignature({
      headers: { [DOSA_SIGNATURE_HEADER]: headerValue },
      config: autoConfig(),
      rawBody: RAW,
      nowMs: NOW,
      onResolved: (info) => seen.push(info),
    });
    expect(result.ok).toBe(true);
    expect(seen[0]?.secretEncoding).toBe("utf8");
  });

  it("acepta el secreto leído como los 32 BYTES que codifica", () => {
    const key = Buffer.from(HEX_SECRET, "hex");
    const headerValue = signedHmac({ raw: RAW, key, t });
    const seen: DosaResolvedInterpretation[] = [];
    const result = verifyDosaSignature({
      headers: { [DOSA_SIGNATURE_HEADER]: headerValue },
      config: autoConfig(),
      rawBody: RAW,
      nowMs: NOW,
      onResolved: (info) => seen.push(info),
    });
    expect(result.ok).toBe(true);
    expect(seen[0]?.secretEncoding).toBe("hex");
  });

  it("un secreto distinto se rechaza en las dos lecturas", () => {
    const headerValue = signedHmac({ raw: RAW, key: "otro-secreto-distinto", t });
    expect((verifyWith(headerValue) as { reason: string }).reason).toBe(
      "SIGNATURE_MISMATCH",
    );
  });

  it("con `utf8` explícito la lectura hex queda cerrada", () => {
    const key = Buffer.from(HEX_SECRET, "hex");
    const headerValue = signedHmac({ raw: RAW, key, t });
    const result = verifyWith(
      headerValue,
      hmacConfig({
        secret: HEX_SECRET,
        secretEncoding: "utf8",
        timestampUnit: "auto",
      }),
    );
    expect((result as { reason: string }).reason).toBe("SIGNATURE_MISMATCH");
  });

  it("un secreto que no es hex solo admite la lectura de texto", () => {
    const result = verifyDosaSignature({
      headers: {
        [DOSA_SIGNATURE_HEADER]: signedHmac({ raw: RAW, key: SECRET, t }),
      },
      config: hmacConfig({ secret: SECRET, secretEncoding: "auto", timestampUnit: "auto" }),
      rawBody: RAW,
      nowMs: NOW,
    });
    expect(result.ok).toBe(true);
  });

  it("el cuerpo alterado no valida en ninguna lectura", () => {
    const headerValue = signedHmac({ raw: RAW, key: HEX_SECRET, t });
    const tampered = Buffer.concat([RAW, Buffer.from(" ")]);
    const result = verifyDosaSignature({
      headers: { [DOSA_SIGNATURE_HEADER]: headerValue },
      config: autoConfig(),
      rawBody: tampered,
      nowMs: NOW,
    });
    expect((result as { reason: string }).reason).toBe("SIGNATURE_MISMATCH");
  });
});
