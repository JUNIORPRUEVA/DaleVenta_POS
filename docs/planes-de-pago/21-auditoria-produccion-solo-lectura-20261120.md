# Auditoría previa a publicación: licencias, esquema y operación

Fecha: 20/11/2026. Rama local: `agent/integrate-ia-planes-20261119`.
Revisión funcional auditada: `283bc63a`. Base remota: `e6e7e8fc`.

## Resultado y límites

**HECHO:** la auditoría de producción se ejecutó en modo solo lectura. No hubo
push, merge a `production-main`, despliegue, reinicio, migración, seed,
backfill, cambio de configuración, activación ni emisión fiscal.

La integración local conserva los siete commits fuente y sus correcciones
validadas. Este informe añade evidencia operativa, no cambia código ejecutable.
Las pruebas del 19/11 no se ejecutaron nuevamente ni se presentan como pruebas
externas de pagos, OCR, WhatsApp o DGII realizadas hoy.

**Estado:** GO para cerrar la auditoría; NO-GO para desplegar el sistema completo
de planes y cobros con la configuración actual.

## 1. Producción sigue en la imagen correcta

| Componente | Imagen observada |
| --- | --- |
| API | `ghcr.io/juniorprueva/fullpos-cloud-api@sha256:14443d35abd5c9c1c791d5837042cc01fc135192bd43bf5cf578981f69d04183` |
| PWA | `ghcr.io/juniorprueva/fullpos-cloud-web@sha256:e53bdb4f23c125d19957a55e4c63038853ee385f161d91c1afc761c13c8162e7` |

Ambas declaran la revisión `e6e7e8fc`, tienen una réplica activa y coinciden con
las imágenes aprobadas anteriormente. No se observa la regresión al artefacto
local de IA que motivó la recuperación del 17/11.

El snapshot anterior y posterior de servicios conserva los mismos identificadores
de contenedor, imágenes, versiones de servicio y hash de configuración protegida.
Las migraciones y el seed automáticos siguen desactivados. Las barreras globales
fiscales existentes y la activación de FULLTECH no se cambiaron.

La consulta HTTP local de salud del backend respondió 200. La consulta fiscal
de FULLTECH, con un administrador de esa empresa y transacción solo lectura,
devolvió `posReady=true`, tipos vendibles E31/E32, ambiente PRODUCTION,
certificación PRODUCTION_READY y vencimiento E31 `2027-12-31`.
Esto no es una nueva emisión ni una autorización para emitir una factura de prueba.

Los cambios nuevos de planes y consulta de cuenta IA continúan en la rama local;
no se debe confundir su integración Git con un despliegue de esa revisión.

## 2. Empresas y licencias reales

La enumeración utilizó el servicio administrativo de licencias existente.
Después, las lecturas operativas se limitaron al identificador de cada empresa.
La transacción PostgreSQL fue REPEATABLE READ y READ ONLY, con límites de tiempo.
Los datos personales y secretos devueltos internamente por proyecciones antiguas
no se exportaron en el informe; se conservaron solo los campos permitidos.

| Clasificación actual | Empresas |
| --- | ---: |
| Registradas | 38 |
| Licencia ACTIVE, vigente y utilizable | 7 |
| ACTIVE almacenado, pero periodo ya vencido | 3 |
| TRIAL cuyo periodo ya venció | 11 |
| BLOCKED | 17 |

Por eso hay 10 filas ACTIVE, pero solo siete licencias actualmente utilizables.
Las otras tres ya aparecen vencidas bajo la API actual: no son bloqueos creados
por la integración de planes. No se reactiva ninguna empresa por inferencia.

El esquema actual todavía no tiene `companies.plan_code` ni el catálogo nuevo
disponible. Los clientes trabajan con sus licencias y cupos anteriores. No se
debe asignar Básico a todos como parte de una migración de esquema.

Hay clientes vigentes con cupos y funciones superiores a Básico. Cambiarles el
plan sin una decisión individual podría recortar capacidad, impuestos o e-CF.
La decisión vigente permanece: conservar su situación anterior, sin backfill.

**Renovaciones posteriores:** conservar el acceso no equivale a asignar una
tarifa nueva. `LicenseRenewalService.snapshot()` no calcula una cuota de catálogo
para una empresa sin `planCode`, y `ensureOpenOrder()` no crea automáticamente
una orden sin ese dato. Antes de ofrecer renovación automática a esos clientes
debe acordarse su correspondencia comercial y sus excepciones individualmente;
no se deduce un precio ni se recortan funciones para completar ese campo.

### Proyección de compatibilidad del candidato

Se trasladaron únicamente los campos necesarios del snapshot a objetos locales
con identificadores y nombres sintéticos. No se copió la base productiva ni se
conectó el candidato a producción.

Se ejecutaron los servicios/políticas compilados de `283bc63a` sobre esa matriz:

