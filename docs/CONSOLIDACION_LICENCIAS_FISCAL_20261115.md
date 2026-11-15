# Consolidación de licencias CRM y facturación electrónica

## Objetivo y procedencia

Preparar una versión que conserve tanto el diseño y el autoservicio e-CF del
PR45 como la administración de licencias CRM que se incorporó por separado al
backend activo. No implica una autorización de deploy.

- Base:221d530c5a4b0ad13fb711195ef70524293db841, merge del PR45 a production-main.
- Licencias:873169126db58eaf99f1cc32d56a7ebc6f5ecbde, cuyo padre es3217f0cd.
- Worktree:C:/src/fullpos-license-fiscal-20261115.
- Rama:agent/consolidate-license-fiscal-20261115.

Se hace una unión de historias sin squash/rebase ni descarte de commits. La
previsualización no encontró conflictos. El commit de licencias incorpora seis
archivos; no modifica schema.prisma ni migraciones. Su servicio/controller,
registro de módulo y métodos compartidos conservan el contenido original.

El worktree original de licencias tiene11 archivos pendientes de actividad de
usuarios, incluyendo una migración sin publicar. Ese trabajo se registra por
hash y queda fuera de esta consolidación; no se limpia ni se sobrescribe.
La comprobación posterior detectó nuevas ediciones de ese otro trabajo en
company-activity.service.ts y company-activity.integration-spec.ts, con el mismo
HEAD87316912. Por tanto, no se afirma que el worktree original esté congelado:
hay un escritor independiente activo y esta tarea no escribe allí. La fuente
de esta unión es exclusivamente el commit inmutable87316912.

## Flujo y seguridad

El puente privado CRM accede a `/license/integrations/crm` mediante el secreto
administrativo ya existente. Cada ruta comprueba ese secreto antes de llamar
al servicio. Un JWT ordinario no sustituye esa autenticación. Los comandos
requieren además el flag existenteCRM_LICENSE_MANAGEMENT_ENABLED; no se activa
ningún flag ni se modifica ninguna credencial en este trabajo.

Los cambios de licencia se hacen bajo transacción y bloqueos por empresa,
validación de versión y UUID de operación. El recibo de auditoría se confirma
en la misma transacción. Los reintentos no repiten la mutación, los límites
no bajan por debajo del uso real y una suspensión revoca solo sesiones de la
empresa seleccionada. No se reescriben comprobantes, rangos o contadores fiscales.

La modificación de la proyección compartida conserva sus resultados anteriores;
el CRM adapta por separado las fechas de trials vencidos sin cambiar el DTO
legacy. El listado administrativo multiempresa sigue siendo exclusivo del
puente privado autenticado, nunca del contexto JWT de un cliente.

## Cambios exclusivos de consolidación

- Prueba HTTP con Nest/supertest y validación real del secreto: rechaza ausencia,
  valor incorrecto y JWT ordinario en las cuatro rutas; comprueba capacidades y
  paso del ID de empresa al servicio. Los delegates de negocio se simulan aquí;
  sus transacciones se comprueban en las pruebas PostgreSQL independientes.
- La fixture CRM admite también56701, siempre loopback y nombre exacto
  crm_license_fixture, sin query/hash. No se amplía el acceso a destinos remotos.
- CI añade PostgreSQL separado para esa fixture y ejecuta las pruebas CRM en
  la suite habitual, además de su nuevo límite HTTP. La base fiscal se conserva.
- Prueba cruzada PostgreSQL: las cuatro acciones CRM conservan íntegros los
  rangos E31, su siguiente número, vencimiento y autorización SANDBOX de dos
  empresas ficticias; el cambio de nombre no altera el RNC ni la segunda empresa.
- Se actualiza este informe y el estado de ejecución. Ningún cambio Flutter,
  sitio público, esquema, migración, lockfile ni Dockerfile.

## Validación local

Solo Docker Desktop y dos bases desechables en127.0.0.1:56701:
fullpos_ecf_ephemeral_test y crm_license_fixture. Credenciales generadas fuera
de Git; emisión externa desactivada. Puerto55519 de otro trabajo no se reutiliza.
Las migraciones existentes se aplicaron únicamente a esas bases nuevas.

