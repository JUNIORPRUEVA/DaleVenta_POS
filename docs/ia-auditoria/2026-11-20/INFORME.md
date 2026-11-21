# Auditoría de IA del 20 de noviembre de 2026

**Estado más reciente:** [cierre local de diseño y reconexión](DISENO_Y_RECONEXION.md).
Las secciones siguientes conservan la auditoría inicial y sus fallos históricos.

## Dictamen

**Actualización:** [verificación posterior con Astra](OPENAI.md). Corrige el
contexto truncado y documenta 10/10 escenarios con el proveedor externo real.
Los resultados de Qwen que siguen se conservan como evidencia histórica.

**NO-GO para producción.** Hay correcciones y verificaciones locales reales,
pero el modelo local todavía produce instrucciones incorrectas en dos preguntas
abiertas de cotizaciones. Un HTTP correcto no equivale a una respuesta correcta.
No se hizo push, merge, despliegue, acceso ni modificación de producción.

## Aislamiento y alcance

- FullPOS: `C:/src/fullpos-ultimos-ajustes-ia`,
  `agent/ultimos-ajustes-de-la-ia`, base `33625e3c`.
- APPYRA: `C:/src/appyra-ultimos-ajustes-ia`,
  `agent/ultimos-ajustes-ia-fullpos`, base `7fc0ed6`.
- El propietario confirmó que sólo este chat usa el worktree APPYRA después de
  detener las ediciones ante una modificación no atribuida. No se descartó trabajo.
- No se editó el worktree `fullpos-detalles-finales-importante` ni se integraron sus
  cambios. No se modificaron fiscal, Prisma, licencias ni sus datos existentes.
- Laboratorio exclusivo: dos empresas ficticias, PostgreSQL local en 5458,
  FullPOS API en 4048, APPYRA en 4448 y navegador UAT en 4004. Credenciales y
  fixtures privados quedan fuera de Git. Todas las bases usadas son ficticias.

## Bloqueos investigados y correcciones

1. **Arranque web:** se había compilado el laboratorio para 4049; la guardia UAT
   permite exclusivamente 4004. Se recompiló para el puerto autorizado y se
   corrigió el proxy local. No se amplió ni desactivó la guardia de producción.
2. **Entrada móvil:** la etiqueta accesible del botón ocupaba el viewport completo
   (390 × 844), en vez de 64 × 64. Se aisló el nodo Semantics y su acción. La hoja
   ahora usa el Overlay del navegador raíz, porque el acceso global vive por
   encima del Navigator. La regresión de tamaño/acción accesible pasa.
3. **Averías del historial:** «Quiero reportar una avería en el historial de
   cotizaciones» se interpretaba como consulta de casos anteriores. La detección
   distingue el historial operativo del historial de incidencias.
4. **Reintentos:** el resultado persistido devolvía `safeDraft` del validador en
   lugar del texto final con la referencia. Se conserva exactamente la respuesta
   final entregada y su atribución como reglas/memoria/resultado de incidencia.
5. **Conocimiento:** se evita reconocer «plan» dentro de «interplanetaria»;
   se conserva «facturando» como término válido. Un recorrido de varios módulos
   sólo se admite si una guía con pasos declara todos en su título. Los
   seguimientos breves recuperan el procedimiento previo del historial de servidor
   validado; no usan historial aportado por otro cliente para autorizar datos.
6. **Negativas vacías:** una negativa genérica del modelo se sustituye por una
   explicación y un siguiente paso seguro. Se amplió la detección de afirmaciones
   falsas de registro para «tu caso quedó registrado».

## Pruebas reales y simuladas

