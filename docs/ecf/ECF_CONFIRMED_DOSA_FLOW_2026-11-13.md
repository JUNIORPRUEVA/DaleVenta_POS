# Resultado DOSA y cadena E31 → E34 — validación local

Fecha: 2026-11-13. Checkout: `finalesdaleventas`, rama `ultimos-trabajos`.
Esta etapa no despliega, no modifica bases compartidas y no realiza emisiones
externas. Las respuestas fiscales del ensayo son sintéticas, servidas por HTTP
en `127.0.0.1`; no representan una nueva aceptación real de DGII.

## Hallazgo y cambio mínimo

**HECHO:** el trigger `ecf_protect_document_snapshot` congela `payload_summary`
cuando existe una reserva E34. Guardar allí el sello después del envío entraba
en conflicto con esa protección. La migración
`20261113060000_ecf_public_print_stamp` agrega `print_stamp`, independiente del
payload reservado e inmutable después de su primera escritura. No hay backfill
automático. La proyección de impresión conserva la lectura del formato anterior.

**HECHO:** el evaluador DOSA conservaba las aceptaciones observadas en revisión.
El nuevo registrador sólo se ejecuta después de persistir el recibo del envío y
cuando el operador habilita `DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED=true`.
Permanece apagado por defecto y no habilita ninguna compuerta de emisión.

Comprueba empresa, ambiente y certificación, identidad fiscal, e-NCF, referencia
del proveedor, secuencia consumida, QR oficial, huellas de documento/petición y
SHA-256 del recibo HTTP 200. Congela la instantánea fiscal y registra el vínculo
al recibo en una transacción; para E34 aplica la reserva con las reglas existentes
de original, evidencia y saldo. Un segundo despacho permanece bloqueado.
La aceptación condicional se identifica y la interfaz pide revisar observaciones.

La autoridad registrada es `DOSA_REPORTED_DGII_RESULT`, con confianza
`PROVIDER_DECLARED`. Esto registra el resultado DGII comunicado por DOSA; no
afirma verificar una firma DGII independiente ni modifica la cuarentena genérica.
No existe un endpoint nuevo para que un cliente importe o apruebe evidencia.

## Evidencia funcional

La prueba HTTP registra empresas ficticias y ventas por las rutas reales del
backend. Recorre venta → preparación E31 → respuesta DOSA local → recibo e
instantánea → preparación y reserva E34 → respuesta → crédito aplicado →
proyección imprimible con QR. Comprueba que el payload reservado no cambia y
que la base rechaza sustituir el sello. También comprueba RNC ajeno, QR inválido,
pendiente, rechazo, doble despacho, aislamiento y comportamiento por defecto.

Pruebas PostgreSQL adicionales cubren clasificación histórica revisada,
separación de ambientes y reservas E34. La clasificación recupera sólo un sello
validado: no concede aceptación fiscal ni modifica contadores o asignaciones.

## Base documental

