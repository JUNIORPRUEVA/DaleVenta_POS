# Matriz de confianza e-CF — fases 91–100

2026-10-14. VERIFIED_IN_CODE / VERIFIED_BY_TEST salvo los objetivos bloqueados.

| Fuente / nivel | Autenticación | Identidad empresarial | Integridad | Estado | Evidencia necesaria | Transición permitida | Transición prohibida | Dependencia externa |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SYNTHETIC | Ninguna o TEST_ONLY_AUTHENTICATED | Usuario + documento/intento locales | Hash bytes/correlación | Sintético inmutable | Fixture explícito | Receipt/replay idéntico | Elevar confianza o cambiar estado fiscal | No prueba Alanube/DGII |
| INTERNAL | Usuario interno; no autenticidad fiscal | requireTenant + FK compuestas | Hash exacto | Observación interna | Documento/intento/fingerprints | Registrar observación de timeout/reinicio | Rechazar fiscalmente, liberar E34, repetir POST | Conciliación oficial |
| PROVIDER_RESPONSE / PROVIDER_DECLARED | BLOCKED_PENDING_PROVIDER_CONTRACT | Asociación local previa; nunca companyId externo | Hash/Ajv/código separados | Declaración sin autenticar | Bytes y correlación; id remoto conocido si aparece | Guardar observación | HTTP/schema/id → aceptación | Autenticidad y semántica DOM |
| WEBHOOK / PROVIDER_DECLARED | BLOCKED_PENDING_PROVIDER_CONTRACT | Contexto interno + asociación remota conocida | JSON acotado, envelope LOCAL y replay | Cuarentena interna | Evento correlacionado | Receipt/replay | Recepción pública o cambio fiscal | Esquema wire, autenticación, entrega |
| Autenticada (objetivo no implementado) | Mecanismo/versionado oficial | Emisor/proveedor/tenant comprobados | Artefacto/prueba verificable | BLOCKED | Contrato + prueba auténtica | Ninguna hoy | Activación por boolean/mock | Contrato y adaptador revisado |
| Verificada (objetivo no implementado) | Autenticidad + semántica verificadas | Cadena operación/intento/documento/empresa | Verificación reproducible | BLOCKED | Artefactos y política de custodia | Ninguna hoy | Reclasificar históricos | Contratos y retención |
| Confirmada fiscalmente (objetivo no implementado) | Mecanismo fiscal oficial | Identidad fiscal y empresarial | Evidencia oficial suficiente | BLOCKED | Prueba y semántica DGII | Ninguna hoy | FINISHED/HTTP → DGII_ACCEPTED | Confirmación/certificación |

## Límites y procedencia

source es una declaración del invocador interno, no prueba del transporte.
La DI productiva usa EcfBlockedAuthenticityVerifier: siempre bloqueado. La tabla
no permite niveles AUTHENTICATED/VERIFIED/FISCALLY_CONFIRMED. TEST_ONLY_AUTHENTICATED
solo puede persistir como SYNTHETIC; el spec firma/verifica Ed25519 con claves
efímeras. Ese mecanismo se eligió exclusivamente para probar la extensión, no
describe el contrato Alanube. Ningún fixture se convierte en prueba real.

Los snapshot/log históricos siguen siendo internos/no autenticados: no backfill,
reclasificación ni promoción. El ingestor no escribe snapshot, estado, log fiscal,
numeración ni ledger; no alimenta assertEvidence de E34. Un hash no prueba origen,
firma, veracidad, aceptación ni existencia remota.

JSON/tamaño/hash/correlación inválidos producen errores seguros sin persistir
cuerpo ni una relación adivinada. Un schema inválido pero correlacionado conserva
solo receipt de cuarentena. Diferentes hashes requieren revisión conservadora;
no prueban por sí mismos contradicción fiscal ni orden de eventos.

## Minimización y retención

Bytes solo en memoria: máximo 64 KiB/profundidad 32, políticas locales, no límites
Alanube. No se almacenan body, headers, tokens, firmas, nombres ni mensajes externos.
Solo hashes, IDs locales, código HTTP, fuente/códigos acotados, hash schema,
receivedAt del servidor y actor. occurredAt externo no es reloj ni orden fiscal.
El historial es append-only, sin TTL/purge. La retención legal y custodia de
artefactos deben aprobarse antes de abrir recepción pública; no se inventó una
política legal. Reverificar requeriría resuministrar bytes con el mismo hash:
esta bandeja no es un archivo legal completo de artefactos.

Ver [auditoría](ECF_ALANUBE_PHASES_91_100_FINAL_AUDIT.md) y
[bloqueos](ECF_ALANUBE_PROVIDER_BLOCKERS.md).