| Verificación | Resultado | Qué demuestra / límite |
| --- | --- | --- |
| FullPOS `npm --workspace apps/api test -- --json --outputFile=…` | 3065 PASS, 597 omitidas | Comando habitual; no equivale a ejecutar las suites omitidas |
| APPYRA `npm test -- --runInBand` | 928 PASS, 82 suites | Unitarias con motores/datos simulados según cada suite |
| APPYRA `npm run typecheck`, `npm run lint`, `npm run build` | PASS | Código y compilación locales |
| FullPOS `npm run build` en `apps/api` | PASS | Recompilación y arranque del API local exclusivo; sin migraciones |
| APPYRA `npm run eval:bank` | 171/171 PASS | Recuperación/fundamentación determinista; no examen generativo |
| Flutter AI y guardia UAT | 48 PASS | Incluye botón accesible y reporte con confirmación |
| Flutter AI/auth/Planes/e-CF | 614 PASS | Regresión tras la corrección móvil; sin editar fiscal ni licencias |
| Flutter AI/auth/Planes/e-CF | 614 PASS | Regresión ampliada, 2 min 27 s; sin cambios de negocio en esas áreas |
| Flutter análisis | PASS | Análisis estático; sin incidencias |
| Web UAT con API 4004 | PASS, 123.8 s tras corrección móvil | Build JS local; no publicación |
| Navegador escritorio 1280 × 900 | PASS para consulta y avería | App real, entrada de teclado, API real, referencia visible y validación de descripción vacía |
| Navegador 390 × 844 tras corrección | PASS funcional, observaciones visuales | Abre asistente, consulta real; nodo accesible 64×64 |
| Corte de conexión desde navegador estrecho | PASS para error y no repetición automática | Fallo simulado por aborto de Playwright; un intento de POST; no desconexión física |
| HTTP FullPOS → APPYRA → PostgreSQL/Ollama | 10/10 recorridos técnicos | Recuperación, seguimiento, desconocidos, reportes, reintento y aislamiento |
| Calidad del contenido de esos diez turnos | **8/10, FAIL** | Dos respuestas generativas contienen acciones no respaldadas |
| PostgreSQL de incidencias | PASS | Referencia de la empresa A persistida, excluida en empresa B |
| Caducidad con PostgreSQL real | PASS | Vence una sesión ficticia exacta; API pide reinicio y crea otra conversación |

La consulta de recuperación del navegador usa texto curado publicado y está
identificada como `appyra-ia-rules`; no se presenta como un acierto generativo.
Los dos turnos abiertos de cotizaciones sí usaron `qwen2.5-coder:3b` local.
Los desconocidos y las confirmaciones deterministas conservan su fuente.

El trabajador local de notificación procesó registros en **modo simulado**:
`notification_simulated=true`. Un `notified_at` o estado de esa cola no acredita
un mensaje real. No se validó ni se autorizó una entrega externa.

### Evidencias

- [Recuperación en escritorio](evidencias/escritorio-recuperacion.png).
- [Diálogo de avería](evidencias/escritorio-dialogo-averia.png).
- [Referencia confirmada en el chat](evidencias/escritorio-referencia.png).
- [Fallo de apertura móvil anterior a la corrección](evidencias/movil-apertura-fallida.png).
- [Consulta real a 390 px tras la corrección](evidencias/movil-consulta-real.png).
- [Pérdida de red simulada](evidencias/movil-perdida-red-simulada.png).
- [Resultado funcional estrecho](movil-resultados.json).
- [Diez conversaciones y comprobaciones de calidad](conversaciones-reales.json).
- [Persistencia y aislamiento del caso](casos-postgresql.json).
- [Caducidad y nueva conversación](caducidad-postgresql.json).

Todas las capturas contienen exclusivamente el laboratorio ficticio. Se
inspeccionaron visualmente las capturas de escritorio y el fallo móvil. La lectura
de texto semántico de Flutter tras cerrar el diálogo no reflejó siempre el nuevo
mensaje, aunque la captura sí mostraba la referencia; se distinguen ambas pruebas.

## Las 597 omisiones

Se inventarió **cada prueba**, no sólo el total: [tabla por archivo](pruebas-omitidas.md)
y [detalle de las 597](pruebas-omitidas.json). Hay 59 archivos con omisiones y 57
suites totalmente omitidas; dos archivos contienen también pruebas ejecutadas.

| Grupo | Pruebas omitidas | Clasificación |
| --- | ---: | --- |
| Fiscal / ventas e-CF | 454 | Opt-in PostgreSQL intencional; requiere su suite aislada para release de esa área |
| Licencias, pagos y actividad | 42 | Fixtures PostgreSQL dedicadas; no ejecutadas ni modificadas en esta tarea |
| Guardian | 89 | Requieren PostgreSQL y, en seguridad, rol lector; sistema distinto del chat APPYRA |
| Outbox de notificaciones | 4 | PostgreSQL y transporte simulado; no habilitar envíos externos |
| Importación legacy | 8 | Requiere SQLite origen y PostgreSQL desechable para importación/rollback |

