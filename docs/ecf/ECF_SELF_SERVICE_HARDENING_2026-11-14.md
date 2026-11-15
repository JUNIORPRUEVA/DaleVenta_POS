# Autoservicio e-CF por empresa: corrección y validación aislada

## Alcance autorizado

Modo: CONTINUOUS_CONTROLLED_EXECUTION. Base cbc3eceb (PR44 integrado), worktree
C:/src/fullpos-ecf-selfservice-20261114, rama agent/ecf-selfservice-hardening-20261114.
Producción queda fuera: no SSH, configuración, despliegue, reinicio, migración,
credenciales, numeración ni documentos reales. FULLTECH conserva su activación.
Cualquier nuevo despliegue permanece NO-GO hasta autorización expresa del dueño.

## Auditoría inicial y plan

HECHO: el formulario declara expiresAt, pero registerSequence/renewSequence no
reciben esa fecha. El servicio guarda validUntil nulo cuando el cliente la omite.
El POS solicita sequenceDueDate al usuario y SalesService guarda la fecha recibida.
La autorización por empresa/ambiente debe ser la fuente de la fecha E31.

Plan mínimo:

1. Derivar y validar la vigencia E31 desde la autorización de su empresa/ambiente,
   guardarla en rangos nuevos y usarla en ventas y preparación fiscal. Conservar
   rangos y documentos existentes; no backfill, reinicio ni fecha inventada.
2. Retirar la pregunta repetida del cobro y usar la proyección del backend.
   Mantener compatibilidad de contratos y Normal independiente de e-CF.
3. Revisar apertura del asistente, evidencia firmada, autorización del cliente,
   habilitación productiva explícita y numeración. Corregir solo bloqueos reales.
4. Probar una segunda empresa ficticia desde registro hasta emisión simulada,
   mediante rutas del cliente y proveedor local; verificar aislamiento y fallos.
5. Ejecutar análisis, compilaciones, suites backend/PostgreSQL/HTTP/Flutter y QA
   visual local. Revisar diff y revalidar antes del informe final.

Criterios: fecha declarada viaja al rango/venta/payload/impresión; una fecha ajena
o vencida no autoriza emisión; no hay efectos financieros ni numeración al fallar
la admisión; empresa/ambiente y permisos se conservan; concurrencia y recuperación
no duplican efectos; interfaz compacta sin pasos nuevos; no operación productiva.

## Problemas encontrados y correcciones

1. **HECHO — vencimiento desconectado.** La declaración guardaba `expiresAt`,
   pero el rango podía quedar con `validUntil=null` y el cobro solicitaba otra
   fecha. Ahora la autorización E31 de la empresa/ambiente es la fuente: exige
   una fecha de calendario válida, la hereda al registrar/renovar rangos y la
   congela en venta, payload y proyección de impresión. Una fecha contradictoria
   se rechaza antes de los efectos financieros. No se actualizó ningún rango
   existente ni se corrigieron datos históricos mediante scripts.
2. **HECHO — disponibilidad incompleta.** Un rango operativo por sí solo podía
   hacer que el POS pareciera preparado sin comprobar la autorización vigente.
   Capabilities cruza el próximo número con la autorización de su empresa y
   ambiente, además de las barreras de permisos/certificación/credenciales ya
   existentes. Añade `e31SequenceDueDate` de forma compatible.
3. **HECHO — revocación eludible.** La inscripción automática solo buscaba una
   fila ACTIVE. Tras una revocación podía crear otra; una fila ACTIVE vencida
   también devolvía éxito. Dos regresiones reprodujeron el fallo antes de la
   corrección. Ahora consulta el historial, respeta revocación/caducidad y
   serializa concesiones por empresa con bloqueo PostgreSQL.
4. **HECHO — estado fiscal en cambio de sesión.** El repositorio compartido no
   invalidaba todos sus dependientes al cambiar empresa/usuario. Ahora todos
   releen su contexto. Una prueba retiene la respuesta de A, carga B y entrega
   después la respuesta de A: B conserva su numeración. Una respuesta de
   activación de la empresa anterior tampoco se aplica a la empresa actual.
5. **HECHO — TEST aparecía en el recorrido comercial.** Una empresa ya certificada
   y preparada para producción podía ver numeración TEST antes del opt-in. El
   asistente existente muestra la activación productiva y después su numeración
   real. TEST queda disponible para una empresa autorizada en sandbox, sin
   convertir las pruebas de integración de FULLTECH en un paso de cada cliente.