La [documentación oficial DOSA](https://github.com/alapaix13/DosaInvoicecloud-Documentation#2-manejo-de-errores-y-reintentos)
indica conservar una respuesta HTTP 200 aceptada o aceptada condicionalmente.
Ante timeout/5xx prescribe el mismo JSON y e-NCF; un 202 conserva su QR y leyenda
de contingencia. Su idempotencia depende de RNC, ambiente y e-NCF; advierte que
un aceptado no compara contenido cambiado. Estos últimos recorridos todavía
no se implementan en esta etapa. La recuperación durante el despacho vivo se
cerró después en [la etapa de recuperación idéntica](ECF_DOSA_SAME_REQUEST_RECOVERY_2026-11-13.md).
Se revisó nuevamente la fuente pública; no se
ejecutaron ejemplos ni se enviaron credenciales.

El portal publica `ObtenerFactura/{id}`; el adaptador aún no lo implementa. El
ejemplo no demuestra que ese id sea TrackId ni que `enviada` sea aceptación DGII.
Alejandro confirmó el 2026-11-13 a las 16:53 que el mismo POST devuelve el
resultado final y es idempotente; el usuario aportó esa respuesta. No se requiere
una consulta GET separada para este recorrido. Véase la
[investigación existente](research/DOSA_EMISSION_API_2026-11.md).

## Validaciones

Validaciones de API en una copia temporal aislada del mismo código, contra el
PostgreSQL Docker propio `fullpos_ecf_finish_20261112`. Se sincronizaron los
archivos API modificados y nuevos, sin usar el `.env` del servidor.

| Comando | Resultado |
| --- | --- |
| `npx prisma migrate deploy` | PASS, migración 0600 aplicada sólo en la base efímera local; el ensayo HTTP también crea y migra su propia base local |
| `npx prisma validate` | PASS |
| `npm run api:build` | PASS, Prisma generate + TypeScript; repetición final después de terminar las pruebas |
| `npm --workspace apps/api test -- --runInBand` | PASS: 274 suites, 3257 pruebas; 13 suites/101 pruebas omitidas por sus compuertas |
| `npm --workspace apps/api run test:e2e -- --runInBand --runTestsByPath src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts` | PASS: 18/18 con implementación final |
| `npm --workspace apps/api run test:integration -- --runInBand --runTestsByPath src/ecf/documents/ecf-legacy-test-classification-postgres.integration-spec.ts src/ecf/documents/ecf-environment-isolation-postgres.integration-spec.ts src/ecf/documents/ecf-e34-emission-postgres.integration-spec.ts` | PASS: 24/24 |
| `flutter test test/features/ecf/ecf_dosa_dispatch_action_test.dart` | PASS secuencial: 9/9; mensajes simple y condicional a 1280/320 px, sin excepciones de layout |
| `flutter test test/features/ecf test/core/printing test/modules/ventas/ecf_pos_fiscal_test.dart` | PASS: 647/647, ejecución final con código estable |
| `flutter analyze` | PASS, sin incidencias en la ejecución final |

Se compararon byte a byte los 11 archivos de API de esta etapa contra la copia
compilada y probada: ninguna diferencia. `git diff --check` pasó en los archivos
de la etapa. No se ejecutó Playwright en esta etapa.

La revisión visual usa el widget real con tema y fuentes de la aplicación y
datos ficticios: [320 px, aceptación condicional](../design-research/2026-11-13/ecf-confirmed-result/result-320.png)
y [1280 px, aceptación simple](../design-research/2026-11-13/ecf-confirmed-result/result-1280.png).
Se revisaron las imágenes renderizadas: texto legible y sin recortes. Es evidencia
de un widget aislado, no de una sesión de producción. El ensayo temporal que
exporta los PNG se retira después de ejecutarse.

Advertencias observadas: deprecación de `ts-jest.isolatedModules` y aviso de
handles abiertos de Jest. Un primer build coincidió con procesos de pruebas
que tenían cargada la DLL Prisma y falló con `EPERM`; la repetición final pasó.
Una prueba Flutter concurrente falló al copiar `sqlite3.dll`
(`PathExistsException`); al repetir sola pasó 9/9. Una regresión iniciada antes
del ajuste final del mensaje condicional terminó 646 PASS/1 FAIL en ese mensaje;
la repetición completa pasó 647/647. El primer ensayo E34 reveló que la empresa
ficticia sólo tenía E31 permitido; se habilitó E34 por la ruta de configuración,
sin debilitar la regla.

## Pendientes para producción

**NO-GO de producción.** Esta etapa valida el recorrido síncrono E31/E34 local.
No sustituye los resultados TEST reales ya documentados de FULLTECH.

1. Reanudación después de reiniciar el proceso o agotar las llamadas permitidas.
   La etapa posterior ya cubre timeout/red/5xx dentro del despacho vivo, con
   máximo tres llamadas idénticas y auditoría; un segundo despacho público sigue
   bloqueado y no se presenta esta recuperación como reanudación persistente.
2. Cierre del resultado pendiente 202 e impresión de contingencia con su leyenda.
3. Resultado automático para RFCE E32 sin TrackId: el registrador actual exige
   una referencia remota; esos casos conservan revisión, aunque tengan QR válido.
4. Cierre y pruebas del circuito de producción: `assertCompanyCanPrepare` aún
   restringe la preparación comercial a SANDBOX y bloquea `productionEnabled`.
   No se retiró esa protección en esta etapa.
5. Revisión coordinada de API/cliente y migraciones 0400/0500/0600, respaldo,
   regeneración y aprobación del manifiesto histórico, configuración por empresa
   y autorización de despliegue. Ninguna migración ni clasificación compartida
   ha sido aplicada por esta etapa. El manifiesto guardado no autoriza aplicarlo.

## Archivos de esta etapa

- `apps/api/prisma/schema.prisma`
- `apps/api/prisma/migrations/20261113060000_ecf_public_print_stamp/migration.sql`
- `apps/api/src/ecf/documents/ecf-print-view.ts`
- `apps/api/src/ecf/documents/ecf-document-query.service.ts`
- `apps/api/src/ecf/documents/ecf-emission.service.ts`
- `apps/api/src/ecf/documents/ecf-e34-credit.service.ts`
- `apps/api/src/ecf/documents/ecf-legacy-test-classification.ts`
- `apps/api/src/ecf/provider/dosa/dosa-confirmed-outcome.ts`
- `apps/api/src/ecf/provider/dosa/dosa-emission-dispatch.service.ts`
- `apps/api/src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts`
- `apps/api/src/ecf/provider/dosa-fiscal.provider.ts`
- `apps/fulltech_app/lib/features/ecf/ecf_dosa_dispatch_models.dart`
- `apps/fulltech_app/test/features/ecf/ecf_dosa_dispatch_action_test.dart`
- `docs/ARCHITECTURE.md`
- `docs/PRODUCT_SPEC.md`
- `docs/ENVIRONMENTS.md`
- `docs/ECF_DOSA_EMISSION_CONTRACT_VERIFIED.md`
- `docs/ecf/ECF_CONFIRMED_DOSA_FLOW_2026-11-13.md`
- `docs/design-research/2026-11-13/ecf-confirmed-result/result-320.png`
- `docs/design-research/2026-11-13/ecf-confirmed-result/result-1280.png`