**Ninguna prueba de `ai-assistant` quedó omitida.** Todas las omisiones observadas
son condicionales de activación, no `skip` permanente añadido en esta tarea.
Que sean intencionales en el comando habitual no las convierte en aprobadas ni
en innecesarias para su área. Además, `npm test` excluye archivos e2e; esos casos
no están incluidos en las 597. Se respetó la prohibición de modificar esas áreas
y no se activaron sus fixtures sobre las bases del laboratorio de IA.

## Fallos conservados y pendientes

1. **Calidad generativa — bloqueante.** En cotizaciones el modelo inventó
   «Consumidor Físico», botones «Convertir en Venta» y «Finalizar», y omitió
   «Cotizar» / «Pasar a ticket». La guía publicada sí contiene los pasos correctos.
   El seguimiento dejó de exigir correo, pero continuó inventando acciones y
   repitiendo encabezados. Las aserciones técnicas anteriores eran insuficientes;
   el nuevo comprobador de contenido termina en FAIL y conserva las respuestas.
2. **Rendimiento — pendiente.** Se observaron 48.09 y 95.03 s en los dos turnos
   generativos locales durante la batería. No se extrapola a otro proveedor.
3. **Recuperación tras pérdida de red — pendiente de cierre.** Una interrupción
   simulada desde Playwright mostró el aviso de conexión. El ensayo de reintento
   posterior agotó `page.waitForResponse` a 30 s; no se declara PASS ni se atribuye
   todavía a una causa de producto. Las pruebas HTTP idempotentes sí pasan.
4. No se evaluó proveedor productivo, adjuntos multimedia, dispositivos físicos
   Android/iOS ni notificaciones reales. La vista estrecha es Chromium de
   escritorio con viewport 390 × 844, no un teléfono físico.
5. **Conocimiento desalineado — pendiente.** `support-topics.ts` de APPYRA declara
   en un comentario que Contabilidad/Nómina se retiraron y no les asigna tema;
   el `app_router.dart` de esta rama FullPOS sí registra esas rutas y pantallas
   (Contabilidad y Nómina). No se eliminó ni modificó ninguno de esos módulos.
   Debe reconciliarse el catálogo/conocimiento con la versión real antes de
   prometer cobertura de todo FullPOS. El banco 171/171 no demuestra esa cobertura.
6. **Pulido visual pendiente.** La captura estrecha posterior a la corrección
   confirma la apertura y la respuesta, pero el botón flotante permanece encima
   del contenido del panel. El error de conexión aparece en burbuja y aviso, con
   `ApiException` / `code: UNKNOWN`. No se declara aprobado el pulido visual de
   estos estados ni se ocultan las capturas que muestran esas limitaciones.

No publicar estas ramas hasta corregir/verificar los bloqueantes. No se ofrece un
GO de producción basado únicamente en las suites unitarias o el banco de reglas.

### Verificaciones finales de la continuación

La corrección de apertura a 390 px quedó comprobada en Chromium real: el nodo
accesible pasó de `{x:0,y:0,width:390,height:844}` a
`{x:312,y:390,width:64,height:64}`. La hoja abrió usando el mismo botón accesible;
se escribió la consulta con eventos de teclado y llegó la respuesta desde ambas
APIs. La pérdida de red se inyectó abortando un POST en el navegador: mostró el
aviso y contabilizó exactamente un intento. **Eso no prueba un corte físico**
ni el reintento posterior, que permanece pendiente según el fallo descrito arriba.

Se inspeccionaron las dos capturas nuevas de 390 px. El texto se lee y el
compositor es accesible, pero el botón flotante continúa encima de parte del panel
y el error se duplica con `ApiException` / `UNKNOWN`. No se les asigna un PASS visual
total. El caso de la referencia que parecía ausente se comprobó en los píxeles;
no se cambió el controlador para ocultar un problema de automatización.