6. **HECHO — carrera en preparación independiente.** Una regresión PostgreSQL
   cambió la autorización entre resolver la fecha y asignar el número; antes se
   preparaba el documento con la fecha anterior. Ahora la preparación transporta
   la fecha esperada hasta el bloqueo de asignación y rechaza el cambio antes de
   consumir el número. Se conserva la semántica previa de recuperación e
   idempotencia, sin envolver toda la preparación histórica en otra transacción.

El formulario conserva sus componentes y estructura. Identifica el vencimiento
E31 obligatorio, elimina fechas de ejemplo y explica su uso automático. El
selector deja el código E31/E32/E34 al principio para mantenerlo visible en móvil.
El cliente anterior puede enviar la fecha coincidente; el nuevo tolera una
respuesta antigua sin la proyección y conserva su alternativa de captura.
Normal/ITBIS, ticket/PDF ordinario y la impresión existente permanecen separados
de la emisión electrónica.

## Flujo comprobado y límites de la simulación

La prueba `two new companies self-onboard...` recorre dos empresas nuevas por
HTTP real contra NestJS y PostgreSQL locales:

1. Registro y acceso con JWT propio; ajustes fiscales y elegibilidad automática.
2. Intención, ticket de un solo uso y sesión del asistente ligada al RNC/empresa.
3. Rechazo de empresa ajena, reutilización de ticket y firma de webhook inválida.
4. Sesión DOSA simulada y evento final HMAC válido; duplicado idempotente.
5. Autorización del cliente, derivación a PRODUCTION_READY y opt-in explícito
   de su empresa; sin personal de plataforma ni promoción manual de credenciales.
6. Registro de autorización/rango con distinta fecha por empresa; el POS sigue
   bloqueado hasta disponer de numeración.
7. Venta E31 sin fecha enviada por el cobro, preparación y despachos simultáneos
   a un servidor HTTP local; cada cuerpo usa su RNC, credencial, fecha y número.
8. Proyección fiscal para impresión con vencimiento y QR propios; empresa ajena
   recibe 404 y cada empresa consume exactamente un número.

**Real en estas pruebas:** HTTP, autenticación, permisos, transacciones, bloqueos,
índices, secuencias, auditoría, firma HMAC, mapeo y persistencia de FullPOS.
**Simulado:** asistente alojado de DOSA, captura/validación externa del certificado,
credenciales, certificación y respuesta de emisión/aceptación de DOSA/DGII.
No se cargó ningún certificado real ni se usaron credenciales productivas.
La proyección de impresión se verificó; no se inventa una nueva prueba en papel.

