# PR 53: revisión de variantes ampliadas y privacidad de logs

## Publicación autorizada y alcance

El propietario autorizó publicar la rama y crear el PR hacia production-main.
Se publicó `agent/consolidacion-total-20261121`, inicialmente en `bfe2d2f9`, y se
abrió https://github.com/JUNIORPRUEVA/DaleVenta_POS/pull/53 como **borrador**.
No se autoriza por ello merge, migraciones ni despliegue productivo.

El inventario global examinó 121 worktrees y 265 referencias de ramas; no son
121 fuentes de una misma entrega. Incluye experimentos y versiones de meses
anteriores. La base del PR conserva los 19 commits consolidados y sus padres.
El inventario ampliado identificó 34 variantes de código/configuración en
31 rutas distintas. Una diferencia de blob no demuestra una funcionalidad ausente.

Las 308 entradas señaladas en el barrido ampliado tienen ahora copia privada
verificada por SHA-256, sin modificar sus originales. Se preservan también las
copias y ledger anteriores de los dos chats. No se incorpora la carpeta privada
de respaldos al repositorio ni a imágenes de Docker.

## Resoluciones verificadas en código

| Origen/área | Comparación y decisión |
|---|---|
| detalleVisuales: drawer y Facturación | Las 40 y 89 líneas añadidas significativas de sus parches están presentes en el candidato al normalizar espacios/comillas. Se conserva además el wrapper móvil posterior. No reaplicar el archivo antiguo. |
| detalleVisuales: historial TPV | 351 de las 355 líneas añadidas significativas están presentes. Las cuatro restantes son altura, iconos Material y un Expanded sustituidos por los controles móviles y el buscador actuales. La versión vigente incorpora además información fiscal y protección de devoluciones. |
| planes-de-pago-impl: Facturación | 339 de 341 líneas añadidas significativas presentes. Las dos frases de suspensión fueron sustituidas por texto que no atribuye falta de pago sin evidencia. Se conserva Plan actual y el acceso a opciones de pago; la pantalla de planes mantiene las explicaciones específicas. |
| onboarding-resume: ruta y habilitación e-CF | Están ecfDgiiCertificateRestart, persistedValidation, reinicio explícito, invalidación por identidad y el gate `_certificateReady` basado en evidencia persistida. No sustituir la pantalla posterior por el prototipo anterior. |
| selfservice: fecha E31 | `_confirmEcfModeForSale` utiliza e31SequenceDueDate y mantiene el fallback de compatibilidad. Está conservado en la pantalla actual. |
| finalesdaleventas: secuencias y activación | Se conservan numberingEnvironment/lockNumberingEnvironment y enableProduction con validaciones por empresa. La versión actual añade defensas posteriores; no restaurar la anterior. |
| finalesdaleventas: devolución e identidad | ecfRefundRequestId es equivalente salvo formato/línea final; la prueba PostgreSQL de clasificación histórica existe y contiene casos adicionales respecto del archivo anterior. |
| finalesdaleventas: cuenta y Facturación | Se mantiene la entrega posterior de configuración fiscal y controles de venta normal/electrónica. Los archivos antiguos no reemplazan la combinación ya validada. |
| finalesdaleventas-appyra: servicio/DTO/cliente y Flutter | Se conserva el puente AppyraIaClient, continuidad/idempotencia, conversación, clientMessageId, controlador y datasource. La versión vigente añade contexto firmado, recursos, aislamiento y soporte interno. Las pruebas del cliente contienen casos posteriores. |
| recover-fiscal-ai: prueba de cuenta | El contrato existe en ai-account-http.e2e-spec.ts: firma, expiración, sentido del token y selección de empresa desde el contexto firmado. El nombre de archivo antiguo no es requisito de runtime. |
| license-security: mutaciones y prueba | La versión posterior eliminó activateMyLicense/blockMyLicense/updateMyLimits del autoservicio. La variante antigua solo las bloqueaba con una excepción. No reintroducirlas ni sustituir el servicio de planes actual por el anterior. |
| fullpos-design: pubspec | El lock actual ya resuelve dio 5.9.1 e image 4.5.4. No se cambian restricciones ni se actualizan dependencias para igualar un parche antiguo. |
| fullpos-design: tres previews | Son entradas de demostración no usadas por el router productivo. Se preservan en origen/respaldo; no se convierten en pantallas nuevas del release. |