- 38 empresas examinadas; 836 comprobaciones PASS.
- Las siete vigentes conservan acceso utilizable, fechas y cupos.
- Las empresas vencidas y bloqueadas mantienen su clasificación correspondiente.
- Ninguna recibe un código de plan automáticamente.
- Las empresas anteriores al catálogo no adquieren un nuevo límite de almacenes.
- Las consultas permanecen limitadas a la empresa de cada caso.

**Límite:** es una proyección determinista local sobre datos seleccionados, no una
prueba end-to-end nueva de cada negocio ni una migración aplicada a sus registros.
Los recorridos transaccionales con PostgreSQL, concurrencia y HTTP se acreditan
en el [informe de integración](20-integracion-ia-planes-20261119.md).

La relación privada por cliente, con sus valores y referencias de preservación,
se guarda fuera del repositorio. Este informe no publica nombres ni identificadores
de clientes; tampoco incluye claves, contactos o contraseñas.

## 3. Historial y migraciones pendientes

| Medición | Resultado |
| --- | ---: |
| Filas históricas de `_prisma_migrations` | 226 |
| Migraciones distintas finalizadas correctamente | 223 |
| Intentos históricos revertidos/resueltos | 3 |
| Migraciones del árbol fuente actual | 90 |
| Del árbol actual ya aplicadas | 83 |
| Del árbol actual pendientes | 7 |
| Intentos fallidos actuales sin resolver | 0 |

Existen 140 nombres de migraciones exitosas históricas fuera del árbol actual.
No se borra ese historial ni se vuelve a construir una base desde cero por esta
diferencia de inventario.

De las 83 migraciones comunes, 40 tienen checksum idéntico y 43 coinciden al
representar los mismos bytes SQL con finales CRLF en lugar de LF. No quedó una
diferencia de contenido sin explicación. La clasificación excluye los intentos
históricos revertidos: no deben sustituir el checksum de la ejecución exitosa
del mismo nombre. También se contrastó el archivo del artefacto para el caso
histórico de auditoría de secuencias e-CF.

**No se modificó ningún archivo de migración ni checksum de la base.** No se
ejecutó `migrate resolve`, `db push`, reset ni un intento de normalizar el historial.

Pendientes, en orden:

1. `20261115160000_add_company_usage_pulses`.
2. `20261116180000_license_plans_and_orders`.
3. `20261117170000_license_plan_requests`.
4. `20261117190000_evidence_insights`.
5. `20261117200000_provisional_activation`.
6. `20261117210000_evidence_validation`.
7. `20261119200000_license_override_multiwarehouse`.

Se revisaron sus SQL: incorporan estructura; no asignan planes ni cambian
estados/vencimientos existentes mediante UPDATE/DELETE/INSERT de clientes.
Eso no elimina la necesidad de respaldos, control de bloqueos y autorización
para aplicar DDL a producción. La colección de actividad continúa desactivada.

La API nueva no debe desplegarse sobre este esquema pendiente. `RUN_MIGRATIONS`
debe conservarse desactivado; el trabajo manual de esquema requiere una fase
autorizada independiente. Tampoco se ejecuta automáticamente el catálogo de
cuatro planes: su inicialización es otra escritura revisable, separada del seed
general y del backfill de empresas.

## 4. Hallazgos de pagos, archivos y servicios externos

### 4.1 Cuenta bancaria confirmada; configuración productiva pendiente

La cuenta y el tipo de cuenta no están declarados mediante las variables
`LICENSE_BANK_*` revisadas. Sin embargo, el candidato contiene datos comerciales
predefinidos en `paymentInstructions()` y una terminación autorizada de respaldo.

Por tanto, no es exacto decir que el candidato devuelve necesariamente
`configured=false` si falta la variable: puede mostrar los valores predefinidos
y devolver true. Tampoco sería exacto afirmar que toda validación bancaria falla
solo por esa ausencia, porque existe el respaldo en `authorizedAccountSuffix()`.

**Confirmado por el propietario el 20/11/2026:** usar la misma cuenta de la vista
local de Planes como cuenta oficial de cobro de suscripciones. Queda resuelta la
decisión comercial. Se propone preparar una configuración explícita y coherente
para pantalla y validación, sin inventar números ni imprimirlos en documentos de
repositorio. La confirmación no constituye un cambio productivo aplicado.

Se comprobó localmente sobre el servicio compilado que la cuenta predefinida
figura configurada, tiene suficientes dígitos y coincide con la terminación
autorizada por el validador. Tres comprobaciones PASS, sin mostrar el número.

### 4.2 Comprobantes: ubicación privada, pero sin persistencia garantizada

El destino por defecto sería `/app/storage/license-evidence`. No está configurado
explícitamente ni existe todavía. El padre `/app` es escribible por el proceso,
pero no está respaldado por un volumen de evidencias.

El único montaje observado del backend corresponde a secretos. No se debe
reutilizar ese montaje para guardar comprobantes. La ruta predeterminada está
fuera de `/uploads` público, lo que es correcto para privacidad; falta asegurar
su durabilidad frente a reemplazo del contenedor.

