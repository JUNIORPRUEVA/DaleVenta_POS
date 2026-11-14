# Numeración e-CF por empresa y ambiente — 2026-11-13

## Resultado y alcance

HECHO: implementación y validación local de la separación SANDBOX/PRODUCTION, conservación segura de evidencia de numeración recibida por webhook y formulario que identifica TEST. No se desplegó, no se modificó una base compartida y no se emitieron nuevos comprobantes externos en este ciclo.

Worktree: finalesdaleventas; rama ultimos-trabajos. Se preservaron los cambios de ciclos anteriores y archivos ajenos preexistentes. No hubo commit ni push.

## Evidencia previa y causa

La auditoría previa del webhook de FULLTECH encontró dos eventos autenticados de producción. Sus resúmenes persistidos no contenían rangos ni vencimiento; el cuerpo original solo conservaba su hash. Esto demuestra lo que quedó guardado, no que DOSA nunca haya enviado esos datos. El parser descartaba campos de numeración no reconocidos. No se puede recuperar el contenido descartado a partir de un hash.

Los rangos y autorizaciones existentes tampoco tenían columna de ambiente. Por eso la presencia de una clave TEST no garantizaba que el contador utilizado perteneciera a TEST. El correo de producción mostrado por el usuario indica secuencias 1–1000 y 31/12/2027; no constituye confirmación de esos valores para TEST.

## Cambios funcionales

- Prisma agrega ambiente a rangos, autorizaciones y auditoría de asignación, y ambiente nullable a documentos históricos. Los índices separan empresa + ambiente; los disparadores impiden reasignar documentos/rangos/autorizaciones existentes a otro ambiente.
- Los servicios consultan, declaran, renuevan y consumen numeración del ambiente configurado. No copian rangos ni retroceden contadores. El bloqueo compartido de la configuración protege las escrituras frente a un cambio concurrente de ambiente.
- La preparación persiste el ambiente del documento y separa su idempotencia. Una nota E34 y su original deben pertenecer al mismo ambiente. La preparación nueva envía explícitamente su ambiente; los consumidores internos antiguos conservan el espacio de idempotencia productivo por compatibilidad.
- El despacho DOSA exige coincidencia entre documento, empresa y ambiente de ejecución; documentos antiguos sin clasificación quedan bloqueados. La bandeja, el resumen y los originales elegibles se filtran por el ambiente actual: el histórico NULL requiere revisión antes del despliegue, pues no aparece automáticamente en esas listas.
- El webhook conserva únicamente campos de numeración reconocidos mediante una proyección acotada de tipos, rangos, fechas y ambientes. Excluye credenciales y texto arbitrario. Es evidencia del proveedor, sin activación automática de rangos. Los nombres admitidos por esta proyección no se presentan como un contrato oficial completo de DOSA; futuros campos desconocidos pueden requerir adaptación.
- El formulario TEST pide referencia y confirmación del proveedor. El cliente envía expectedEnvironment en las tres escrituras; el servidor rechaza formularios desactualizados y el cliente muestra un mensaje para reabrir la numeración. Se corrigió un desbordamiento real del selector a 390 px.

## Validación

PostgreSQL desechable: contenedor fullpos_ecf_finish_20261112, loopback 127.0.0.1:55500, base fullpos_ecf_ephemeral_test. Guardas de objetivo local y llamadas reales desactivadas. API compilada y probada en copia aislada temporal con las mismas fuentes verificadas, para evitar la DLL Prisma que utiliza un proceso previo del repositorio.

Comandos ejecutados y evidencia:

- npx prisma validate (apps/api): PASS.
- npx prisma migrate deploy (apps/api, exclusivamente PostgreSQL local): PASS; migración 20261113040000_ecf_numbering_environment aplicada en el historial local de 81 migraciones.
- npm --workspace apps/api test: 271 suites / 3237 pruebas PASS; 13 suites / 101 pruebas omitidas. Log fullpos-ecf-env-all-verified.log.
- npm --workspace apps/api run test:e2e -- --runTestsByPath src/ecf/provider/dosa/dosa-emission-dispatch.e2e-spec.ts src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts src/ecf/ecf-documents-http.e2e-spec.ts: 3 suites / 29 pruebas PASS. Log fullpos-ecf-env-http-verified.log. Transporte externo simulado.
- flutter analyze: PASS, sin incidencias. Log fullpos-ecf-env-flutter-final-analysis.log.
- flutter test test/features/ecf: ver cierre de validación al final de este documento.
- flutter test test/features/ecf/ecf_sequence_range_section_test.dart --reporter expanded: 17 PASS, capturas con fuentes Manrope e iconos reales a 390/834/1280 px.
- git -c core.safecrlf=false diff --check: PASS.

