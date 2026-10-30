# Bloqueos Alanube DOM / DGII — fases 91–100

## Evidencia vigente del GET autorizado

La consulta única GET /company ya se ejecutó con HTTP 200. RNC 132109122,
id 01M3T6Y4R9BH35XGJ5PP12KV0T, type=main: destino principal resuelto.
Name=FULLTECH y address=address son valores literales observados. Pendiente:
aclarar dirección placeholder y nombre esperado de la simulación; mensaje
reducido actualizado. No sustituir RNC por el real de FULLTECH. No repetir GET.
JWT ADMIN UAT ausente y API4002 no escuchando; login POST local documentado,
no ejecutado bajo la prohibición de cualquier POST. Preflight BLOCKED; 35 pruebas
E32 PASS. Ninguna factura autorizada. Ver evidencia/hash en readiness actualizado.

## Estado E32 tras la última aclaración del usuario

La entrega oficial del paquete Sandbox está confirmada por el usuario. No se
requiere reconfirmar RNC/rango/vigencia ni exigir certificación productiva para
esta prueba. Candidato de formato E32: E320009805001, no enviado. Los pendientes
son operativos: nombre/dirección de emisor, destino principal/asociado y sesión
ADMIN UAT válida con configuración del tenant revisada. Solo si los primeros
datos no están en el paquete/portal usar el borrador reducido de consulta.
Sin JWT las comprobaciones por tenant no se evalúan; no atribuirlo a Alanube.
Readiness BLOCKED; 35 focalizadas/88 PG/975 backend/build PASS. No envío.
La selección primaria sin ULID y GET por id ya están implementados/probados.

## Registro previo (superado para E32 donde discrepe)

## Actualización vigente: primera prueba E32

Para el candidato E32 sintético ya hay transporte exclusivo, preflight JWT UAT,
claim irreversible y consulta GET por compañía con schema oficial independiente.
Primer binding correlacionado y evidencia en cuarentena implementados/probados.
No bloquear esta prueba por saldo/reglas E34, webhook público ni certificación
productiva. Los pendientes generales históricos inferiores siguen aplicando a
una integración fiscal integral, no todos a este ensayo acotado.

Bloqueos reales E32: Alanube debe confirmar compañía/idCompany/habilitación y
e-NCF completo disponible/rango/vigencia. Configuración local no equivale a
autorización, confirmado por el usuario. Después faltan contexto JWT/config del
tenant y consentimiento específico ligado al hash del candidato. DPAPI existe;
no nueva autenticación ni emisión. El script no adivina numeración ni company.id.

Leer ECF_ALANUBE_E32_SANDBOX_READINESS.md y el mensaje exacto
ECF_ALANUBE_E32_PROVIDER_CONFIRMATION_REQUEST.md, preparado y NO enviado.
No se exige firma webhook para una consulta GET; la respuesta tampoco habilita
aceptación fiscal. Ante timeout sin id, detener POST y escalar localización al
proveedor. No se asumió idempotencia DOM ni se agregaron headers de otro país.

2026-10-14. Primera emisión Sandbox: NO-GO. Sin solicitudes enviadas.

## A. Bajo nuestro control

Implementado/probado: bandeja interna inmutable, hash, validación estructural,
tenant/documento/intento/fingerprints, FK compuestas, replay concurrente y lectura
de conciliación conservadora. E34 conserva UNKNOWN_RESULT. No reintentos POST,
estados fiscales por receipts ni receptor público.

Pendiente local operativo: autorización del futuro flujo HTTP/operadores,
orquestación sender/intento/evidencia/ledger, custodia/retención de artefactos,
auditoría de rechazos y límites de tasa del receptor. La correlación actual
congela identidad e ids remotos del documento/intento cuando existen receipts;
no permite asociar por primera vez un id remoto desconocido. Ese binding requiere
diseño explícito con evidencia auténtica/versionado, no un bypass.

## B. Documentación oficial necesaria

Contratos completos/versionados de respuesta/consulta DOM, consistencia, consulta
sin id, alcance por compañía y semántica del 404; procesamiento vs estado fiscal;
esquema webhook, identificador estable, orden, replay, duplicados y ACK; reglas
E34 por línea/concepto/impuesto, parciales/acumuladas, descuentos, exenciones,
redondeos, elegibilidad y límites temporales.

## C. Confirmación Alanube

Idempotencia tras timeout, concurrencia, TTL, garantías de consulta; autenticación
webhook completa, encabezados y eventual firma/canonicalización, rotación,
revocación, rate limits y variantes asíncronas. Un GET público documentado o auth
previa no demuestra todas esas garantías.

## D. Certificación / habilitación

Reseller FULLTECH, activación por empresa, certificados, responsabilidades y
procedimiento completo. Configuración y HTTP no prueban certificación ni eximen
obligaciones fiscales. Conformidad integral DGII no verificada.

## E. Autorización expresa antes de probar

Llamadas autenticadas, envío de solicitud técnica, alta externa de empresas,
numeración y cualquier emisión ficticia Sandbox requieren autorización específica
futura. Producción protegida: sin deploy/migración. Flags no habilitan POST ni E34.

## Fuentes oficiales públicas consultadas el 2026-10-14

- [Consulta E34](https://developer.alanube.co/reference/checkcreditnotes):
  CONFIRMED_OFFICIAL: GET /credit-notes/{id}, Bearer, respuestas 200/400/404/500.
  No se infieren garantías de resultado/desconocido ni aceptación fiscal.
- [Webhook DOM](https://developer.alanube.co/changelog/api-fe-dom-mejoras-en-lo-webhooks-para-notificaciones-de-documentos-electr%C3%B3nicos):
  PARTIAL_OFFICIAL: autenticación previa y configuración auth/cache. No equivale
  a contrato completo de firma ni a prueba criptográfica.
- [E34](https://developer.alanube.co/reference/createcreditnotes): estructura
  publicada. Snapshots oficiales y hashes anteriores preservados.

No se contactó DGII ni endpoints autenticados. Versiones .md de consulta y
changelog inaccesibles por web; se leyó HTML público.

## Revisión E34 — fase 97

| Área | Clasificación | Estado |
| --- | --- | --- |
| ncfModified/ncfModifiedDate/modificationCode requeridos; código 1–4; patrón excluye E33/E34 | REGLA CONTRACTUAL CONFIRMADA | Schema/mapper existentes preservados |
| creditNoteIndicator 0/1, fechas date, motivo máximo 90 | REGLA CONTRACTUAL CONFIRMADA | Validación estructural existente; no deducir plazos |
| Totales, ITBIS, descuentos del subconjunto DOP | REGLA CONTRACTUAL CONFIRMADA en estructura | Núcleo/mapper probado; condiciones legales incompletas |
| Tenant, original E31/E32 con snapshot/log, saldo global y centavos estrictos | VALIDACIÓN INTERNA | PASS local/UAT, sin autenticidad externa |
| Límites por concepto/tasa/cantidad, exenciones/descuentos del original, plazos y elegibilidad completa | REGLA PENDIENTE | PARTIAL/BLOCKED |
| Aceptación auténtica / conformidad integral DGII | REGLA OFICIAL PENDIENTE DE VERIFICACIÓN | BLOCKED; no consultar DGII por restricción expresa |

No surgió una nueva regla suficientemente confirmada para modificar el mapper.
No se repitió trabajo ya terminado ni se inventaron condiciones legales. Un
código de modificación y schema válido no autorizan una nota real.
