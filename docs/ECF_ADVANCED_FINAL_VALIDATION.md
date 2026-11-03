# e-CF — Validación final avanzada

Worktree `FULLPOS-ECF-ALANUBE`, rama `feature/ecf-alanube`. Fecha: **2026-10-15**.
Sin `commit`, sin `push`, sin `deploy`. Producción y UAT histórica **intactas**.

Etiquetas: **IMPLEMENTADO** · **PROBADO** · **SIMULADO** · **NO PROBADO** · **BLOQUEADO**.

---

## 1. Funcionalidades implementadas en esta sesión

### 1.1 Simulador Alanube por escenarios — IMPLEMENTADO + PROBADO

`apps/api/src/ecf/alanube/alanube-scenario.transport.ts` (+ `…spec.ts`).

El simulador anterior era un **stub con una sola respuesta fija**: no podía
reproducir ningún escenario adverso. El nuevo:

- Reproduce **los 16 escenarios** pedidos: recibido, proveedor acepta, proveedor
  rechaza, DGII acepta/rechaza (simulado), timeout, 429, 500, respuesta
  duplicada, fuera de orden, caída de conexión, reintento idempotente, respuesta
  malformada, estado desconocido, reinicio de proceso y recuperación pendiente.
- **Guion configurable** con repetición: permite modelar un reintento contra el
  mismo proveedor.
- **Identidad estable**: el identificador remoto se deriva del `requestId`, así
  que un reintento devuelve el MISMO id — la base para poder reconciliar.
- **Redacción**: registra las llamadas con la cabecera `authorization` y el
  cuerpo como `[REDACTED]`.
- Marca **toda** respuesta con `SIMULATED_NOT_OFFICIAL`: es un artefacto de
  prueba, no el contrato oficial.

**33 pruebas** (`alanube-scenario.transport.spec.ts`), entre ellas los
invariantes:

| Invariante | Resultado |
| --- | --- |
| Un **200** del proveedor nunca es aceptación fiscal | PROBADO (clase `UNKNOWN_OUTCOME` + revisión humana) |
| Un cuerpo ilegible (200 con HTML) falla cerrado | PROBADO |
| Un estado desconocido no se lee como aceptado | PROBADO |
| La **emisión nunca se reintenta**, en los 16 escenarios | PROBADO |
| Sin idempotencia verificada, la emisión no se reintenta | PROBADO |
| Timeout / caída de red sí se reintentan al leer, con espera creciente | PROBADO |
| Se agota al tercer intento (sin reintento infinito) | PROBADO |
| Ninguna clasificación devuelve una clase de "aceptación" | PROBADO |
| El reintento conserva la identidad remota | PROBADO |
| El reinicio conserva la identidad de la operación | PROBADO |
| No se filtran credenciales en el registro | PROBADO |
| Un guion vacío se rechaza en vez de simular en silencio | PROBADO |

### 1.2 Matriz exhaustiva de la máquina de estados — IMPLEMENTADO + PROBADO

`apps/api/src/ecf/documents/ecf-document-state-machine.matrix.spec.ts`.

Los estados se declaran **de forma independiente** en la prueba y se comparan
contra la implementación: **196 pares** (14 × 14) con y sin evidencia.

| Invariante fiscal | Resultado |
| --- | --- |
| El esquema persiste exactamente los 14 estados cubiertos | PROBADO |
| Solo se permite lo que la tabla declara (y reafirmarse) | PROBADO |
| Los estados terminales no tienen salida | PROBADO |
| Sin evidencia, ninguna aceptación ni rechazo es alcanzable | PROBADO |
| Con evidencia, las mismas transiciones sí se permiten | PROBADO |
| **PREPARADO ≠ ENVIADO**: un borrador no llega a aceptación | PROBADO |
| **Aceptado por el proveedor ≠ aceptado por la DGII** (paso intermedio obligatorio) | PROBADO |
| Un rechazo nunca se convierte en aceptación | PROBADO |
| La revisión humana no se resuelve sola | PROBADO |
| `DGII_ACCEPTED` solo se alcanza desde `DGII_STATUS_PENDING` | PROBADO |
| Un resultado desconocido no salta a aceptación DGII | PROBADO |

## 2. Errores encontrados

