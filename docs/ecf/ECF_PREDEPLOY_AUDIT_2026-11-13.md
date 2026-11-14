# Auditoría de preparación e-CF y migración manual — 13/11/2026

## Resultado verificado

HECHO: las migraciones fiscales autorizadas ya están aplicadas en producción.
Se conservó la historia previa de migraciones, el contenedor/API en ejecución,
los datos fiscales existentes y la configuración de las empresas. Se clasificaron
únicamente cinco ensayos históricos revisados de FULLTECH como Sandbox, sin
convertirlos en facturas aceptadas. No se ejecutó deploy, reinicio, seed, cobro,
venta nueva ni llamada fiscal externa.

El código candidato incluye el trabajo fiscal previo y los cierres de auditoría,
con la actualización adicional de Astro expresamente aprobada por el usuario.
El propietario autorizó la publicación Git en la continuación de esta tarea:
commit50617f39, [PR41](https://github.com/JUNIORPRUEVA/DaleVenta_POS/pull/41)
abierto hacia production-main. La integración y activación productiva siguen
pendientes; este informe no autoriza un deploy ni declara aceptación sobre
impresoras físicas. Véase la [guía operativa](ECF_RELEASE_OPERATOR_2026-11-13.md).

## Alcance y criterios

Preservar trabajos/commits y producción; identificar realmente servidor, base y
servicios; respaldar y ensayar antes de migrar; aplicar SQL original manualmente
con límites y verificar el ledger; mantener aislamiento por empresa/ambiente,
Normal sin envío fiscal, recuperación idempotente y devoluciones E34; comprobar
compilación, regresión e interfaz; preparar un despliegue manual API primero.
Plan ejecutado: auditoría → respaldo → ensayo restaurado → aplicación manual
autorizada → verificación → candidato desde production-main → correcciones
mínimas → pruebas → revisión de diferencias y documentación.

## Conservación del trabajo y base de integración

- Candidato: C:/src/fullpos-ecf-predeploy-20261113, rama
  agent/ecf-predeploy-20261113, base production-main
  cada11f8bb3bb2e749810c3d9213bb84f9471d44, confirmada otra vez por fetch.
- El checkout anterior finalesdaleventas conserva sus218 archivos originales
  verificados byte a byte. No se reescribió su rama.
- La rama anterior y production-main tenían11 commits exclusivos cada una y
 27 archivos con conflictos en la vista previa. Se trasladó solamente el delta
  de trabajo no confirmado sobre la rama actual mediante git apply --3way;
  cero conflictos. No se integraron a ciegas los commits antiguos.
- Bundle Git verificado de261 referencias, patch binario y copias de trabajo en
  C:/Users/pc/.codex/backups/daleventas-ecf-predeploy-20261113T2334Z.
- Se excluyeron archivos temporales de sondeo, logs, node_modules y artefactos.
  No se modificó el código de páginas públicas/auth del sitio ni se revirtió el
  POS/onboarding actual. Los cambios recibidos se atribuyen como trabajo previo.

## Identidad y seguridad de producción

Servidor srv902744; servicios daleventapos_backend, daleventapos_pwa y
daleventapos_database. PostgreSQL17; API Node20.20.2/Prisma5.22.
El host de base de datos se resolvió y se contrastó con la tarea/VIP del servicio,
además de la identidad de base del contenedor. No se imprimió DATABASE_URL,
variables de entorno, contraseñas, claves API o el contenido de la clave SSH.
El montaje de secretos y los servicios no relacionados permanecieron intactos.

Respaldo privado en servidor:
/root/fullpos-safety/ecf-predeploy-20261113T2340Z. Directorio0700, archivos0600.
Copias locales de ambos dumps e imágenes con SHA256 coincidente y ACL privada:

| Archivo | SHA256 |
| --- | --- |
| database-before.dump | 73fd39b44b79f5d2a7e7027562957d19c345cba45fc48a04ee8fe1765e002868 |
| database-immediately-before.dump | f4ed7420d873004dfe787f4e468058eddc6bd5f8da7239aa5df6e3783ca8d0f3 |
| running-api-and-pwa-images.tar.gz | d78a8f4ac071e910b9bd9d1c3366bdd37256014c1198bde6412026fc0b0df095 |

Se restauró el dump en PostgreSQL17 local aislado. Se ensayaron tanto Prisma
migrate deploy como la transacción manual/resolve antes de producción.
Los respaldos de configuración que contienen secretos permanecen privados en
el servidor; no forman parte del repositorio.

## Migración manual aplicada

| Migración | SHA256 original |
| --- | --- |
| 20261113040000_ecf_numbering_environment | 1523a7fd7199627535a1408197e922d6f0761d86872d2acf0ec0f081811691d6 |
| 20261113050000_ecf_reviewed_legacy_test_classification | 649d2845b063f1e5eb5f7db669afbd73fd545d8e934060e80ff22a3be5920c4f |
| 20261113060000_ecf_public_print_stamp | 76de09a3c058016f8dbaa3ccd89d712068ae0043248af9e891720e5a2624ce49 |

SQL original en una transacción con advisory lock, lock_timeout3s y
statement_timeout30s. Registro posterior mediante Prisma5.22 migrate resolve
--applied, con los archivos/checksums originales. Los223 registros anteriores
permanecen:226 en total, sin migraciones fallidas sin resolver. Hay140 nombres
históricos fuera de la base local consolidada: no se borraron ni se recrearon.

Verificación: API /health correcto, mismo contenedor5fe17a2dc313 e imagen
sha256:5b6cffc9d31f0cfc30856070091245cdb162f58c555e8a66d9879d923ca9d0f0;
automigraciones deshabilitadas. No reset/db push/seed/DROP ni reescritura de ventas.

## Revisión histórica de FULLTECH

Cinco documentos MANUAL sin venta asociada tenían evidencia de ensayo TEST
correlacionada. El plan revisado aplicado fue
c92f82949290be18dd9f2584019eec95315e0ba2a3baab224f9ee97c5031823c.
La diferencia respecto del plan previo fue recuperar timbres E32 válidos mediante
el parser corregido; no cambió identidad, evidencia ni asignación.

Se preservaron estado, fingerprint, contenido fiscal, e-NCF, asignaciones y
contadores originales. La clasificación actualizó ambiente, timbre público
validado y auditoría. El conteo global posterior fue5 documentos,5 revisados de
FULLTECH,0 sin ambiente. El archivo de plan anterior conservado en docs/ecf es histórico; el hash de
aplicación vigente es el indicado arriba y en la evidencia de esta auditoría.
Los siguientes originales E31=3/E32=3/E34=2 y sus
rangos históricos se conservaron. No se copió una autorización productiva a TEST.
La configuración de FULLTECH siguió Sandbox/productionEnabled=false; ambas
credenciales propias estaban presentes/activas sin revelar sus valores.

## Hallazgos corregidos en el candidato

- La activación confundía ensayos terminales revisados con facturas comerciales
  pendientes: ahora exige la evidencia auditada/fingerprint/manifest del ensayo
  MANUAL sin venta, sin conceder aceptación fiscal. Los resultados inciertos,
  comerciales y cualquier documento con ambiente NULL siguen bloqueando.
- Un nuevo rango Sandbox podía reutilizar numeración histórica clasificada.
  Registro, renovación y asignación contrastan el e-NCF y ledger original de la
  misma empresa/tipo con su contador y rechazan valores anteriores a esa frontera.
- npm audit detectó7 avisos runtime de API. Se actualizaron versiones compatibles
  de ajv/node-forge y transitivas, sin --force ni cambio de major de Nest/Prisma.
- Astro5 presentaba5 avisos, incluido uno crítico. Con aprobación explícita se
  fijó Astro7.4.12 y Node22.23.4-alpine; no se cambiaron páginas/layouts/auth.
- El Docker API resolvía versiones con npm install sin el lock raíz auditado.
  El generador proyecta756 paquetes desde ese lock a apps/api/package-lock.json;
  Docker usa npm ci y CI verifica --check. El lock raíz sigue siendo autoridad.
- Ambos Docker finales aceptan GIT_SHA para conservar la revisión del artefacto.
- Se añadió un control SSH reutilizable de solo lectura para checksums, salud,
  documentos sin ambiente y ajustes de despliegue/activación, sin mostrar secretos.

## Validaciones ejecutadas

Todas las mutaciones automatizadas usaron una base desechable local identificada;
la restauración de producción se utilizó solo para ensayo de migración/revisión.
Ningún test de limpieza se ejecutó sobre producción ni sobre el clon restaurado.

| Comando/comprobación | Resultado observado |
| --- | --- |
| npm run api:build | PASS en candidato final |
| npm --workspace apps/api test | 276 suites/3300 PASS;101 opt-in omitidos |
| Jest HTTP: dosa-emission-dispatch-http + ecf-documents-http, --runTestsByPath --runInBand --forceExit | 30 PASS, proveedor localhost |
| Jest PostgreSQL: clasificación, aislamiento, secuencias, recuperación DOSA y devolución E34 | 48 PASS/5 suites |
| npx prisma validate, apps/api, con URL efímera local | PASS Prisma5.22 |
| flutter analyze | Sin incidencias |
| flutter test test/features/ecf test/core/printing test/modules/ventas test/features/ventas test/modules/cotizaciones test/features/account/ecf_company_toggle_drawer_test.dart test/features/onboarding test/core/auth test/core/routing | 1117 PASS |
| flutter test test/modules/cotizaciones/billing_ecf_selector_visible_test.dart test/features/ecf/ecf_production_activation_action_test.dart test/features/ecf/ecf_sale_history_panel_test.dart | 14 PASS; capturas320/1280 inspeccionadas |
| flutter build web --release | PASS; fixture localhost, no artefacto para producción |
| npm run audit:tenant-inventory / audit:endpoints / audit:unsafe-tenant-queries:warn, workspace API |168 modelos/431 filas;296 avisos heurísticos/0 errores |
| node scripts/release/sync_api_docker_lock.mjs --check |756 paquetes verificados |
| docker build -f apps/api/Dockerfile -t fullpos-ecf-api-review:20261113 apps/api | PASS Linux Node20.20.2/Prisma5.22 |
| docker build --target website -f Dockerfile.public-web -t fullpos-ecf-astro-review:20261113 . | PASS Linux Node22.23.4; astro check0 errores/0 avisos,14 páginas |
| npm test en la etapa Docker Astro, tests montados solo lectura |11 PASS con Node22.23.4 |
| npm audit --omit=dev --json dentro de imagen API |0 avisos runtime |
| npm audit --json dentro de etapa Astro7 |0 avisos |
| scripts/release/verify_ecf_server_predeploy.ps1, PowerShell7 | Servidor/migraciones/salud correctos; bloquea activación por flags aún deshabilitados |

El primer prisma validate sin entorno falló por DATABASE_URL ausente; no era
un error de esquema. Se repitió con el destino efímero local verificado y pasó.
La suite general informa handles abiertos al finalizar; terminó con exit0.
Las suites HTTP requieren --forceExit por el harness ya documentado; no se
interpretó como confirmación de ausencia de handles. Hay11 avisos dev-only
(1 bajo/10 moderados) en herramientas API; no se afirma auditoría dev sin avisos.
Las capturas prueban widgets; no sustituyen aceptación de dispositivos reales.
No se volvió a modificar el transporte de impresoras y no se pidió repetir su
puesta en marcha. No se afirma una prueba física nueva del contenido fiscal.

## Límites y pendientes concretos

1. La rama está publicada con el commit50617f39 y el PR41 abierto. El propietario
   conserva la revisión y la integración; los controles de CI deben pasar antes
   de unirlo. No se ejecutó merge. autoDeploy=false está verificado en API y PWA.
2. En EasyPanel siguen desactivados DOSA_PRODUCTION_EMISSION_ENABLED y
   DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED. Se deben preparar bajo control del
   propietario y conservar RUN_MIGRATIONS=false. No se cambió configuración
   productiva ni se reiniciaron servicios para activar estos permisos.
3. La clave pública del asistente ya existe en la configuración PWA y EasyPanel
   la entrega como build argument; no falta pedirla ni reemplazarla.
4. Deploy manual y aceptación post-deploy corresponden al propietario. API
   compatible primero, PWA después. Cada empresa conserva activación/rangos propios.
5. Hasta desplegar la API compatible, no iniciar nuevos ensayos fiscales con
   el código antiguo. El chequeo previo vuelve a detectar documentos NULL
   que ese código pudiera crear entre la migración y el rollout.
6. Una comparación de esquema de solo lectura del clon restaurado mostró
   diferencias preexistentes fuera del cambio fiscal: defaults generados por DB,
   seis nombres de índice y unique de telemetry_outbox.dedupe_key. No se ejecutó
   ese diff ni se quitaron defaults/índices; requiere revisión independiente.

RECOMENDACIÓN: conservar esquema aditivo para rollback; después de distribuir
clientes con NORMAL, mantener API compatible o corregir hacia adelante. Restaurar
un dump antiguo puede perder ventas posteriores y exige otra autorización/plan.
La secuencia operativa está en [RELEASE](../RELEASE.md).

## Estado

Migración manual: aplicada y verificada. Candidato: validaciones locales
completadas según evidencia y código publicado en PR41. Integración,
activación/deploy: NO-GO hasta cerrar CI, configuración y aceptación pendientes.
Ningún despliegue ejecutado.

## Inventario de archivos

El inventario del commit de implementación50617f39 distingue trabajo recibido y cambios de esta auditoría, con
hashes del contenido candidato y del respaldo previo. Incluye las rutas reales
de código, pruebas, migraciones, documentación y evidencia visual.
[Inventario completo](ECF_PREDEPLOY_FILES_2026-11-13.json).
[Evidencia pública resumida](ECF_PREDEPLOY_EVIDENCE_2026-11-13.json).

## Fuentes externas consultadas

- [Prisma: migraciones y producción](https://www.prisma.io/docs/orm/v6/prisma-migrate/workflows/development-and-production). Se utilizó la CLI5.22 instalada y el ensayo restaurado como prueba operativa.
- [Astro: actualización a v7](https://docs.astro.build/en/guides/upgrade-to/v7/), junto con engines del paquete7.4.12 y ejecución real con Node22.23.4.
- [Aviso oficial Astro/AVIF](https://github.com/withastro/astro/security/advisories/GHSA-26w7-cxv4-gfx2). Riesgo condicionado a optimización de imágenes no confiables; no se afirmó explotación en este sitio estático.
- [Aviso body-parser](https://github.com/expressjs/body-parser/security/advisories/GHSA-27r3-jxmh-p828), [multer](https://github.com/expressjs/multer/security/advisories/GHSA-q7qp-rjg7-q26m) y [Forge](https://github.com/digitalbazaar/forge/security/advisories/GHSA-6889-vf6x-f3g5). Las versiones finales también se verificaron mediante npm audit dentro de Linux.
- [EasyPanel: builders](https://easypanel.io/docs/builders), para contexto de build e inyección de variables como argumentos. La configuración se inspeccionó solo en lectura, con salida reducida a booleanos.

## Comprobación visual adicional de Astro7

Playwright library1.65.1 se instaló solo en el directorio temporal de auditoría,
sin añadir dependencias al producto. Se abrió Chrome headless con perfil
aislado y se bloquearon todas las solicitudes fuera de localhost.
Inicio, acceso, registro y preparación:8 vistas a1280/390px, HTTP200,
sin desbordamiento horizontal ni errores JavaScript. El enlace «Créala gratis»
llevó al formulario correcto. Las capturas de inicio/acceso/registro se
inspeccionaron visualmente; no se enviaron credenciales ni se creó una cuenta.
El navegador se cerró al finalizar.

La herramienta habitual de navegador estaba inaccesible. El control nativo
detectó actividad del usuario y no completó ninguna entrada; se utilizó por
eso el navegador aislado. La página de preparación usa role=status, no h1;
se corrigió esa suposición de la comprobación sin cambiar código del producto.
Los resultados y rutas de capturas están en la evidencia/inventario adjuntos.
[Referencia oficial de Playwright](https://playwright.dev/docs/api/class-browsertype),
[capturas](https://playwright.dev/docs/screenshots).

## Empaquetado combinado final

El Dockerfile.public-web completo compiló en Linux: Flutter, Astro y Nginx.
La imagen local fullpos-ecf-public-review:20261113 conservó la revisión
cada11f8-local-ecf-review. La prueba HTTP de solo lectura pasó17 rutas
(13 públicas Astro/4 Flutter),6 assets, manifest con inicio ./home y portal
de certificación con marcadores rellenados. No se hicieron peticiones API
ni llamadas fiscales. Los destinos y la clave ficticia son solo de QA.

El primer intento rechazó correctamente la clave ficticia pk_local por prefijo
inválido; el ensayo final usó el prefijo pk_test requerido y pasó. Docker
advierte por el nombre ARG DOSA_ASSISTANT_PUBLISHABLE_KEY: es la clave
pública ya prevista por el asistente, no una clave privada. No se suprimió
el aviso ni se introdujeron credenciales reales en la imagen de prueba.
