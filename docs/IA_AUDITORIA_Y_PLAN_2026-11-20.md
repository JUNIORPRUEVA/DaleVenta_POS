# Ajustes del asistente de FullPOS: auditoría inicial y plan

**Continuación y evidencias del 20/11/2026:** consultar
[informe de cierre de auditoría](ia-auditoria/2026-11-20/INFORME.md).
Incluye inventario individual de 597 omisiones, pruebas reales de navegador/HTTP/
PostgreSQL y fallos de calidad del modelo. El dictamen continúa siendo NO-GO.

## Estado y alcance

Rama local exclusiva `agent/ultimos-ajustes-de-la-ia`, worktree
`C:/src/fullpos-ultimos-ajustes-ia`, base de production-main
`33625e3cc6666867d80e5c1fae8e001dca64526c` (PR52). Sin upstream configurado,
para evitar un push accidental a production-main. Los worktrees previos,
incluido detalles-finales-importante, no se modifican.

Objetivo del propietario: respuestas prácticas fundamentadas en todo FullPOS,
orientación contextual, reporte real y seguimiento de averías, sin inventar
soluciones ni confirmar acciones que no ocurrieron. No se promete resolver
cualquier problema automáticamente: las operaciones no soportadas, riesgosas o
que requieran intervención humana se derivarán con una explicación concreta.

Este documento conserva la auditoría y el plan originales. Posteriormente el
propietario autorizó la implementación y las pruebas locales en worktrees
aislados; los resultados se registran al final. No autoriza publicación ni cambios
productivos.

## Flujo real observado

Flutter AiAssistantController → AiAssistantService/data source → POST /ai/chat
autenticado → AiAssistantService NestJS → AppyraIaClient →
APPYRA /agent-runtime/chat. Si el puente no está activo se usa el camino local;
si falla se usa su respaldo por reglas. Son caminos de conocimiento distintos.

El motor externo está en otro repositorio:
`C:/Users/pc/DEV/PROYECTOS/INTERNO/APPYRA_AI`. Se consultó sólo en lectura.
Su runtime consulta conocimiento publicado, catálogo de navegación y cuenta
autorizada; también tiene un servicio persistente de incidencias. Que el código
exista localmente no demuestra su despliegue ni su configuración actual.

## Hallazgos de código (HECHO)

1. **Conocimiento separado.** `ai-assistant.service.ts:601` delega antes de
   `buildKnowledge`. `tryAppyraIa` envía mensaje, conversación, archivo, contexto
   firmado y route/module/screenName; no envía el conjunto de guías del camino
   local. Por tanto ampliar únicamente el prompt local no mejora el motor activo.
   No se debe remediar enviando indiscriminadamente manuales o datos privados.
2. **Falsos bloqueos de soporte.** `isForbiddenSecretRequest` contiene
   `text.includes('contraseña')` y `password`: rechaza también preguntas legítimas
   como «cómo recupero mi contraseña». Hay que distinguir orientación de
   extracción/revelación sin debilitar la protección de secretos.
3. **Contexto incompleto.** `ai_chat_context_resolver.dart` no tiene ramas para
   e-CF, Planes, compras, caja o almacenes. Una ruta no reconocida acaba con módulo
   general y puede carecer de nombre de pantalla. Se requiere una matriz basada
   en rutas reales y pruebas para las pantallas actuales.
4. **Reporte sin resultado estructurado en FullPOS.** El acceso rápido de
   `ai_assistant_sheet.dart:349` sólo envía «Quiero reportar una avería». El motor
   externo devuelve `incident` (referencia, estado, duplicado), pero
   `AppyraIaClient.mapResponse` y su contrato no conservan ese objeto. El texto
   puede incluir una referencia, pero no existe una ficha fiable en Flutter.
5. **Revisión humana perdida en presentación.** El servicio Dart interpreta
   `requiresHumanReview`; el controlador no lo copia al mensaje del asistente.
   La interfaz no puede distinguir ese estado a partir del modelo de mensaje.
6. **Reporte genérico/anterior insuficiente en el motor.**
   `openIncidentForTurn` usa sólo el mensaje actual como resumen y detalle.
   Pulsar el acceso rápido puede registrar la frase genérica; «repórtalo» no
   incorpora por sí mismo la descripción del turno anterior. Hay que preparar
   un resumen con los datos mínimos, confirmarlo y registrar ese caso concreto.
