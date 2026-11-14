# Despacho por empresa y conservación del asistente DOSA

Fecha: 2026-11-13. Checkout `finalesdaleventas`, rama `ultimos-trabajos`.
Etapa local; no despliegue, migración compartida ni emisión externa.

## El asistente ya existe

**HECHO:** no falta implementar ni repetir el asistente DOSA. El recorrido
existente conserva sesión por empresa, captura del certificado P12/PFX y sus
contraseñas dentro de DOSA, cierre autenticado de la postulación y autorización
del cliente para emitir. La numeración se solicita en Oficina Virtual y se
registra en el flujo existente de la empresa.

Evidencia consultada:

- `docs/ECF_DOSA_SINGLE_FLOW.md`, sección 3: DOSA captura certificado,
  contraseña del certificado y contraseña del Portal de Certificación DGII;
  FullPOS no duplica esa captura.
- Commit `e703d988`: proceso DOSA único y una acción para iniciarlo.
- Commit `ebc78d98`: eliminación del formulario duplicado de certificado.
- Commit `703f5196`: cierre DOSA como evidencia de aprobación y autorización de
  la empresa. `dosa-activation-authority.service.ts` comprueba firma, vínculo al
  intento/postulación y fechas; no exige repetir una aprobación documental que
  ese proceso no entrega.
- `ecf_dgii_habilitation_page.dart` monta `DosaAssistantSection`, la numeración y
  `EcfAuthorizationStep` existentes, con el contexto de la empresa.
- `FULLTECH_TEST_ACCEPTANCE_2026-11-13.md` conserva la evidencia de FULLTECH y su
  estado de certificación registrado. Los documentos históricos previos al
  cierre de DOSA no son una lista vigente de trabajo por rehacer.

Estos archivos del asistente, sesiones, webhook y autoridad permanecen sin diff
respecto de HEAD. Esta etapa modifica el despacho posterior, no el asistente.
La explicación previa que mezcló las pruebas de ingeniería con ese proceso de
certificación fue imprecisa y se corrige aquí.

## Piloto y clientes

FULLTECH SRL sigue siendo el piloto para validar la integración FullPOS/DOSA.
Los clientes no deben repetir manualmente nuestras pruebas de ingeniería. Cada
empresa conserva su propio proceso/estado de autorización y sus credenciales;
la certificación de FULLTECH no se comparte con otro RNC. No se añade una etapa
TEST obligatoria a clientes ni una restricción con el RNC de FULLTECH escrita en
el código. Se conserva el asistente de DOSA que ya gestiona la certificación.

## Causa y ajuste del despacho

**HECHO:** `DosaEmissionService` seleccionaba el ambiente desde la configuración
global del servidor. El orquestador y la lista de pendientes exigían ese mismo
ambiente, impidiendo que el piloto TEST coexistiera con clientes productivos.

Ahora el lector de configuración recupera ambiente, autorización productiva y
certificación de la empresa autenticada. El despacho valida el ambiente del
documento contra ese valor y vuelve a comprobarlo antes de abrir la bóveda.
Una configuración ausente o ilegible falla cerrada, sin elegir claves globales.
El cliente HTTP y su caché usan empresa + RNC + ambiente + huella de credencial.
Producción exige permiso del servidor, `productionEnabled` de esa empresa y
`PRODUCTION_READY`. TEST nunca toma una clave productiva como sustituto.

No hay cambio de DTO público, nuevas dependencias ni migración en esta etapa.
No se habilitaron banderas ni empresas reales. La transición pública a producción
y la preparación comercial productiva continúan protegidas por los bloqueos de
fase existentes; no se presentan como resueltas por este cambio de despacho.

## Validación local

API validada en copia temporal aislada del mismo código. PostgreSQL propio
`fullpos_ecf_finish_20261112`, base desechable y bases efímeras de los ensayos.
Los proveedores son dobles o servidores HTTP en localhost. Ninguna solicitud
se envía a DOSA/DGII reales.

| Comando | Resultado |
| --- | --- |
| `npm run api:build` | PASS, Prisma generate + TypeScript |
| `npm --workspace apps/api test -- --runInBand` | PASS final: 274 suites y 3262 pruebas; 13 suites/101 pruebas omitidas por sus compuertas |
| `npm --workspace apps/api run test:unit -- --runInBand --runTestsByPath src/ecf/provider/dosa/dosa-emission-key-selection.spec.ts src/ecf/provider/dosa/dosa-integration-journey.spec.ts src/ecf/provider/dosa/dosa-emission.barrier.spec.ts src/ecf/provider/dosa/dosa-certification-intent.controller.spec.ts` | PASS: 94 |
| `npm --workspace apps/api run test:integration -- --runInBand --runTestsByPath src/ecf/integration/multi-company-e2e.integration-spec.ts src/ecf/provider/dosa/dosa-dispatch-pending-postgres.integration-spec.ts src/ecf/documents/ecf-environment-isolation-postgres.integration-spec.ts` | PASS: 24 |
| `npm --workspace apps/api run test:e2e -- --runInBand --runTestsByPath src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts --testNamePattern='dos empresas despachan simult'` | PASS: caso mixto; 18 casos omitidos por el filtro |
| `npm --workspace apps/api run test:e2e -- --runInBand --runTestsByPath src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts src/ecf/provider/dosa/dosa-emission-dispatch.e2e-spec.ts` | PASS final: 31/31 |
| `flutter test test/features/ecf/ecf_repository_test.dart test/features/ecf/ecf_dosa_dispatch_action_test.dart test/modules/ventas/ecf_pos_fiscal_test.dart test/core/printing/ecf_print_representation_test.dart` | PASS: 69 |
| `flutter test test/features/ecf/dosa_assistant_test.dart test/features/ecf/dosa_assistant_section_test.dart test/features/ecf/dosa_assistant_publishable_key_test.dart test/features/ecf/ecf_flow_steps_test.dart test/features/ecf/ecf_authorization_step_test.dart test/features/ecf/ecf_completed_view_test.dart test/features/ecf/ecf_dgii_habilitation_page_test.dart` | PASS: 140 pruebas existentes del asistente y su recorrido |

