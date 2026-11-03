import { ConfigService } from "@nestjs/config";
import type { AlanubeHttpTransport } from "./alanube-safe-http.types";
import { AlanubeRealHttpTransport } from "./alanube-real-http.transport";
import { AlanubeSimulatedTransport } from "./alanube-simulated.transport";
import {
  isSandboxAccessAllowed,
  sandboxAccessRefusal,
  type SandboxAccessEnv,
} from "./alanube-sandbox-access.policy";

export const ALANUBE_HTTP_TRANSPORT = Symbol("ALANUBE_HTTP_TRANSPORT");

/**
 * Construye el transporte. El REAL exige una configuración de sandbox completa
 * (entorno = sandbox, URL https del host oficial y referencia de token válida):
 * si algo falta o apunta a producción, se queda en el SIMULADOR local. Es un
 * fallo cerrado — nunca se habla con el proveedor por una configuración a medias.
 */
export function createAlanubeHttpTransport(config: ConfigService): AlanubeHttpTransport {
  if (isAlanubeRealTransportSelected(config)) {
    return new AlanubeRealHttpTransport();
  }
  return new AlanubeSimulatedTransport();
}

/** Entorno relevante para decidir el transporte, leído de la configuración. */
export function alanubeTransportEnv(config: ConfigService): SandboxAccessEnv {
  return {
    ALANUBE_ENABLE_REAL_CALLS: read(config, "ALANUBE_ENABLE_REAL_CALLS"),
    ALANUBE_HTTP_TRANSPORT_ENABLED: read(config, "ALANUBE_HTTP_TRANSPORT_ENABLED"),
    ALANUBE_ENV: read(config, "ALANUBE_ENV", "sandbox"),
    ALANUBE_BASE_URL: read(config, "ALANUBE_BASE_URL", ""),
    ALANUBE_TOKEN_SECRET_REF: read(config, "ALANUBE_TOKEN_SECRET_REF", ""),
  };
}

/**
 * ÚNICA definición de "el transporte real estaría activo". Además de los tres
 * interruptores, exige que la configuración de sandbox sea completa: un token de
 * pruebas referenciado y una URL oficial de sandbox.
 */
export function isAlanubeRealTransportSelected(config: ConfigService): boolean {
  return isSandboxAccessAllowed(alanubeTransportEnv(config));
}

/** Motivo por el que el transporte real NO se selecciona (para diagnóstico). */
export function alanubeRealTransportRefusal(config: ConfigService): string | null {
  return sandboxAccessRefusal(alanubeTransportEnv(config));
}

function read(config: ConfigService, key: string, fallback = "false") {
  return (config.get<string>(key) ?? process.env[key] ?? fallback).trim().toLowerCase();
}