7. **Cambio de sesión: riesgo que requiere reproducción.** El provider del chat
   mantiene mensajes/conversationId; `setContext` reinicia conversación al cambiar
   módulo, pero conserva mensajes y no recibe identidad de empresa/usuario.
   En APPYRA, `resolveSession` consulta id/tenantId/agentId; la credencial de
   integración puede compartir tenant entre empresas FullPOS. No se ha probado
   una fuga: se exige una prueba negativa entre dos empresas/usuarios antes de
   ampliar memoria o accesos. La deduplicación temprana debe cubrirse también.

## Antecedentes documentados, no estado productivo verificado

APPYRA `docs/33-verificacion-produccion-y-arreglo-crlf.md` documenta una medición
con guías genéricas ocupando plazas de procedimientos, un arreglo de normalización
revertido y fallos del banco. Es evidencia histórica, no un resultado ejecutado
en esta tarea. El coverage.json consultado fue generado el 17/11 contra otra
ruta/base; no acredita cobertura del PR52 ni contenido publicado actual.

Otros contratos antiguos del motor describen notificación de soporte como
propuesta; el código actual sí persiste incidencias y separa notificaciones.
Resolver la discrepancia mediante código/pruebas y estado real: no dar por
implementado un envío a WhatsApp por una frase del modelo. No se enviaron mensajes.

## Plan mínimo propuesto

1. **Aislamiento y continuidad primero.** Identidad de usuario/empresa en el ciclo
   de vida del chat, descarte de respuestas tardías, separación de conversación,
   reintentos idempotentes y validación de propiedad de sesión en el motor.
2. **Averías comprobables.** Recoger problema concreto y módulo, mostrar resumen
   para confirmar, conservar referencia/estado real, distinguir registrado de
   notificado y permitir seguimiento autorizado. Sin dobles casos por reintento.
   No crear otro almacén de tickets paralelo al servicio que ya existe.
3. **Contexto completo.** Resolver rutas actuales con nombres claros y conservar
   contexto útil entre turnos compatibles. Compatibilidad con respuestas antiguas
   y ausencia de nuevos campos. Capturas/archivos no son instrucciones confiables.
4. **Conocimiento verificable.** Inventario módulo → pantalla → procedimiento →
   fuente real → prueba. Cubrir ventas normales/ITBIS, e-CF/E31/E32/E34, caja,
   inventario, compras, clientes, créditos, cotizaciones, usuarios/permisos,
   planes/transferencias, impresiones/PDF, conectividad y actualizaciones según
   código/documentación. Separar guías de uso de datos de una empresa y del estilo
   del agente. Actualizar la fuente que realmente consulta APPYRA, no sólo el
   prompt de respaldo. No importar ni publicar contenido en producción.
5. **Respuestas y escalamiento.** Dar pasos específicos cuando exista guía;
   preguntar sólo lo que falta; declarar fallos del motor y revisión humana;
   permitir ayuda de recuperación de cuenta sin mostrar secretos. No ampliar los
   roles habilitados ni capacidades financieras/fiscales por esta optimización.
6. **Pruebas conjuntas.** Flutter unit/widget de contexto, sesiones, estados y
   casos; backend build y pruebas de puente/contrato/seguridad; APPYRA banco de
   preguntas y tests de recuperación/incidencias. Integración HTTP y PostgreSQL
   locales aislados con dos empresas ficticias. Pruebas visuales de chat compacto
   y escritorio. Modelos/proveedores simulados se etiquetan como simulados; una
   evaluación con modelo externo se separa y no se presupone autorización de gasto.

Si hace falta modificar APPYRA, usar su propia rama/worktree y leer primero sus
AGENTS.md. Esta rama FullPOS no puede contener cambios Git de otro repositorio.
No editar su main ni los worktrees donde otros agentes puedan estar trabajando.

## Criterios de aceptación

- Preguntas legítimas de uso y recuperación no se bloquean por palabras aisladas;
  extracción de secretos, acceso ajeno e instrucciones maliciosas siguen denegados.
- Cada procedimiento propuesto tiene fuente; lo desconocido se declara y deriva.
- Una avería real tiene descripción útil y referencia persistente verificable;
  un fallo no produce confirmación falsa ni promesa de notificación.
