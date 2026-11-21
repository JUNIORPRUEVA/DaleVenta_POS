# Verificación con OpenAI — 20 de noviembre de 2026

**Continuación posterior:** [diseño y reconexión cerrados localmente](DISENO_Y_RECONEXION.md).
La nueva acción de reintento tiene evidencia real de escritorio, móvil y PostgreSQL.
El bloqueo del ejecutor que sigue se conserva como historial, no como estado vigente.

## Alcance y estado

Continuación del [informe inicial](INFORME.md). Se conserva la evidencia anterior
de Qwen: sus errores no se borran ni se cuentan como aprobados retrospectivamente.
Sólo se usaron los dos worktrees asignados y empresas ficticias del laboratorio.
No hubo push, merge, despliegue ni cambios en producción, fiscal, Prisma o licencias.

**NO-GO para producción:** la configuración comercial sólo se preparó en el
laboratorio. El cierre visual y de conectividad se registra al final de este informe.
Ningún modelo garantiza ausencia absoluta de errores.

## Credencial y selección del modelo

- Autenticación real en `/v1/models`: la cuenta permite `gpt-6.2-astra`.
- Se retiró una clave pegada por accidente en `.env.example`; se dejó únicamente
  el marcador vacío. La credencial permanece en `.env`, ignorado por Git.
  No se imprimió, publicó ni incluyó en evidencias. No se inspeccionó su editor.
- Se creó una cuenta de proveedor **del tenant ficticio**, usando la API de
  administración existente y cifrado existente, y se asignó `conversation` a
  Astra con autorización externa y tope diario de **US$3**.
- No se cambió el modelo predeterminado de otras empresas ni la configuración de
  EasyPanel. La asignación local no se transporta automáticamente con los commits.