- **Un defecto en mi propia prueba**: el invariante "ningún escenario produce
  aceptación" incluía el 429, que tiene su propia clase (`RATE_LIMIT`, correcta y
  reintentable al leer). El invariante correcto es sobre **HTTP 200**. Corregido.
- **No aparecieron defectos de producto nuevos** en esta sesión.

## 3. Errores corregidos

- La aserción del invariante descrita arriba (prueba, no producto).
- De la sesión anterior, y ya en verde: la bandeja no mostraba el e-NCF reservado,
  y una nota rechazada por saldo consumía un e-NCF (con la regresión de
  idempotencia que introdujo la primera versión del arreglo).

## 4. Pruebas ejecutadas

```
flutter analyze                                     → No issues found!
flutter test                                        → 1325 passed, 1 skipped
npx tsc -p tsconfig.build.json --noEmit             → TSC_EXIT=0
npx prisma validate                                 → schema is valid
pwsh scripts/ecf-test-db/run-tests.ps1              → 127 suites passed (1 skipped), 1375 passed, 8 skipped
                                                       ISOLATION OK: 708/568/3462
pwsh … -Pattern "alanube-scenario"                  → 33 passed
pwsh … -Pattern "state-machine"                     → 20 passed
pwsh … -Pattern "ecf-documents-http"                → 3 passed (E2E HTTP + PostgreSQL)
git diff --check                                    → DIFFCHECK_EXIT=0
```

## 5. Pruebas pendientes (NO PROBADAS)

| Prueba | Motivo |
| --- | --- |
| **E2E gráfico de Flutter** (navegación real) | No se automatizó; requiere dispositivo/emulador y build de la app |
| **Cliente Windows antiguo** contra el backend | No existe artefacto verificable (ver §6) |
| **Pruebas contractuales por tipo** (E31/E32/E34 contra los esquemas) | No ampliadas en esta sesión |
| **Concurrencia HTTP** (dos solicitudes simultáneas por HTTP) | Cubierta a nivel de servicio (PG), no por HTTP |
| **Cierre de turno, NCF tradicional, cotizaciones, abonos, reportes, offline, impresión, actualizador** | No ejercitados |

## 6. Compatibilidad por versión — auditoría estática (PROBADO) y cliente real (BLOQUEADO)

**No hay ningún instalador ni build anterior verificable en el entorno.** La
versión actual del proyecto es `1.0.6+140`; no se localizaron artefactos de la
familia `1.0.6+130/+132/+133`. No se descargan ni ejecutan binarios de
procedencia desconocida, así que **la ejecución de un cliente antiguo está
BLOQUEADA por falta de artefacto**, no por falta de trabajo.

Lo que **sí** se ha verificado, y es lo que de verdad determina el riesgo:

**Todo el diff de esta rama fuera de `src/ecf/` es aditivo o de seguridad.**

| Archivo | Cambio | Riesgo de compatibilidad |
| --- | --- | --- |
| `app.module.ts` | +2 líneas (registra `EcfModule`) | Ninguno: aditivo |
| `sales/sales.service.ts` | **+13 / −0** | Ninguno en la respuesta: solo **añade** `itemTypeSnapshot` a las partidas |
| `common/uat-safety.ts` | Guardas **más estrictas** al arrancar | Ninguno: no cambia ninguna API |
| `main.ts` | Solo en `APP_ENV=uat && UAT_LOCAL_ONLY=true` | Ninguno fuera de ese modo |
| `sales/sales.service.fiscal-final.spec.ts` | Prueba | — |

**Total en `apps/api/src`: 5 archivos, +35 / −4.** No hay eliminaciones de campos,
ni cambios de forma en ninguna respuesta, ni campos nuevos obligatorios en las
peticiones. Un cliente antiguo sigue enviando y recibiendo lo mismo.

| Escenario | Resultado |
| --- | --- |
| Login / registro de empresa sobre el backend nuevo | **PROBADO** (E2E HTTP real) |
| Refresh token | **NO PROBADO** |
| Empresa **sin** e-CF | **PROBADO**: el módulo está apagado por defecto y responde `ECF_COMPANY_DISABLED` |
| Empresa con e-CF **deshabilitado** | **PROBADO** (igual que el anterior + la app no ofrece la acción) |
| Empresa con e-CF **habilitado** | **PROBADO** (E2E E31/E32/E34) |
| Empresa con **NCF tradicional** | **NO PROBADO** |
| Windows antiguo / nuevo, Web, Android, iPhone | **BLOQUEADO / NO PROBADO** |