- Dos empresas/usuarios no comparten mensajes, archivos, casos ni deduplicación.
- Pérdida de conexión, sesión expirada, respuesta tardía y reintento no mezclan
  identidad ni duplican casos; clientes anteriores siguen interpretando respuestas.
- Se conserva la facturación, numeración, licencias, caja y documentos existentes.
- Sin producción, despliegue, migración, envío externo, cambio de variables,
  commit/push/PR o merge en esta fase. Las pruebas locales se distinguen de la
  evaluación de modelos y de cualquier comprobación externa productiva.

## Estado

**NO-GO para publicar/desplegar los ajustes de IA** mientras falte la validación
visual/funcional de la app y la revisión ampliada de calidad/cobertura. Este
estado no cambia la entrega PR52, que es independiente.

## Implementación local autorizada y evidencia

- FullPOS: distinción entre ayuda de recuperación y extracción de secretos;
  contexto de rutas fiscales/Planes/caja/compras/almacenes; diálogo de avería con
  descripción y confirmación; referencia real y revisión humana en el mensaje;
  descarte de respuestas tardías y reinicio por identidad; error recuperable de
  conversación; timeout efectivo del puente corregido (ausencia antes daba 1 s).
- Datos: consultas de respaldo filtradas por empresa, órdenes por su cliente,
  propietario resuelto dentro de la empresa, SQL de memoria con UUID y company_id;
  clave de tema incluye empresa sin migrar ni reescribir historia.
- APPYRA: rama exclusiva `agent/ultimos-ajustes-ia-fullpos` en
  `C:/src/appyra-ultimos-ajustes-ia`; propiedad de conversación comprobada antes
  del reintento, contexto firmado de usuario/empresa, reporte genérico pide
  detalles, reporte con descripción devuelve el resultado persistido. Sin nueva
  tabla de incidencias ni envío externo.
- Conocimiento: guías de Plan actual/transferencias y recuperación; corrección de
  la guía que decía que FullPOS no calcula devuelta. El banco antiguo esperaba ese
  dato incorrecto y se alineó con el código de cobro existente.
- Respuestas verificadas: secciones explícitas de consulta dentro de guías
  publicadas pueden responder sin modelo; se conserva su atribución como reglas.
  Un test comprueba que no se invoca el modelo ni se le atribuye esa respuesta.

Validaciones ejecutadas en esta fase:

| Comprobación | Resultado | Límite |
| --- | --- | --- |
| `npm --workspace apps/api test -- --runInBand` (FullPOS) | 3065 PASS; 597 omitidas; 264 suites PASS | No certifica los casos omitidos |
| `npm test -- --runInBand` (APPYRA `apps/api`) | 922 PASS, 81 suites | Motores simulados en tests unitarios |
| `npm run eval:bank` (APPYRA `apps/api`) | 171/171 PASS | Banco determinista; baseline 164/171 reproducido |
| `flutter analyze` | PASS, sin incidencias | Análisis estático |
| `flutter build web --release --dart-define=FULLPOS_UAT_PROFILE=true --dart-define=APP_ENV=uat --dart-define=API_BASE_URL=http://127.0.0.1:4049/api --dart-define=DISABLE_APP_UPDATES=true` | PASS, 114.1 s | Artefacto local UAT; no publicación |
| `flutter test` sobre AI/auth/Planes/e-CF | 613 PASS | Regresión seleccionada, no toda la suite Flutter |
| `npm run build` en cada API aislada | PASS | No despliega ni valida producción |
| `npm run lint`, `npm run typecheck` (APPYRA) | PASS | Sin actualización de dependencias |
| Integración HTTP/PostgreSQL exclusiva local | PASS | Dos empresas ficticias, sin credenciales productivas |
| Recuperación/devuelta por HTTP | PASS con aserciones de contenido y fuente | Respuestas curadas, no acierto generativo del modelo |

La integración local usa PostgreSQL exclusivo en 5458, FullPOS en 4048 y APPYRA
en 4448. Se verificaron memoria persistida, exclusión de clientes ajenos, referencia
de avería conservada al duplicar y rechazo de conversación de otra empresa. No se
emitieron facturas ni mensajes externos. Fixtures y evidencias privadas quedan
fuera de Git, sin documentar secretos.

### Riesgos pendientes y resultados negativos conservados