Las comparaciones literales son evidencia auxiliar, no pruebas de equivalencia
semántica por sí solas. Se contrastaron con las rutas/funciones actuales y con
las validaciones de la entrega consolidada. No se presenta esta revisión como
una nueva aprobación visual humana de todos los formularios históricos.

## Guardian: qué se conserva y qué se recupera

El prototipo de guardian-uat-consolidada incluía seis variantes. Tres relativas
a diagnóstico, circuito y su prueba intentaban añadir cuotas globales y una
barrera de disponibilidad. **No se importan directamente:** el commit posterior
`5d8a5f98` cambió deliberadamente a saldo real del proveedor y eliminó cuotas de
tokens. La implementación vigente reserva diagnósticos con advisory lock y
controla concurrencia en el adaptador. Reaplicar el parche antiguo sustituiría
esa política y perdería salvaguardas posteriores.

El prototipo de circuito continúa respaldado y sin borrar. Adoptarlo como una
función independiente requeriría diseño compatible y pruebas de concurrencia;
no se declara implementado por este PR ni se confunde con la IA del chat Laura.

Las otras tres variantes sí identificaron una mejora recuperable: saneamiento
de URLs antes de registrar peticiones. Se añadieron request-log.ts y su prueba,
y se integró el helper en main.ts. Además se aplicó al filtro global de errores:
una URL sensible puede aparecer tanto en el campo URL como en el mensaje/stack.

## Corrección mínima de privacidad

Se enmascaran valores de parámetros de autenticación, incluidos nombres
codificados, capitalización y parámetros repetidos. Se conserva ruta, orden y
parámetros no sensibles. Se incluyen handoff/ticket y tokens de recuperación.
No se modifica req.originalUrl, la firma de webhooks, el routing, los permisos,
la configuración fiscal, las licencias ni la base de datos.

La primera prueba HTTP local demostró que un 404 repetía la contraseña ficticia
en message/stack aunque URL ya estuviera saneada. Se corrigió esa repetición en
los metadatos de log y captura Guardian. La prueba repetida aprobó: los estados
200/404 se conservan y los dos marcadores ficticios no llegan a logs.

## Validación del cambio de privacidad

```text
npm test -- --runTestsByPath src/common/request-log.spec.ts src/common/filters/global-exception.filter.spec.ts
35 PASS, dos suites

npm run api:build
PASS

npm --workspace apps/api test
3176 PASS, 599 omisiones, 274 suites aprobadas

HTTP real + PostgreSQL 17.11 local
PASS: respuestas 200/404 y saneamiento de logs

git diff --check
PASS
```

La primera pasada amplia usó por error un JWT_SECRET sintético global en el
ejecutor privado. Falló el caso que comprueba ausencia de clave: ConfigService
leía ese entorno. Se retiró únicamente la inyección del ejecutor para reproducir
el entorno de CI. No se tocó la prueba ni el servicio de evidencia de caja.
La batería repetida terminó en exit 0. Los logs iniciales no son un PASS.

Evidencias: pr53-request-log-tests-final.log, pr53-api-build-final.log,
pr53-api-all-tests.log, pr53-request-log-http-result.json y el respaldo ampliado,
todos en la carpeta privada de auditoría. Las imágenes QA del cierre anterior
corresponden al código previo a este helper; no se publican como artefactos del
HEAD nuevo. Las imágenes productivas deben construirse desde el merge verificado.

## Puertas restantes

Mantener el PR en borrador hasta revisar este alcance y los controles del HEAD
actual. Los verdes de bfe2d2f9 no certifican el helper añadido después.
Las siete migraciones productivas, respaldo restaurado, imágenes del commit de
merge y configuración coordinada de soporte/IA siguen sujetos al procedimiento
de PREPARACION_FULLPOS_RELEASE_20261121.md. No hay GO de producción ni se cambió
el estado de los servicios desplegados.
