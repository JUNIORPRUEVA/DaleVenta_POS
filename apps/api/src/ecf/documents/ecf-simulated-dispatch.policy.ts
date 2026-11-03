/// Política del despacho SIMULADO de e-CF.
///
/// Motivo: `EcfEmissionService.dispatchOnce` existía pero **ninguna ruta HTTP lo
/// cableaba**, así que la cadena "preparar → proveedor → estado → bandeja" no era
/// alcanzable de extremo a extremo. Habilitarla para el proveedor REAL exige
/// credenciales, contrato oficial y autorización explícita (sigue en NO-GO).
///
/// Este módulo permite recorrer la cadena **solo** con el transporte simulado, y
/// se niega a hacerlo fuera de un entorno UAT local. Es una función pura para
/// poder probarla sin arrancar Nest ni depender del entorno del proceso.
///
/// Nota fiscal: el despacho simulado **no** es emisión, **no** declara aceptación
/// de la DGII y **no** habilita el envío real. `dispatchOnce` nunca concede
/// aceptación: una observación correlacionada acaba siempre en
/// `HUMAN_REVIEW_REQUIRED` para revisión humana.

export type SimulatedDispatchEnv = {
  APP_ENV?: string | undefined;
  UAT_LOCAL_ONLY?: string | undefined;
};

/**
 * Motivo por el que el despacho simulado NO está permitido.
 * `null` significa permitido.
 *
 * `realTransportSelected` es el resultado de `isAlanubeRealTransportSelected`:
 * la MISMA condición que usa la fábrica de transportes, para que la política y
 * el transporte no puedan divergir.
 */
export function simulatedDispatchRefusal(
  env: SimulatedDispatchEnv,
  realTransportSelected: boolean,
): string | null {
  // Si el transporte real estaría activo, este camino queda cerrado: no se
  // permite ni intentarlo.
  if (realTransportSelected) {
    return "ECF_SIMULATED_DISPATCH_REFUSED_REAL_TRANSPORT";
  }

  const appEnv = (env.APP_ENV ?? "").trim().toLowerCase();
  const localOnly = (env.UAT_LOCAL_ONLY ?? "").trim().toLowerCase() === "true";

  // Solo un entorno UAT LOCAL. Ni producción, ni staging, ni un despliegue
  // remoto: el simulador es una herramienta de validación local.
  if (appEnv !== "uat" && !localOnly) {
    return "ECF_SIMULATED_DISPATCH_REFUSED_NOT_LOCAL_UAT";
  }

  return null;
}

/** `true` si el despacho simulado está permitido en este entorno. */
export function isSimulatedDispatchAllowed(
  env: SimulatedDispatchEnv,
  realTransportSelected: boolean,
): boolean {
  return simulatedDispatchRefusal(env, realTransportSelected) === null;
}