Pruebas intermedias fallidas y corregidas: las aserciones del test del reporte
incluían indebidamente la consulta legítima de antecedentes; se restringieron al
flujo de seguimiento. La regresión forzó un borrador inválido para reproducir el
reintento con `safeDraft`; también se cubrió «quedó registrado». La comparación
de vocabulario por palabra completa omitió «facturando» (168/171); se añadió ese
término explícito y el banco volvió a 171/171, conservando el rechazo de
«interplanetaria». En Flutter se corrigieron la importación de SemanticsAction y
la liberación del handle de semántica del nuevo test. Ningún fallo se ocultó
desactivando pruebas.

La última compilación FullPOS encontró primero `EPERM` al renombrar la DLL del
cliente Prisma de Windows, porque el API local la tenía cargada. Se detuvo sólo
el proceso registrado del laboratorio, se ejecutó `npm run build` y se levantó
ese mismo API local, con ambos health checks en PASS. No se cambió esquema,
migración, configuración ni servicio productivo para resolver el bloqueo.

## Reproducción e inventario

Desde el worktree FullPOS:

```powershell
node apps/api/scripts/audit-ai-skipped-tests.cjs <resultado-jest.json> docs/ia-auditoria/2026-11-20
node apps/api/scripts/audit-ai-live-results.cjs <conversaciones-locales.json> docs/ia-auditoria/2026-11-20
```

El segundo comando devuelve código 1 cuando detecta las instrucciones incorrectas;
es el resultado esperado de esta auditoría fallida, no una puerta debilitada.
Los helpers de navegador/fixtures permanecen en la carpeta privada del laboratorio:
contienen rutas/configuración local y no se añaden a Git. Los comandos ejecutados
y resultados anteriores son evidencia de esta sesión, no una garantía de que un
tercero pueda ejecutar fixtures privados sin prepararlos primero.

El inventario base está en [la auditoría inicial](../../IA_AUDITORIA_Y_PLAN_2026-11-20.md).
Esta continuación añade en APPYRA `company-memory.intent(.spec).ts`,
`runtime-knowledge-query(.spec).ts`, regresiones de `support-topics.spec.ts` y
`draft-validator.ts`; en FullPOS añade los dos scripts de auditoría, los informes,
el aislamiento semántico del botón y el contexto de apertura móvil. El resto de
los cambios locales anteriores se conserva sin commit.

Archivos de código añadidos/modificados específicamente durante esta continuación
(además de los cambios previos del inventario base):

FullPOS:

- `apps/api/scripts/audit-ai-skipped-tests.cjs`
- `apps/api/scripts/audit-ai-live-results.cjs`
- `apps/fulltech_app/lib/core/ai_assistant/presentation/widgets/ai_assistant_dock_button.dart`
- `apps/fulltech_app/lib/core/ai_assistant/presentation/widgets/global_ai_assistant_entry_point.dart`
- `apps/fulltech_app/test/core/ai_assistant/ai_assistant_sheet_composer_test.dart`
- `docs/EXECUTION_STATE.md`
- `docs/IA_AUDITORIA_Y_PLAN_2026-11-20.md`
- `docs/ia-auditoria/2026-11-20/INFORME.md`
- `docs/ia-auditoria/2026-11-20/pruebas-omitidas.md`
- `docs/ia-auditoria/2026-11-20/pruebas-omitidas.json`
- `docs/ia-auditoria/2026-11-20/conversaciones-reales.json`
- `docs/ia-auditoria/2026-11-20/casos-postgresql.json`
- `docs/ia-auditoria/2026-11-20/caducidad-postgresql.json`
- `docs/ia-auditoria/2026-11-20/movil-resultados.json`
- Las seis capturas enlazadas en Evidencias.

APPYRA:

- `apps/api/src/modules/agent-runtime/agent-runtime.service.ts`
- `apps/api/src/modules/agent-runtime/agent-runtime.service.spec.ts`
- `apps/api/src/modules/agent-runtime/runtime-knowledge-query.ts`
- `apps/api/src/modules/agent-runtime/runtime-knowledge-query.spec.ts`
- `apps/api/src/modules/company-memory/company-memory.intent.ts`
- `apps/api/src/modules/company-memory/company-memory.intent.spec.ts`
- `apps/api/src/modules/simulator/draft-validator.ts`
- `apps/api/src/modules/simulator/session/session-answer.ts`
- `apps/api/src/modules/simulator/session/session-answer.spec.ts`
- `apps/api/src/modules/simulator/support-topics.ts`
- `apps/api/src/modules/simulator/support-topics.spec.ts`