El modelo local real `qwen2.5-coder:3b` inventó inicialmente que había enviado un
correo de recuperación y pasos incorrectos de devuelta. Los validadores no
detectaron ambos errores: es una limitación real de calidad. Se corrigieron esas
consultas mediante extractos aprobados y se repitió la prueba HTTP con éxito;
esto no demuestra que otras preguntas abiertas sean correctas.

La app local todavía requiere completar la inspección visual/funcional de la
compilación final y la revisión del propietario. La automatización de navegador
ha tenido bloqueos de arranque/captura; no se declara un PASS visual. Tampoco se
ha verificado procesamiento de adjuntos en el laboratorio ni cobertura total de
FullPOS, ni rendimiento/calidad con el proveedor productivo. No publicar guías ni
cambiar modelos productivos como parte de este trabajo local.

La revisión de navegador aislado falló con `locator.innerText: Timeout 30000ms
exceeded` durante la lectura de la app; intentos previos tuvieron timeout de
captura y activación de accesibilidad fuera del viewport. La imagen inspeccionada
sólo mostraba «Iniciando…». Estos fallos no se cuentan como prueba visual del chat.
El build avisa de limitaciones del ensayo wasm en dependencias; el build web JS
sí termina. No se actualizaron dependencias para ocultar esos avisos.

## Inventario de archivos de esta implementación

FullPOS, relativo a su worktree exclusivo:

- `apps/api/src/ai-assistant/ai-assistant.service.ts`
- `apps/api/src/ai-assistant/appyra-ia.client.ts`
- `apps/api/src/ai-assistant/appyra-ia.client.spec.ts`
- `apps/api/src/ai-assistant/secret-request.policy.ts`
- `apps/api/src/ai-assistant/secret-request.policy.spec.ts`
- `apps/api/src/ai-assistant/ai-memory.tenant.spec.ts`
- `apps/fulltech_app/lib/core/ai_assistant/application/ai_assistant_controller.dart`
- `apps/fulltech_app/lib/core/ai_assistant/data/datasources/ai_assistant_datasource.dart`
- `apps/fulltech_app/lib/core/ai_assistant/domain/models/ai_assistant_message.dart`
- `apps/fulltech_app/lib/core/ai_assistant/domain/services/ai_assistant_service.dart`
- `apps/fulltech_app/lib/core/ai_assistant/presentation/ai_chat_context_resolver.dart`
- `apps/fulltech_app/lib/core/ai_assistant/presentation/widgets/ai_assistant_sheet.dart`
- `apps/fulltech_app/test/core/ai_assistant/ai_assistant_controller_test.dart`
- `apps/fulltech_app/test/core/ai_assistant/ai_assistant_sheet_composer_test.dart`
- `apps/fulltech_app/test/core/ai_assistant/ai_context_coverage_test.dart`
- `docs/EXECUTION_STATE.md`
- `docs/IA_AUDITORIA_Y_PLAN_2026-11-20.md`

APPYRA, relativo a su worktree exclusivo:

- `apps/api/content/fullpos-support/agent.json`
- `apps/api/content/fullpos-support/knowledge/10-ventas-registrar-venta.md`
- `apps/api/content/fullpos-support/knowledge/32-planes-y-transferencias.md`
- `apps/api/content/fullpos-support/knowledge/33-recuperar-acceso.md`
- `apps/api/src/modules/agent-runtime/agent-runtime.service.ts`
- `apps/api/src/modules/agent-runtime/agent-runtime.service.spec.ts`
- `apps/api/src/modules/conversations/prompt/prompt-builder.ts`
- `apps/api/src/modules/knowledge/retrieval/text-normalization.ts`
- `apps/api/src/modules/simulator/session/session-answer.ts`
- `apps/api/src/modules/simulator/session/session-answer.spec.ts`
- `apps/api/src/modules/simulator/session/approved-support-answer.ts`
- `apps/api/src/modules/simulator/session/approved-support-answer.spec.ts`
- `apps/api/src/modules/simulator/support-topics.ts`
- `apps/api/test/bank/fullpos-question-bank.json`

Archivos generados de plugins Windows restaurados a su estado previo. Configuración
local y credenciales de fixtures quedan ignoradas/fuera de Git. No hubo cambios
en esquema, migraciones, lógica fiscal, planes ni worktrees de otros agentes.