Las comprobaciones cubren el alcance local de esta etapa. No se modificó
Flutter en esta etapa ni se afirma una nueva certificación externa a partir de
estas pruebas. `git diff --check` pasó y los archivos API coinciden con la copia
aislada compilada y probada. El contenedor PostgreSQL propio se detiene al cerrar
la validación; no se elimina la base.

El ensayo mixto usa dos empresas ficticias, una TEST y otra marcada PRODUCTION:
despachan a localhost simultáneamente con claves propias, igual texto de e-NCF
en sus rangos independientes y QR del ambiente correspondiente. El acceso
cruzado se rechaza; retirar la autorización productiva bloquea antes de crear
un intento o enviar. El documento productivo sintético se prepara con el motor
interno para probar el despacho, no mediante el recorrido comercial protegido.

Los primeros ensayos fallaron por dos fixtures incompletos: faltaba el desglose
de pago del documento manual y una prueba antigua confundía el ambiente global
con el de la empresa. Se completaron los datos y se conservó la prueba negativa
con la empresa realmente configurada en producción sin autorización. No se
debilitó la compuerta para hacerlos pasar. Permanecen avisos de deprecación
ts-jest, SQLite experimental y handles abiertos; Flutter PDF avisa sobre las
fuentes Helvetica en sus fixtures.

## Consulta resuelta por Alejandro

Actualización posterior, 2026-11-13 a las 16:53: el usuario aportó la respuesta
del proveedor. El mismo endpoint de envío espera el resultado final y repetir
el comprobante devuelve el último resultado sin reenviar uno aceptado o aceptado
condicional. Por tanto, la consulta GET separada ya no es una dependencia para
el recorrido síncrono. No se solicita otra implementación del asistente ni una
nueva respuesta de Alejandro sobre esa consulta. La documentación pública aún
describe HTTP 202; ese estado continúa pendiente, nunca se convierte en aceptación.

La recuperación dentro del despacho vivo se implementa y valida en la
[etapa posterior](ECF_DOSA_SAME_REQUEST_RECOVERY_2026-11-13.md). No incluye
reanudar operaciones tras reiniciar el proceso.

## Pendientes de cierre

- Activación productiva y preparación comercial en FullPOS, preservando los
  permisos, certificación, consentimiento y numeración propios de la empresa.
- Reanudación tras agotar la recuperación o perder el proceso; cierre de 202 e
  impresión de contingencia; resultado automático RFCE sin TrackId. La recuperación
  limitada dentro del despacho vivo queda cubierta en la etapa posterior enlazada.
- Revisión de migraciones/clasificación histórica ya preparadas y despliegue
  coordinado únicamente después de validación y autorización.

**NO-GO para producción.** El asistente existente no se considera pendiente de
reimplementación ni se solicita recertificar FULLTECH.

## Archivos de esta etapa

- `apps/api/src/ecf/provider/dosa/dosa-emission.service.ts`
- `apps/api/src/ecf/provider/dosa/dosa-company-fiscal-config.ts`
- `apps/api/src/ecf/provider/dosa/dosa-emission-dispatch.service.ts`
- `apps/api/src/ecf/provider/dosa/dosa-emission-key-selection.spec.ts`
- `apps/api/src/ecf/provider/dosa/dosa-integration-journey.spec.ts`
- `apps/api/src/ecf/provider/dosa/dosa-certification-intent.controller.spec.ts`
- `apps/api/src/ecf/provider/dosa/dosa-emission.barrier.spec.ts`
- `apps/api/src/ecf/provider/dosa/dosa-dispatch-pending-postgres.integration-spec.ts`
- `apps/api/src/ecf/provider/dosa/dosa-emission-dispatch.e2e-spec.ts`
- `apps/api/src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts`
- `apps/api/src/ecf/integration/multi-company-e2e.integration-spec.ts`
- `docs/ARCHITECTURE.md`
- `docs/ENVIRONMENTS.md`
- `docs/PRODUCT_SPEC.md`
- `docs/ecf/ECF_COMPANY_ENVIRONMENT_DISPATCH_2026-11-13.md`