Los primeros ensayos detectaron fixtures anteriores sin ambiente/configuración, una expectativa de compuerta reemplazada por el bloqueo anterior de ambiente, y el desbordamiento móvil. Se corrigieron y repitieron las pruebas; no se debilitaron los límites fiscales. Jest reporta advertencia de cierre tardío por operaciones asíncronas, aun con todas las aserciones aprobadas. Un intento de build durante ese cierre falló EPERM al reemplazar la DLL Prisma cargada; el resultado del reintento se registra al cierre.

## Evidencia visual

Inspección de imágenes renderizadas de widget, no de una sesión desplegada en navegador. No se utilizó Playwright ni Figma en este ciclo.

- [Móvil 390 px](../design-research/2026-11-12/ecf-numbering-environments/test-numbering-390.png)
- [Tablet 834 px](../design-research/2026-11-12/ecf-numbering-environments/test-numbering-834.png)
- [Escritorio 1280 px](../design-research/2026-11-12/ecf-numbering-environments/test-numbering-1280.png)

## Condiciones antes de desplegar

NO-GO para despliegue compartido: revisar los rangos y documentos existentes por empresa con evidencia del ambiente real. La migración conserva rangos históricos en PRODUCTION de forma conservadora y deja documentos históricos NULL. No debe ejecutarse en producción sin resolver esa clasificación, el histórico visible y un despliegue coordinado de API/clientes. Los disparadores bloquean incluso NULL → ambiente; cualquier clasificación futura requiere una estrategia de migración auditada y autorizada, sin desactivar protecciones durante la operación normal.

No corregir ni reutilizar contadores consumidos por ensayos previos. La autorización de TEST debe confirmarse para la identidad de cada empresa. Que el sistema pueda almacenar iguales números en dos ambientes no demuestra autorización externa para usarlos.

El E31 TEST de FULLTECH sigue pendiente por rechazo 145 con vencimiento 31/12/2027. E31/E34 aceptados bajo la identidad inicial TEST de DOSA y E32 aceptados bajo FULLTECH son evidencia de identidades distintas, no un cierre completo de FULLTECH.

