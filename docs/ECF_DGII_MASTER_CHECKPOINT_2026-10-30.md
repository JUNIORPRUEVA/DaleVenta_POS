# Checkpoint del asistente único e-CF / DGII — 2026-10-30

Alcance: worktree `FULLPOS-ECF-ALANUBE`, rama `feature/ecf-alanube`.
Este checkpoint describe el código local; no acredita una postulación oficial,
certificación ni emisión productiva.

## Antes y después

| Antes | Ahora |
| --- | --- |
| Puesta en marcha, habilitación y postulación mostraban avances separados. | `/ecf` presenta Solicitud → Pruebas → Certificación en un solo panel. |
| Datos fiscales y expediente se abrían en pantallas distintas. | Los formularios existentes se insertan en la tarea activa y usan los servicios actuales. |
| Un expediente en revisión interna podía parecer un avance oficial. | `APPLICATION_PENDING` permanece en Solicitud y el texto declara que falta constancia oficial. |
| Fallar la lectura del borrador dejaba el formulario disponible. | La edición espera a recuperar la revisión vigente del servidor. |

La activación técnica aparece después de la certificación y conserva sus
compuertas backend. Las rutas antiguas de datos fiscales y habilitación redirigen
a `/ecf`; la bandeja de comprobantes y la configuración técnica siguen como
funciones secundarias.

## Fuente de cada dato

| Dato | Fuente comprobada en código | Persistencia del trámite |
| --- | --- | --- |
| Razón social | `Company.name` de la empresa autenticada | Borrador y snapshot inmutable al enviar a revisión interna |
| RNC, dirección, representante e identificación | `AppConfig` de la misma empresa | Sugeridos al expediente; diferencias exigen elección explícita |
| Correo del representante | Borrador del expediente | Se solicita si falta; no reemplaza el perfil fiscal |
| Teléfono | Configuración fiscal de empresa | Recomendado para el emisor; no es campo obligatorio del payload de solicitud actual |
| Documentos y evidencia | `ecf_evidences` acotado por empresa | El snapshot conserva referencias, clases y hashes |
| Certificado digital | Requisito y evidencia del flujo existente | No se piden claves privadas en la app |
| Software, proveedor, URL y autorización | Requisitos y registros DGII existentes | No se completan por inferencia a partir del perfil fiscal |

El servicio obtiene `companyId` mediante `requireTenant(user)` y consulta
`Company`, `AppConfig`, borrador, evidencia y snapshots con ese identificador.
`submit` crea un snapshot versionado y dos eventos de auditoría en una transacción;
no contiene llamada de presentación a DGII ni a Alanube. El guardado usa revisión
optimista y la repetición del mismo snapshot pendiente es idempotente.

## Estados y acción principal

| Situación | Acción visible | Efecto real |
| --- | --- | --- |
| Datos fiscales incompletos | Guardar datos fiscales | Actualiza el perfil de empresa mediante el formulario existente. |
| Datos de solicitud completos | Continuar | Abre la revisión de documentos en el mismo asistente. |
| Solo falta correo | Guardar correo | Guarda el borrador versionado; no presenta una solicitud oficial. |
| Expediente revisado | Enviar a revisión interna | Crea o reutiliza el snapshot interno con consentimiento. |
| Snapshot en revisión interna | Ver cómo presentar | Explica el trámite externo y permite registrar evidencia manual; no lo adelanta a Pruebas. Después ofrece Consultar estado. |
| Pruebas pendientes | Ver comprobaciones | Abre solo las acciones implementadas por el motor local. |
| Autorización oficial verificable | Revisar activación | Consulta las compuertas; no habilita emisión real por sí sola. |

## Etapas y límites

| Etapa | Resultado local | Pendiente para operación real |
| --- | --- | --- |
| 0. Inventario | Rutas, UI, repositorios, `submit`, guards y compuertas revisados. | Verificación externa de contratos vigentes. |
| 1. Datos | Perfil canónico sugerido, faltantes puntuales, resolución de diferencias, borrador reanudable. | Validación empresarial oficial de los datos. |
| 2. Asistente | Tres hitos, un progreso y una tarea activa en `/ecf`. | Validación visual en dispositivos reales. |
| 3. Semántica | Revisión interna diferenciada de presentación oficial. | Contrato de postulación, pruebas, webhooks y evidencia oficial con Alanube/DGII. |
| 4. Activación | Compuerta backend `realEmissionAuthorized=false`; e-CF no se enciende por la guía. | Certificación, autorización, numeración, firma e integración productiva por empresa. |
| 5. Pruebas | Pruebas focalizadas de Flutter y Jest; análisis, TypeScript y esquema comprobados. | Build API integral y pruebas visuales reales. |

## Validación de este checkpoint

| Comando | Resultado |
| --- | --- |
| `flutter analyze --no-pub` | Sin observaciones. |
| `flutter test --no-pub --reporter compact` | 1479 pruebas aprobadas; 1 omitida. |
| `npm --workspace apps/api test -- --runInBand` | 126 suites / 1300 pruebas aprobadas; 19 suites / 260 pruebas omitidas. |
| `npx tsc -p apps/api/tsconfig.build.json` | Aprobado. |
| `npx prisma validate` con URL local ficticia | Esquema válido; sin conexión a base. |
| `git diff --check` | Sin errores de espacios. |
| `npm run api:build` | Bloqueado por `EPERM` al reemplazar el binario local de Prisma. |

El test de widgets en Chrome quedó en la fase de carga y se interrumpió; no es
evidencia de validación web. Los anchos 320, 360, 390, 768, 1024 y 1366 px se
validaron con pruebas de widgets y datos sintéticos. `V:\apps\fulltech_app`
resuelve al mismo root Git autorizado, pero las ediciones se hicieron en la ruta
del worktree indicada arriba.

Los informes históricos de E32, de la base UAT aislada y de producción no se
revalidaron en esta tarea. No se ejecutó APPLY, migración, emisión, deploy ni
llamada al proveedor o a la DGII.

## Siguiente acción exacta

1. Resolver el bloqueo local `EPERM` que impide a `prisma generate` reemplazar
   `query_engine-windows.dll.node` y repetir `npm run api:build`.
2. Validar el asistente con un backend local de datos sintéticos y guard de red
   UAT en Windows, Web, Android e iOS, incluidas navegación por teclado y lectura
   accesible.
3. Obtener confirmación contractual vigente de Alanube y DGII sobre creación de
   empresa, certificado/firma, postulación, set de pruebas, estados y webhooks.
   Implementar y probar el adaptador oficial únicamente en una tarea autorizada
   para llamadas externas y con las compuertas fiscales completas.