**Preparación propuesta:** volumen privado persistente para la ruta de evidencias,
permisos mínimos, comprobación de acceso y respaldo, preservando el montaje de
secretos existente. No se crea ni se monta nada en esta fase.

### 4.3 OCR de transferencias: integración operativa pendiente

La configuración efectiva revisada no declara ni URL del Media Engine ni pareja
Python/worker local; tampoco material de autenticación de OCR. Se usaron las
claves que realmente lee `LicenseOcrEngine`, no una variable genérica inventada.

En producción el modo es production y el interruptor de activación de pruebas
no está habilitado. El código solo permite ese atajo cuando NODE_ENV es test.
No debe activarse para simular que un pago ha sido validado.

**Consecuencia del candidato con la configuración actual:** sin OCR satisfactorio,
una subida no obtiene por ese atajo una activación automática; queda en el flujo
de revisión correspondiente. Antes de ofrecer el autoservicio de cobro como
completo hay que conectar y verificar el Media Engine, o acordar expresamente
la operación manual soportada. No se procesó un recibo real en esta auditoría.

### 4.4 WhatsApp: hay identificador de emisor, falta token efectivo

Se revisaron las alternativas reales de MetaCloudClient: licencia, Guardian y
WhatsApp existente. El identificador está presente, pero no un token efectivo
en esas alternativas. El modo dry-run no está habilitado explícitamente.

Con la configuración observada no se puede declarar disponible el envío de
avisos de planes. Al conectar credenciales en una fase posterior se debe
mantener primero dry-run explícito y autorizar por separado cualquier envío
real. No se envió WhatsApp ni se modificó una credencial.

### 4.5 Administración y contexto IA

La administración CRM de licencias está habilitada y existe material de secreto
administrativo. También existe el secreto de contexto de consulta IA. La presencia
no demuestra que el consumidor externo tenga el mismo valor ni que las nuevas
rutas estén desplegadas. La consulta `/ai/account` del candidato se probó localmente
en la fase anterior; no se presenta como una verificación externa efectiva de hoy.

## 5. Plan de la siguiente fase, todavía no ejecutado

1. Preparar los datos bancarios ya confirmados y acordar el alcance del cobro
   automático/manual, sin cambiar de cuenta por inferencia.
2. Localizar la integración OCR existente y preparar su conexión autorizada,
   sin compartir tokens por chat ni incorporarlos al repositorio.
3. Preparar la persistencia privada de evidencias y los controles de respaldo.
4. Preparar configuración propuesta de avisos en dry-run; no enviar mensajes.
5. Preparar respaldo verificable y procedimiento manual de las siete migraciones,
   con archivos originales y sin tocar numeración, contadores ni documentos e-CF.
6. Preparar la inicialización explícita del catálogo, sin asignar planes a clientes.
   Acordar por separado la renovación comercial de los clientes anteriores al
   catálogo; la inicialización técnica no autoriza cambiar sus contratos.
7. Con autorización de publicación, publicar la rama/PR y verificar sus controles.
8. Construir imágenes limpias e inmutables fuera de producción. Revisar contrato,
   cliente Prisma y contenido antes de preparar fuentes de EasyPanel.
9. Autorizar por separado cambios productivos, migraciones y despliegue; conservar
   imágenes de reversión y comparar las siete licencias vigentes antes/después.

Esta auditoría no autoriza ninguno de esos cambios productivos. La numeración
fiscal y las condiciones comerciales de clientes existentes no se deducen del
catálogo nuevo ni se sustituyen en masa.

## 6. Evidencias y comandos ejecutados

Evidencia privada, fuera de Git:
`C:/Users/pc/.codex/backups/fullpos-prepublish-readonly-20261120/`.

- `runtime-before.json` y `runtime-after.json`: infraestructura y hashes, sin valores secretos.
- `production-license-readonly.json`: snapshot limitado por empresa y metadatos de esquema.
- `migration-assessment-corrected.json`: historial exitoso separado de intentos revertidos;
  reemplaza la clasificación preliminar que no los separaba.
- `runtime-supplement.json`: configuración efectiva, salud y capacidades de FULLTECH.
- `customer-preservation-report-private.json`: referencia privada por cliente.
- `candidate-customer-projection.json`: proyección local, 38 empresas / 836 comprobaciones.

```text
git status --short
git log -3 --oneline
python C:/Users/pc/.codex/backups/fullpos-prepublish-readonly-20261120/audit_readonly.py
python C:/Users/pc/.codex/backups/fullpos-prepublish-readonly-20261120/assess_local.py
python C:/Users/pc/.codex/backups/fullpos-prepublish-readonly-20261120/supplement_readonly.py
node C:/Users/pc/.codex/backups/fullpos-prepublish-readonly-20261120/project_candidate.cjs
```

Los helpers SSH usan la clave existente sin leer ni mostrar su contenido, filtran
la salida y no invocan despliegue ni comandos de mutación. Las consultas de negocio
se ejecutaron en transacciones READ ONLY. No se utilizó Figma, Context7, navegador,
herramientas de mensajería, subagentes ni servicios de emisión externos.