Referencias: [ensayos FULLTECH](FULLTECH_TEST_EXECUTION_2026-11-12.md), [aceptación TEST inicial](DOSA_INITIAL_TEST_ACCEPTANCE_2026-11-12.md), [documentación primaria de DOSA](https://github.com/alapaix13/DosaInvoicecloud-Documentation). La documentación consultada no confirma que la numeración productiva de FULLTECH sea válida en TEST.

## Archivos de este ciclo

- apps/api/prisma/schema.prisma
- apps/api/prisma/migrations/20261113040000_ecf_numbering_environment/migration.sql
- apps/api/src/ecf/documents/ecf-credit-note-postgres.integration-spec.ts
- apps/api/src/ecf/documents/ecf-dgii-authorized-sequences.service.ts
- apps/api/src/ecf/documents/ecf-document-idempotency.service.ts
- apps/api/src/ecf/documents/ecf-document-query-postgres.integration-spec.ts
- apps/api/src/ecf/documents/ecf-document-query.service.ts
- apps/api/src/ecf/documents/ecf-e31-emission-postgres.integration-spec.ts
- apps/api/src/ecf/documents/ecf-e32-consumo-postgres.integration-spec.ts
- apps/api/src/ecf/documents/ecf-e34-credit.service.ts
- apps/api/src/ecf/documents/ecf-e34-emission-postgres.integration-spec.ts
- apps/api/src/ecf/documents/ecf-e34-postgres.integration-spec.ts
- apps/api/src/ecf/documents/ecf-emission.service.ts
- apps/api/src/ecf/documents/ecf-fiscal-document-persistence-postgres.integration-spec.ts
- apps/api/src/ecf/documents/ecf-preparation-postgres.integration-spec.ts
- apps/api/src/ecf/documents/ecf-preparation.service.ts
- apps/api/src/ecf/documents/ecf-sequence-postgres.integration-spec.ts
- apps/api/src/ecf/documents/ecf-sequence.service.ts
- apps/api/src/ecf/documents/ecf-simulated-dispatch-concurrency-postgres.integration-spec.ts
- apps/api/src/ecf/documents/ecf-simulated-dispatch-postgres.integration-spec.ts
- apps/api/src/ecf/dto/ecf-documents.dto.ts
- apps/api/src/ecf/ecf-documents-http.e2e-spec.ts
- apps/api/src/ecf/provider/dosa/dosa-dispatch-pending-postgres.integration-spec.ts
- apps/api/src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts
- apps/api/src/ecf/provider/dosa/dosa-emission-dispatch.e2e-spec.ts
- apps/api/src/ecf/provider/dosa/dosa-emission-dispatch.service.ts
- apps/api/src/ecf/provider/dosa/dosa-webhook.dto.ts
- apps/api/src/sales/sales-return-ecf-credit-postgres.integration-spec.ts
- apps/api/src/ecf/documents/ecf-environment-isolation-postgres.integration-spec.ts
- apps/api/src/ecf/documents/ecf-numbering-environment.ts
- apps/api/src/ecf/documents/ecf-pos-readiness-postgres.integration-spec.ts
- apps/api/src/ecf/provider/dosa/dosa-numbering-metadata.spec.ts
- apps/api/src/ecf/provider/dosa/dosa-numbering-metadata.ts
- apps/fulltech_app/lib/features/ecf/data/ecf_repository.dart
- apps/fulltech_app/lib/features/ecf/ecf_authorized_sequence_models.dart
- apps/fulltech_app/lib/features/ecf/ui/flow/ecf_sequence_range_section.dart
- apps/fulltech_app/test/features/ecf/ecf_sequence_range_section_test.dart
- apps/fulltech_app/test/features/ecf/ecf_repository_test.dart
- docs/PRODUCT_SPEC.md
- docs/ARCHITECTURE.md
- docs/ENVIRONMENTS.md
- docs/ecf/ECF_ENVIRONMENT_NUMBERING_2026-11-13.md
- docs/design-research/2026-11-12/ecf-numbering-environments/test-numbering-{390,834,1280}.png

## Cierre de validación Flutter

flutter analyze: PASS, sin incidencias (fullpos-ecf-env-flutter-final-analysis.log). flutter test test/features/ecf --reporter expanded: 426 PASS, sin fallos (fullpos-ecf-env-flutter-final-tests.log). Incluye la prueba del cuerpo HTTP de declaración/registro/renovación con expectedEnvironment y la traducción del rechazo por ambiente desactualizado. Las capturas finales se regeneraron después del ajuste del texto TEST y se inspeccionó el resultado móvil.

## Cierre de compilación y veredicto

npm run api:build: PASS, Prisma Client 5.22.0 generado y TypeScript compilado, código de salida 0 (fullpos-ecf-env-build-verified-retry.log). El primer intento EPERM fue transitorio mientras el runner Jest retenía la DLL; el reintento terminó sin cambiar código ni detener servicios del usuario. La comprobación de igualdad de las 55 fuentes API copiadas dio true. git -c core.safecrlf=false diff --check: PASS.

GO para las verificaciones locales descritas. NO-GO para despliegue compartido y para declarar terminado el módulo completo: clasificación histórica, confirmación de numeración TEST propia de FULLTECH y flujo externo completo siguen pendientes. Ninguna aceptación bajo otra identidad sustituye esas verificaciones.

Se añadieron enlaces de seguimiento a docs/ecf/FULLTECH_TEST_EXECUTION_2026-11-12.md y docs/ecf/DOSA_INITIAL_TEST_ACCEPTANCE_2026-11-12.md, preservando los resultados históricos.

## Actualización externa posterior — 2026-11-13

La confirmación de numeración TEST propia de FULLTECH y las pruebas externas E31/E34 ya se completaron: [aceptación y trazabilidad](FULLTECH_TEST_ACCEPTANCE_2026-11-13.md). Se aceptaron E310000000002 y E340000000001 con vencimiento TEST E31 31/12/2028. Esta resolución reemplaza esos dos pendientes externos señalados anteriormente, sin cambiar el NO-GO de despliegue compartido: clasificación histórica, migración coordinada y validación del recorrido normal del POS aún pendientes.