- Documentación oficial: [GPT‑6.2 Astra](https://developers.openai.com/api/docs/models/gpt-6.2-astra.md).
  Precios usados para el control local: US$8 / millón de entrada y US$40 / millón
  de salida. El consumo se verifica en PostgreSQL, no se deduce del texto del chat.

### Compatibilidad del transporte

Se reutilizó Chat Completions. El adaptador actual envía `reasoning_effort=none`
cuando el modelo pide herramientas; Astra no admite ese valor. Por ello esta
evaluación desactiva **sólo el bucle opcional de herramientas elegido por el modelo**
(`AGENT_MAX_TOOL_CALLS_PER_TURN=0`). Las consultas autorizadas de servidor al mapa
de FullPOS, cuenta y ficha empresarial permanecen operativas y delimitadas por
empresa. No se retiraron controles de permisos, propiedad de sesión ni presupuestos.

No se validó Astra con el bucle opcional activado. No habilitarlo en un despliegue
sin adaptar y probar el transporte. El reporte de averías lo registra la plataforma,
no el modelo. Las notificaciones del laboratorio siguen siendo simuladas.

## Causa y correcciones

1. **Contexto truncado, demostrado con regresión:** con la identidad e instrucciones
   reales de FullPOS, el límite de 9.000 caracteres cortaba la guía antes de
   `Pasar a ticket` y `Cobrar y facturar`. Astra inicialmente también omitió esos
   pasos. Se amplió a 16.000 el presupuesto total, conservando el máximo de 6.000
   para conocimiento. La regresión falló antes y pasa después.
2. **Seguimiento:** la instrucción de dar todos los pasos se limita a quien pide el
   procedimiento; una duda posterior se responde puntualmente usando el historial.
   La repetición completa de pasos dejó de ser una condición incorrecta del auditor.
3. **Evaluación honesta:** el comprobador distingue preguntas completas de
   seguimientos y toma el modelo de los metadatos. La muestra anterior de Qwen
   sigue fallando 8/10; la nueva de Astra pasa 10/10. Las aserciones léxicas no
   sustituyen una revisión semántica; se leyeron las respuestas.
4. **Presentación de errores:** el controlador Flutter usa el mensaje público de
   `ApiException`, sin mostrar su representación técnica ni introducir una falsa
   respuesta del asistente en el historial. El aviso se presenta una sola vez.
5. **Hoja móvil:** se oculta el acceso flotante mientras está abierta, para evitar
   cubrir el texto. Su estado se restablece al cerrar.

## Evidencias y validación ejecutada

Archivos de esta continuación (se conserva el resto del trabajo anterior):

| Worktree | Archivo | Cambio |
| --- | --- | --- |
| APPYRA | `apps/api/.env.example` | Marcador vacío; sin la clave pegada |
| APPYRA | `apps/api/src/modules/conversations/prompt/prompt-builder.ts` | Presupuesto y seguimiento |
| APPYRA | `apps/api/src/modules/conversations/prompt/prompt-builder.spec.ts` | Regresión con configuración real |
| FullPOS | `apps/fulltech_app/lib/core/ai_assistant/application/ai_assistant_controller.dart` | Aviso público único |
| FullPOS | `apps/fulltech_app/lib/core/ai_assistant/presentation/widgets/global_ai_assistant_entry_point.dart` | Ocultar acceso móvil sin reemplazar navegación |
| FullPOS | `apps/fulltech_app/test/core/ai_assistant/ai_assistant_controller_test.dart` | Error legible, historial e identidad de reintento |
| FullPOS | `apps/api/scripts/audit-ai-live-results.cjs` | Evaluación por tipo de pregunta y fuente declarada |
| FullPOS | `docs/EXECUTION_STATE.md`, `docs/ia-auditoria/2026-11-20/` | Informe y evidencias ficticias |

- [Diez escenarios con Astra](openai/conversaciones-reales.json): consulta abierta,
  seguimiento, funciones desconocidas, solicitud genérica de avería, referencia
  real, reintento idempotente, otra empresa, sesión inexistente y recuperación.
  **10/10 técnicos y 10/10 de contenido**, con revisión manual.
- Flujo real: Flutter → FullPOS local → APPYRA local → OpenAI externo → PostgreSQL
  local. La captura `openai/evidencias/escritorio-astra.png` muestra el procedimiento
  completo y fue inspeccionada visualmente. Las respuestas curadas siguen
  identificadas como `appyra-ia-rules`; no se atribuyen al modelo.
- Tras ajustar el seguimiento, las dos consultas reales tardaron **5,84 y 5,64 s**.
  Son mediciones puntuales, no un compromiso de latencia.
- PostgreSQL acredita 14 llamadas correctas a `gpt-6.2-astra`, 42.422 tokens de
  entrada y 2.656 de salida: **US$0,445616** hasta esa comprobación.

Comandos ejecutados en APPYRA (`apps/api`):

```text
npm run typecheck
PASS
npm run lint
PASS tras retirar dos aserciones no nulas del test nuevo
npm test -- --runInBand
82 suites, 929 pruebas PASS
npm run eval:bank
171/171 PASS (banco determinista, no 171 llamadas a OpenAI)
```

Comandos ejecutados en FullPOS:

```text
node apps/api/scripts/audit-ai-live-results.cjs <resultados-Astra> <informe>
10/10 PASS
node apps/api/scripts/audit-ai-live-results.cjs <resultados-Qwen> <informe-privado>
8/10 FAIL conservado
flutter test test/core/ai_assistant
34 PASS tras corregir la expectativa del saludo inicial en la prueba nueva
```

Los ejecutores privados verifican propietario del laboratorio y destino local.
Credenciales, tokens, registros privados y scripts con acceso al estado del
laboratorio no forman parte del repositorio. Las 597 omisiones y sus condiciones
continúan inventariadas en el informe inicial; ninguna es de `ai-assistant`.

## Pendientes de esta continuación

### Cierre ejecutado de interfaz

```text
flutter test test/core/ai_assistant
34 PASS; el primer intento del test nuevo no descontaba el saludo inicial;
se corrigió la expectativa para conservar ese mensaje y detectar sólo errores añadidos.
flutter analyze
PASS, sin incidencias (101,1 s)
flutter build web --release --dart-define=FULLPOS_UAT_PROFILE=true --dart-define=FULLPOS_UAT_BUILD=true --dart-define=APP_ENV=uat --dart-define=API_BASE_URL=http://127.0.0.1:4004/api --dart-define=APP_BASE_URL=http://127.0.0.1:4004
PASS, compilación final 74,2 s
node <script privado>/ia_browser_e2e.cjs --mobile-only
PASS, 390×844; acceso flotante oculto, consulta real y un POST abortado simulado.
git diff --check
PASS en ambos worktrees
```

Se inspeccionó [la captura móvil final](openai/evidencias/movil-error-limpio.png):
un solo aviso, sin representación técnica de excepción y sin botón flotante
cubriendo la hoja. Se conservaron el Navigator y el estado del punto de venta.
La captura no acredita un ensayo físico Android/iOS.

### Bloqueante conservado: automatización del reintento

Comando: `node <script privado>/ia_browser_e2e.cjs --connectivity-only`.
El primer ensayo agotó `page.waitForResponse` a 30 s. El circuito global bloquea
peticiones durante 12 s tras una falla de conexión; se respetó esa ventana sin
desactivar la protección. Después falló `Recovery identity/content failure`.
La consulta de PostgreSQL local mostró `customer_message="¿Cóm"`: se había
enviado otro texto, por lo que no era una repetición válida. El tercer ajuste,
con una comprobación antes de enviar, terminó en **`Incomplete fault probe text`**.
Se detuvieron las correcciones repetidas conforme al límite de AGENTS.md.

No se atribuye ese resultado a un fallo demostrado de idempotencia del producto;
tampoco se declara PASS. Las pruebas unitarias de reutilización de identificador
y el reintento HTTP real sí pasan. Para desbloquear: corregir en una siguiente
revisión la entrada/foco de la automatización de Flutter, demostrar igualdad del
texto e identificador y comprobar la respuesta real tras reconectar. No basta
con ampliar el timeout ni con omitir la aserción.

### Otras limitaciones

- Revisar por separado el inventario de conocimiento frente a los módulos
  actuales; una batería de diez preguntas no demuestra cobertura de todo FullPOS.
- Publicación y configuración productiva requieren revisión y autorización
  posterior. No están realizadas ni autorizadas por guardar la clave local.

**Estado final: NO-GO para producción.** Credencial, Astra, corrección de contexto,
calidad de los diez escenarios y presentación local verificados; reintento de
navegador pendiente. Laboratorio para revisión del propietario:
`http://127.0.0.1:4004/__local_demo` (sólo en esta máquina).