**Consideración de despliegue:** `sales.service.ts` escribe una columna nueva, así
que la migración aditiva debe aplicarse **antes** de que el backend nuevo atienda
tráfico. Es el orden normal de una migración aditiva, y queda dicho.

## 7. Estado de Alanube

| Pieza | Estado |
| --- | --- |
| Cliente HTTP seguro (timeouts, redirecciones, redacción) | IMPLEMENTADO |
| Clasificación de errores | IMPLEMENTADO + PROBADO |
| Política de reintentos (emisión nunca; lectura con espera creciente; tope 3) | IMPLEMENTADO + PROBADO |
| Simulador de 16 escenarios | **IMPLEMENTADO + PROBADO** (esta sesión) |
| Interpretación de respuestas | IMPLEMENTADO; nunca concede aceptación DGII |
| Webhooks | Contrato e interfaz; **recepción operativa cerrada** |
| Llamadas reales | **Deshabilitadas** (`ALANUBE_ENABLE_REAL_CALLS=false`); ninguna en esta sesión |
| Firma oficial del webhook | **BLOQUEADO**: no documentada; no se inventa |

## 8. Estado E31 / E32 / E34

| | Preparación | Numeración | Emisión |
| --- | --- | --- | --- |
| **E31** | PROBADO (HTTP) | Consume el rango de la empresa; reintento reutiliza | **No alcanzable** |
| **E32** | PROBADO (HTTP) | **No consume nada**; `PENDING_SANDBOX_SLOT` | Bloqueada por contrato `PARTIAL_OFFICIAL` |
| **E34** | PROBADO (HTTP) | Rango propio; una nota rechazada **ya no** gasta número | **No alcanzable** |

## 9. Seguridad

PROBADO por suites existentes + el E2E: aislamiento por empresa en toda consulta
y mutación; un id ajeno es indistinguible de uno inexistente; E32/E34 no leen
ventas ni originales de otra empresa; con e-CF apagado no se crea documento;
`payloadSummary` y `fiscalDocument` no se devuelven. **Toda autorización está en
el backend** (`AuthGuard` + `RolesGuard`).

## 10. Integridad financiera

PROBADO en el E2E: preparar E31/E32/E34 no altera la venta, no crea movimientos
de inventario y no toca caja ni turnos. Una nota E34 **no** genera devolución de
dinero: reserva crédito fiscal y nada más.

## 11. Riesgos

| Riesgo | Severidad | Estado |
| --- | --- | --- |
| Cliente antiguo sin probar contra el backend nuevo | Media | Mitigado por la auditoría estática (diff aditivo); **no cerrado** |
| Contrato E32 `PARTIAL_OFFICIAL` sin confirmar | Alta | Bloquea emisión, no la preparación local |
| Firma del webhook no documentada | Alta | Recepción cerrada |
| Documentos anteriores con `fiscal_document = NULL` | Baja | Siguen funcionando; no se reconstruyen |
| `sales.service.ts` escribe columna nueva | Baja | Migración aditiva debe preceder al despliegue |

## 12. Bloqueantes externos

1. Confirmación del contrato E32 `PARTIAL_OFFICIAL`.
2. Mecanismo de firma del webhook.
3. Credenciales de sandbox y ventana autorizada.
4. Certificación DGII (ejecución y autorización humanas).
5. Artefacto de una versión anterior verificable para probar el cliente real.

## 13. GO / NO-GO

| Entorno | Veredicto | Motivo |
| --- | --- | --- |
| **UAT** | **GO** | 1375 pruebas backend, 1325 Flutter, E2E HTTP 3/3, aislamiento histórico intacto |
| **Sandbox externo** | **NO-GO** | Bloqueantes 1–3: sin contrato E32 ni firma de webhook ni credenciales, cualquier prueba externa sería una simulación presentada como real |
| **Producción** | **NO-GO** | Sin certificación DGII, sin E2E gráfico, sin cliente antiguo probado |
| **Emisión fiscal real** | **NO-GO por construcción** | Ningún endpoint cablea el despacho |