Compilación `npm run api:build`:PASS. Pruebas HTTP CRM:6 PASS.
Regresión PostgreSQL de licencias:12 PASS. Admisión atómica, readiness y
devoluciones fiscales PostgreSQL:32 PASS en3 suites.
Verificación del lock Docker:756 paquetes PASS. Diff checks PASS.
Auditorías generadas fuera del árbol fuente:168 modelos y435 endpoints. El
scanner marca las cuatro rutas CRM como «sin guard detectado» porque no analiza
la llamada manualassertAdminSecret; se revisó esa llamada en cada ruta y las
seis pruebas HTTP demuestran rechazo antes del servicio para credenciales
ausentes/incorrectas y JWT ordinario. No se altera el scanner para ocultarlo.
YAML de CI validado conjs-yaml de las dependencias existentes. Los intentos de
usarPyYAML/yaml no estaban disponibles; no se instaló ninguna dependencia.
Suite completa backend:3353 PASS,101 omitidas explícitas,280 suites aprobadas y
13 omitidas (300.688s). La prueba cruzada añadida después del inicio de esa
ejecución se ejecutó por separado:1 PASS. No se cuenta dentro de las3353.
Regresión HTTP fiscal/compatibilidad POS:44 PASS en3 suites (114.852s).
Typecheck adicional de las tres regresiones CRM:PASS conTypeScript instalado,
sin emisión de archivos y sin modificar eltsconfig del proyecto.

Aceptación con la aplicación Nest compilada completa, API local4873 y dos
empresas ficticias creadas por HTTP:8 comprobaciones PASS. Incluye salud,
autenticación del puente, registro multiempresa, compatibilidad de/license,
comando real idempotente, rechazo de versión antigua y revocación de sesión
solo de la empresa suspendida. El flag CRM se habilita exclusivamente en ese
proceso local con un secreto generado para la prueba; ningún flag productivo
cambia. No hay llamadas a un proveedor fiscal. El proceso local se detuvo al
terminar; las fixtures quedan únicamente en la base desechable de esta tarea.

Comandos y runners ejecutados:

```text
npm ci
npm run api:build
npx prisma migrate deploy             # dos bases locales nuevas, nunca producción
npm test -- --runTestsByPath src/license/crm-license.integration-spec.ts --forceExit
npm run test:e2e -- --runTestsByPath src/license/crm-license-http.e2e-spec.ts --forceExit
npm test -- --runTestsByPath src/license/crm-license-fiscal-postgres.integration-spec.ts --forceExit
npm test -- --forceExit
npm run test:e2e -- --runTestsByPath src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts src/ecf/ecf-documents-http.e2e-spec.ts src/ecf/pos/legacy-pos-compatibility-http.e2e-spec.ts --forceExit
npx tsc -p <backup privado>/tsconfig.regression.json
node scripts/release/sync_api_docker_lock.mjs --check
node <backup privado>/run_audits.cjs
python <backup privado>/application_smoke.py
git diff --check
git diff --cached --check
```

El primer intento de crear la base CRM coincidió con el reinicio de
inicialización de PostgreSQL y falló con«database system is shutting down».
Se esperó su arranque definitivo y se creó/migró correctamente; no se eliminó
ni reutilizó ninguna base ajena. Las advertencias ts-jest deisolatedModules y
la recomendación de Jest sobre handles se conservan en logs; todas las
ejecuciones indicadas terminaron con código0.

Logs y hashes privados:
C:/Users/pc/.codex/backups/fullpos-license-fiscal-20261115/.

## Límites y control del propietario

No se cambia ni se reinicia el backend activo; no se toca la base productiva,
credenciales, variables, permisos fiscales, numeraciones ni documentos reales.
La PWA publicada del PR45 permanece identificada por su digest anterior.
La imagen backend publicada de221d530c no debe reemplazar al backend de licencias
hasta construir/verificar la versión consolidada y autorizar su publicación.

La aceptación UI/PDF/offline del PR45 se conserva como evidencia previa; no se
afirma una nueva ejecución de dispositivos/impresoras ni emisión DGII externa.
Los detalles visuales ya documentados no se modifican aquí.

Resultado local:GO para revisión de la unión. Los controles GitHub Actions del
nuevo head son un requisito separado: consultar el PR y no inferirlos de los
resultados del PR45. Deploy sigue NO-GO sin autorización expresa y sin una
imagen backend construida/verificada desde la versión consolidada.
El propietario conserva merge aproduction-main y deploy; la unión aquí se
realiza únicamente en la rama aislada de trabajo.