El cliente todavía debe suministrar sus datos reales, completar los requisitos
externos de DGII/DOSA, solicitar su numeración en Oficina Virtual, transcribir
la autorización y consentir la habilitación productiva. No existe aquí una
consulta oficial nueva que certifique automáticamente que lo transcrito coincide
con la Oficina Virtual. Se valida formato, coherencia, vigencia y pertenencia al
contexto autenticado; no se sustituye la autorización real del contribuyente.
El [formato oficial DGII](https://dgii.gov.do/cicloContribuyente/facturacion/comprobantesFiscalesElectronicosE-CF/Documentacin%20sobre%20eCF/Formatos%20XML/Formato%20Comprobante%20Fiscal%20Electr%C3%B3nico%20%28e-CF%29%20v1.0.pdf)
se consultó como referencia del vencimiento de secuencia. La página pública de
desarrolladores DOSA no pudo recuperarse con la herramienta web; no se atribuyen
a ella comprobaciones nuevas.

## Entorno y evidencias

Dos contenedores propios postgres:16-alpine, etiquetados para esta tarea,
se enlazaron exclusivamente a 127.0.0.1:55500 y 55501, sin datos de clientes.
Las 83 migraciones existentes se aplicaron únicamente a esas bases nuevas.
No se creó una migración ni se relajó la lista de destinos efímeros permitidos.
El runner privado valida etiqueta, nombre y enlace local antes de cada ejecución.
Los proveedores reales permanecen apagados; los casos de producción simulada
solo habilitan permisos dentro del proceso de prueba y apuntan a localhost.
Al terminar se verificaron de nuevo las etiquetas/enlaces y se detuvieron ambos
contenedores propios (Exited 0). Ningún contenedor ajeno fue detenido.

Logs privados de esta tarea: C:/Users/pc/.codex/backups/fullpos-ecf-selfservice-20261114/.
No se incluyen secretos ni archivos de entorno en el repositorio.

Las capturas de widgets reales se encuentran en [selfservice-visual-2026-11-14](selfservice-visual-2026-11-14/).
Producción E31: 320/390/1280 px; formulario TEST: 390/834/1280 px.
Se inspeccionaron imágenes renderizadas por Flutter: no desbordamientos, fecha
obligatoria legible y código de tipo visible en móvil. Esto no equivale a una
sesión de navegador. El host de control de Chrome no estuvo disponible y el
fallback nativo fue bloqueado por falta de confianza en la URL; se detuvo sin
reintentar ni eludir el bloqueo. QA interactiva de navegador pendiente.
El entry point `test/preview/ecf_selfservice_preview.dart` permite revisar solo
widgets existentes con datos sintéticos locales; no se importa en la aplicación.

## Validaciones

Comandos ejecutados desde este worktree, salvo Flutter desde apps/fulltech_app.
Los comandos PostgreSQL se lanzaron mediante el runner privado `local-qa.ps1`,
que primero verifica el contenedor propio y construye su conexión solo en memoria.

| Comando / alcance | Resultado observado |
| --- | --- |
| `npm ci --no-audit --no-fund` | PASS; dependencias bloqueadas, sin cambio al lockfile |
| `flutter pub get` | PASS; sin cambio al lockfile |
| `npx prisma migrate deploy` + `npx prisma validate` desde apps/api | PASS exclusivamente en las dos bases locales nuevas; 83 migraciones existentes |
| `npm run api:build` | PASS después de la última corrección de código productivo |
| `npx tsc --noEmit -p C:/Users/pc/.codex/backups/fullpos-ecf-selfservice-20261114/tsconfig.changed-test.json` | PASS; tipos estrictos de los cuatro specs principales nuevos/modificados |
| `npm --workspace apps/api test -- --testPathPatterns=src/ecf/ --forceExit` con PostgreSQL opt-in | PASS, 160 suites / 2,054 pruebas; incluye la nueva carrera de preparación |
| `npm --workspace apps/api test -- --runTestsByPath src/sales/sales-ecf-atomic-postgres.integration-spec.ts src/ecf/documents/ecf-pos-readiness-postgres.integration-spec.ts src/ecf/documents/ecf-sequence-postgres.integration-spec.ts src/ecf/documents/ecf-environment-isolation-postgres.integration-spec.ts` | PASS, 4 suites / 39 pruebas después de la corrección final |
| `npm --workspace apps/api run test:e2e -- --runTestsByPath src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts src/ecf/ecf-documents-http.e2e-spec.ts src/ecf/pos/legacy-pos-compatibility-http.e2e-spec.ts --forceExit` | PASS final, 3 suites / 44 pruebas, 68.679 s; proveedor exclusivamente local |
| `npm --workspace apps/api test` | PASS final, 240 suites / 2,887 pruebas, 59.373 s; 52 suites / 555 pruebas opt-in omitidas en esta ejecución general |
| `npm --workspace apps/api run audit:tenant-inventory` | PASS; 168 modelos inventariados |
| `npm --workspace apps/api run audit:endpoints` | PASS; 431 endpoints inventariados |
| `npm --workspace apps/api run audit:unsafe-tenant-queries:warn` | PASS en modo aviso; 0 errores / 298 avisos heurísticos; no significa una auditoría global sin avisos |
| `flutter analyze --no-pub` | PASS final; No issues found, 62.6 s |
| `flutter test --no-pub --reporter compact` | PASS; 2,266 pruebas y 9 omitidas por el runner, antes de las dos nuevas regresiones de cambio de sesión |
| `flutter test --no-pub test/features/ecf/ecf_repository_company_scope_test.dart test/features/ecf/ecf_sequence_range_section_test.dart test/features/ecf/ecf_dgii_habilitation_page_test.dart test/features/ecf/ecf_repository_test.dart test/features/ecf/ecf_dosa_activation_status_test.dart test/modules/cotizaciones/billing_ecf_selector_visible_test.dart test/modules/cotizaciones/billing_ecf_checkout_gate_test.dart` | PASS final; 128 pruebas, con las dos regresiones nuevas y capturas usando AppTheme.light |
| `flutter build web --release --no-pub --dart-define=API_BASE_URL=http://127.0.0.1:4001` | PASS, 133.4 s; artefacto local, no imagen productiva ni publicación |
| `git diff --check` | PASS; revisión de diff sin cambios a Prisma, dependencias, CI ni configuración productiva |

La suite general no activa todas las integraciones opcionales; las fiscales
PostgreSQL y HTTP indicadas arriba sí se ejecutaron expresamente. Los
conteos de suites se superponen; no se suman para inventar un total de cobertura.
Los archivos privados de evidencia correspondientes son `api-build-final.log`,
`types-changed-tests-final.log`, `ecf-postgres-final-green.log`,
`postgres-focused-final.log`, `flutter-all.log`, `flutter-scoped-final-green.log`,
`flutter-analyze-final.log`, `flutter-web-final.log`, `http-final-green.log`,
`backend-unit-final-green.log` y `audit-*.log`.

Los avisos de consultas son heurísticos, no fugas demostradas. La consulta nueva
de autorizaciones marcada por el scanner contiene `where: {companyId,
environment, documentType}` y fue revisada junto con las regresiones multiempresa.
No se cambió el scanner ni se silenció ningún aviso. La revisión global de los
otros módulos permanece fuera del alcance de esta corrección fiscal.
La compilación JavaScript web advierte sobre incompatibilidades del dry-run WASM
en dependencias existentes; el objetivo web solicitado compiló correctamente.

Incidencias durante la validación, declaradas:

- Las fixtures E31 antiguas sin vencimiento fallaron con la regla nueva. Se
  completaron con fechas sintéticas consistentes; no se desactivó la validación.
- Una fixture de ausencia de rango tampoco tenía autorización; ahora separa
  ambos estados para seguir probando el error específico.
- Flutter concurrente causó una colisión de copia de sqlite3.dll; se repitieron
  los comandos secuencialmente. Una compilación API paralela a PostgreSQL
  encontró el DLL de Prisma ocupado; se recompiló fuera de las pruebas.
- Una invocación de Flutter incluyó un nombre inexistente de test; se corrigió
  la ruta y la ejecución válida pasó (126 pruebas).
- Las suites opt-in PostgreSQL existentes retienen handles de Jest al acabar;
  se usa `--forceExit`, como en el gate HTTP del proyecto. No se ocultaron
  aserciones fallidas ni se alteraron controles de tenant para obtener PASS.
- Una ejecución concurrente de Supertest sufrió ECONNRESET: el servidor sin
  `listen` podía cerrarse automáticamente al terminar otra petición. Las dos
  suites modificadas mantienen ahora un listener efímero en 127.0.0.1 hasta
  `app.close()`, conservando las peticiones simultáneas y todas sus aserciones.

## Archivos modificados

Implementación backend:

```text
apps/api/src/ecf/documents/ecf-dgii-authorized-sequences.policy.ts
apps/api/src/ecf/documents/ecf-document-query.service.ts
apps/api/src/ecf/documents/ecf-emission.service.ts
apps/api/src/ecf/documents/ecf-preparation.service.ts
apps/api/src/ecf/documents/ecf-sequence.service.ts
apps/api/src/ecf/portal/ecf-portal-enrollment.service.ts
apps/api/src/sales/sales.service.ts
```

Cliente existente:

```text
apps/fulltech_app/lib/features/ecf/data/ecf_repository.dart
apps/fulltech_app/lib/features/ecf/ecf_models.dart
apps/fulltech_app/lib/features/ecf/ui/ecf_dgii_habilitation_page.dart
apps/fulltech_app/lib/features/ecf/ui/flow/ecf_dosa_activation_status.dart
apps/fulltech_app/lib/features/ecf/ui/flow/ecf_sequence_range_section.dart
apps/fulltech_app/lib/modules/cotizaciones/cotizaciones_screen.dart
```

Regresiones y fixtures sintéticas (las fixtures antiguas se completan con fechas
de prueba; no son cambios a registros ni contratos productivos):

```text
apps/api/src/ecf/documents/ecf-credit-note-postgres.integration-spec.ts
apps/api/src/ecf/documents/ecf-dgii-authorized-sequences.policy.spec.ts
apps/api/src/ecf/documents/ecf-document-query-postgres.integration-spec.ts
apps/api/src/ecf/documents/ecf-e32-consumo-postgres.integration-spec.ts
apps/api/src/ecf/documents/ecf-fiscal-document-persistence-postgres.integration-spec.ts
apps/api/src/ecf/documents/ecf-legacy-test-classification-postgres.integration-spec.ts
apps/api/src/ecf/documents/ecf-pos-readiness-postgres.integration-spec.ts
apps/api/src/ecf/documents/ecf-pos-readiness.spec.ts
apps/api/src/ecf/documents/ecf-preparation-postgres.integration-spec.ts
apps/api/src/ecf/documents/ecf-sequence-postgres.integration-spec.ts
apps/api/src/ecf/ecf-documents-http.e2e-spec.ts
apps/api/src/ecf/integration/multi-company-e2e.integration-spec.ts
apps/api/src/ecf/portal/ecf-portal-enrollment-postgres.integration-spec.ts
apps/api/src/ecf/portal/ecf-portal-enrollment.service.spec.ts
apps/api/src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts
apps/api/src/sales/sales-ecf-atomic-postgres.integration-spec.ts
apps/fulltech_app/test/features/ecf/ecf_dgii_habilitation_page_test.dart
apps/fulltech_app/test/features/ecf/ecf_repository_test.dart
apps/fulltech_app/test/features/ecf/ecf_repository_company_scope_test.dart
apps/fulltech_app/test/features/ecf/ecf_sequence_range_section_test.dart
apps/fulltech_app/test/preview/ecf_selfservice_preview.dart
```

Documentación y evidencia visual:

```text
docs/ARCHITECTURE.md
docs/PRODUCT_SPEC.md
docs/EXECUTION_STATE.md
docs/ecf/ECF_SELF_SERVICE_HARDENING_2026-11-14.md
docs/ecf/selfservice-visual-2026-11-14/production-e31-320.png
docs/ecf/selfservice-visual-2026-11-14/production-e31-390.png
docs/ecf/selfservice-visual-2026-11-14/production-e31-1280.png
docs/ecf/selfservice-visual-2026-11-14/test-numbering-390.png
docs/ecf/selfservice-visual-2026-11-14/test-numbering-834.png
docs/ecf/selfservice-visual-2026-11-14/test-numbering-1280.png
```

Los generadores de inventario/matriz y algunas pruebas crean archivos de
evidencia ajenos al alcance. Solo ese ruido generado por esta ejecución se
restauró al HEAD de este worktree limpio; no se tocaron cambios de otro autor.

## Requisitos verificados

| Solicitud | Evidencia / límite |
| --- | --- |
| Vencimiento E31 una sola vez | Autorización propia → rango nuevo/renovado → venta → payload → proyección fiscal de impresión; fechas inválidas/contradictorias rechazadas |
| Independencia de empresas | Dos altas nuevas por rutas reales, sesiones/tickets propios, credenciales/fechas/numeración distintas, concurrencia y 404 ajeno |
| Asistente completo existente | Sesión externa simulada, webhook firmado, consentimiento, activación explícita y numeración productiva sin paso TEST comercial adicional |
| Segunda empresa ficticia local | Completado para dos empresas nuevas, además de las fixtures multiempresa anteriores; ninguna emisión externa |
| Barreras y recuperación | Suites de permisos, certificación, credenciales, autorizaciones, vigencia, rango agotado, atomicidad, replay/timeout y E34; revocación y carrera E31 añadidas |
| UI compacta | Mismos componentes/recorrido; 128 pruebas Flutter focalizadas y seis capturas de widgets; sesión interactiva de navegador pendiente por bloqueo de herramienta |
| Pruebas completas | Backend/PostgreSQL/HTTP/Flutter, análisis y compilaciones locales; se declaran omisiones del runner y simulaciones externas |
| Conservar trabajo y proteger FULLTECH | Rama nueva desde PR44; otros worktrees intactos; sin operación productiva, nueva migración, cambio de contador ni documento histórico |
| No desplegar ni unir | Sin commit/push/merge/deploy en esta tarea; el dueño conserva la autorización de cualquier nuevo despliegue |

## Estado

Correcciones locales implementadas y revalidadas; análisis, compilaciones y
suites anteriores PASS. Diff revisado, sin cambios a dependencias/esquema,
credenciales productivas, secuencias reales ni otros worktrees.
QA interactiva de navegador pendiente por bloqueo de herramienta. Las capturas
de widgets están verificadas y no sustituyen esa comprobación.
Producción y cualquier nuevo despliegue: **NO-GO**, hasta autorización expresa.
Sin merge, push, deploy, reinicios, cambios de entorno, migraciones o facturas
reales en producción. FULLTECH SRL no se consultó ni modificó en esta tarea.
Rama local con cambios pendientes de commit; no se publicó ni ejecutó un nuevo
workflow de GitHub Actions en esta tarea.
