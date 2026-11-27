# Guardian por empresa: defaults y administración — 27/11/2026

## Alcance y decisiones

Implementación local solicitada por el propietario: monitoreo habilitado por
defecto para empresas actuales y futuras, conservando desactivaciones manuales
(confirmación explícita en este chat). No se autoriza aquí publicación, migración
compartida, cambio de entorno productivo ni emisión de avisos reales de prueba.

FullPOS: `C:/t/fp-guardian-companies-20261127`, rama
`agent/guardian-empresas-20261127`, base `ebc9486a6bba430efb929fe5ed5b5fe335b5cda7`.
CRM: `C:/t/crm-guardian-mobile-20261127`, rama
`agent/guardian-acceso-movil-20261127`, base `136e2ed8b99e197fde974aaaed87edd33b6a8d5f`.
Los cambios previos propios de acceso móvil a Guardian se conservan. El trabajo
de cobro/recuperación de FullPOS sigue separado en su worktree; no se sobrescribió.
No se editó el worktree de voz del otro agente.

## Hallazgos verificados

- Prisma definía `Company.guardianEnabled=false` por defecto. La política de
  ingesta exige el valor real true: no era solo una etiqueta equivocada del CRM.
- La concesión automática tiene otro interruptor y alcance de empresas. La
  revisión productiva **solo lectura** mostró alcance restringido, interruptor
  automático habilitado y diagnóstico IA desactivado. No se leyeron ni imprimieron
  valores de credenciales. No se modificó configuración ni base productiva.
- La pantalla mezclaba un bloque técnico extenso con incidencias globales y la
  lista de empresas al final. No abría un detalle de empresa al tocar la fila.
- Cero incidencias no demuestra conexión, salud del equipo ni entrega de avisos.

## Cambios

- Default de base true y migración nueva `20261127190000_guardian_default_enabled`.
  Solo modifica campos Guardian de empresas no archivadas que conservan false
  con fuente de decisión NULL. No modifica desactivaciones explícitas, licencias,
  datos fiscales, numeraciones, inventario ni históricos de documentos.
- Alcance automático predeterminado `*` cuando la variable no existe; una lista
  explícita, incluso vacía, conserva su autoridad. El interruptor maestro sigue
  apagado por defecto. No se eliminan autenticación, elegibilidad ni cuotas.
- Proyección aditiva del panel: equipos con credencial habilitada, no revocada ni
  vencida; último uso; motivo de bloqueo de conexión automática; desactivación
  manual. No expone hashes ni claves. `lastContactAt` no es una garantía de conexión
  en tiempo real. Se conserva el límite previo de 1,000 empresas de esta consulta.
- CRM prioriza empresas, buscador y filtros. Cabecera fija con actualizar y acceso
  a incidencias. Detalle con activación, equipos, último contacto, gravedad y
  listado de incidencias filtrado por el ID de empresa en el servidor.
- Las acciones mantienen confirmación y motivo; no se actualiza la vista como
  guardada hasta recibir respuesta. Se bloquean acciones simultáneas. No se
  ocultan errores de consulta ni se declara salud ante una falla.
- Diagnóstico, evidencias, avisos, intentos de entrega e historial permanecen
  disponibles en el detalle de incidencia. Los estados técnicos están plegados.
- El proxy existente del CRM ya admite estas consultas y campos aditivos: no
  necesita cambios de backend ni credenciales nuevas en Flutter.

## Archivos FullPOS

- `apps/api/prisma/schema.prisma`
- `apps/api/prisma/migrations/20261127190000_guardian_default_enabled/migration.sql`
- `apps/api/src/guardian/guardian.auto-enrollment.config.ts`
- `apps/api/src/guardian/guardian.auto-enrollment.spec.ts`
- `apps/api/src/guardian/guardian.company.policy.ts` (comentario de política)
- `apps/api/src/guardian/guardian.company.optin.pg.integration-spec.ts`
- `apps/api/src/guardian/guardian.defaults.pg.integration-spec.ts`
- `apps/api/src/guardian/guardian.platform.service.ts`
- `docs/ARCHITECTURE.md`
- `docs/PRODUCT_SPEC.md`
- Este informe.

## Validación ejecutada

