import { Logger } from "@nestjs/common";
import type { DosaHttpResponse, DosaHttpTransport } from "./dosa-emission.client";

/**
 * Transporte DOSA FALSO para UAT.
 *
 * No abre sockets: guarda la petición en memoria y devuelve una respuesta
 * canónica. Sirve para recorrer la cadena completa (compuertas → credenciales →
 * cable → `dispatchOnce` → persistencia) sin contactar al proveedor.
 *
 * Reglas de seguridad:
 *
 *  - **No se selecciona por accidente.** El proveedor de DI sólo lo elige cuando
 *    `DOSA_EMISSION_TRANSPORT=FAKE` **y** el entorno es una UAT local; en
 *    cualquier otro caso la fábrica lanza al arrancar. Un despliegue que herede
 *    la variable no arranca apuntando a un transporte falso: falla de forma
 *    visible.
 *  - **No sustituye banderas.** `DOSA_EMISSION_ENABLED` y
 *    `DOSA_PRODUCTION_EMISSION_ENABLED` siguen mandando: con ellas apagadas la
 *    compuerta rechaza antes de llegar aquí.
 *  - **No inventa aceptación fiscal.** La respuesta es una respuesta de
 *    proveedor; el estado final lo decide `assessEcfProviderResponse` y nunca es
 *    aceptación de la DGII.
 */
export class FakeDosaHttpTransport implements DosaHttpTransport {
  private readonly logger = new Logger("DosaFakeTransport");
  /** Peticiones capturadas, en orden. Sólo para inspección en pruebas/UAT. */
  readonly requests: Array<{
    url: string;
    headers: Record<string, string>;
    body: string;
  }> = [];

  /**
   * @param response respuesta que devolverá el "proveedor". Por defecto, una
   *   aceptación simulada con el e-NCF que venga en el cuerpo.
   */
  constructor(
    private readonly response?: (
      request: { url: string; body: string },
    ) => DosaHttpResponse,
  ) {}

  async post(
    url: string,
    init: { headers: Record<string, string>; body: string; signal: AbortSignal },
  ): Promise<DosaHttpResponse> {
    this.requests.push({
      url,
      headers: { ...init.headers },
      body: init.body,
    });

    if (this.response) return this.response({ url, body: init.body });

    // Respuesta canónica: el `eNCF` que se envió, un identificador de
    // seguimiento y un estado de recepción. Nada de "ACEPTADO por la DGII".
    let encf = "";
    try {
      const parsed = JSON.parse(init.body) as {
        encabezado?: { idDoc?: { eNCF?: string } };
      };
      encf = parsed?.encabezado?.idDoc?.eNCF ?? "";
    } catch {
      this.logger.warn("Cuerpo no JSON en el transporte falso de DOSA");
    }

    return {
      status: 200,
      body: JSON.stringify({
        encf,
        estado: "Recibido",
        trackId: `fake-${this.requests.length}`,
      }),
    };
  }

  reset(): void {
    this.requests.length = 0;
  }
}

/**
 * Decide si el transporte falso está habilitado, y falla cerrado.
 *
 * Devuelve `null` cuando no se pidió; lanza cuando se pidió fuera de una UAT
 * local. Nunca devuelve el falso por una variable incompleta.
 */
export function resolveFakeTransportSelection(
  env: Record<string, string | undefined>,
): "FAKE" | null {
  const requested = (env.DOSA_EMISSION_TRANSPORT ?? "").trim().toUpperCase();
  if (requested === "" || requested === "FETCH") return null;

  if (requested !== "FAKE") {
    throw new Error(
      `ECF_DOSA_TRANSPORT_UNKNOWN: DOSA_EMISSION_TRANSPORT debe ser FETCH o FAKE (recibido "${requested}").`,
    );
  }

  const appEnv = (env.APP_ENV ?? "").trim().toLowerCase();
  const uatLocalOnly = (env.UAT_LOCAL_ONLY ?? "").trim().toLowerCase() === "true";
  const localUat = appEnv === "uat" || uatLocalOnly;
  if (!localUat) {
    throw new Error(
      "ECF_DOSA_FAKE_TRANSPORT_FORBIDDEN: el transporte falso de DOSA sólo puede " +
        "seleccionarse en una UAT local (APP_ENV=uat o UAT_LOCAL_ONLY=true).",
    );
  }

  return "FAKE";
}