- `npm run api:build`: PASS, Prisma generate y TypeScript.
- `npx prisma validate`: PASS.
- `npx prisma migrate deploy`: 99 migraciones completas en bases nuevas dentro
  del contenedor propio `fullpos_guardian_defaults_20261127`, loopback 5569.
  Nunca se usó una base compartida.
- `npm --workspace apps/api test -- --silent`: 279 suites aprobadas,
  3,213 pruebas aprobadas, 614 omitidas por condiciones de sus suites.
- Suite PostgreSQL nueva de defaults: 2 PASS; comprueba default futuro, migración,
  repetición, preservación de decisiones/archivadas/vencimientos de licencia y
  proyección de credenciales vigentes sin secretos.
- Suites PostgreSQL de política por empresa y plataforma: 19 PASS.
- Suite PostgreSQL de reparación Guardian en su base local exigida
  `guardian_repair_test`: 4 PASS.
- Revalidación final `--testPathPatterns='src/guardian/.*spec.ts'`: 335 PASS,
  93 omitidas por sus condiciones de ejecución; incluye la nueva suite de defaults.
- CRM proxy: `npm test -- tests/guardian.test.js`: 11 PASS.
- Flutter CRM: `flutter test --no-pub`: 436 PASS, 5 omitidas por UAT no configurado.
- Guardian y navegación: 9 PASS, incluyendo errores, datos antiguos sin campos
  nuevos, consulta por empresa, cancelación, confirmación, error al guardar y
  autorización de acceso móvil.
- Análisis de pantalla y pruebas Guardian: cero incidencias. Análisis general
  con `--no-fatal-infos`: sin errores ni warnings; 54 avisos informativos de estilo
  existentes fuera del cambio Guardian, no corregidos por estar fuera de alcance.
- Android debug compilado. Capturas de widgets renderizados a 390x844 y 1280x900,
  con datos ficticios: lista, espera de equipos, desactivación y detalle de problema.
- Hot reload y navegación real de solo lectura en Android contra el backend CRM
  existente: lista de empresas y detalle; no se pulsó confirmar activación.

Dos incidencias de ejecución se corrigieron sin alterar pruebas: una primera
ejecución con la variable PostgreSQL genérica encontró la barrera de nombre de
base de la suite de reparación; se repitió en su base dedicada. La regeneración
Prisma concurrente con pruebas bloqueó la DLL de Windows; se repitieron generación
y pruebas secuencialmente. La regresión general final y las suites locales pasaron.
Los fallos iniciales de prueba de interfaz se corrigieron y se repitió la validación.

## Publicación posterior: pendiente, no ejecutada

1. Revisar y confirmar los diffs y los dos PR; conservar este trabajo y el de caja
   al integrar, sin reemplazar carpetas ni worktrees.
2. Antes de autorizar la migración productiva, respaldar la base y obtener conteos
   de empresas con false/fuente NULL, desactivaciones explícitas y archivadas.
3. Autorizar y aplicar solo la migración nueva. El servidor tiene migración
   automática desactivada: desplegar código por sí solo no aplica este cambio.
4. El alcance productivo actual es una lista explícita. Para todas las empresas
   elegibles debe revisarse y aprobarse `GUARDIAN_AUTO_ENROLL_COMPANIES=*` en el
   backend FullPOS; no basta con cambiar el default de código. No tocar tokens,
   permisos fiscales ni licencias. No activar diagnóstico IA automáticamente.
5. Publicar backend y cliente CRM compatibles; la interfaz funciona con campos
   antiguos, mostrándolos como sin comprobar. No requiere nueva PWA FullPOS.
6. Comprobar concesión, último contacto, incidente controlado y entrega real de
   aviso con destinatario autorizado. Una prueba simulada no acredita WhatsApp.
7. Si hay regresión, restaurar imagen/alcance previos verificados. No invertir la
   migración mediante UPDATE masivo a false: perdería decisiones administrativas.
   La reversión de datos necesita respaldo y comparación por fuente/fecha.

Resultado: implementación local validada para revisión. **NO-GO para activar o
desplegar automáticamente**: faltan revisión/autorización de PR, migración y
alcance productivo, más comprobación posterior de enrolamiento/avisos reales.
