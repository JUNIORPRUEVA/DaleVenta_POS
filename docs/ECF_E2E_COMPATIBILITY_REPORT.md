# e-CF — Reporte E2E y de compatibilidad

Worktree `FULLPOS-ECF-ALANUBE`, rama `feature/ecf-alanube`. Fecha: **2026-10-15**.
Sin `commit`, sin `push`, sin `deploy`. Producción y UAT histórica **intactas**.

Etiquetas: **IMPLEMENTADO** · **PROBADO** · **SIMULADO** · **NO PROBADO** · **BLOQUEADO**.

---

## 1. Qué se ha probado y cómo

**PROBADO — E2E vertical por HTTP real contra PostgreSQL desechable.**

`apps/api/src/ecf/ecf-documents-http.e2e-spec.ts` levanta la **aplicación NestJS
completa** (`AppModule`) contra una base **creada para la ejecución**
(`fullpos_http_e2e_<ts>`), aplica las migraciones, y conduce el sistema con
`supertest`: **login real, JWT real, `AuthGuard`/`RolesGuard` reales, DTO real**.

Esto es distinto de los `*-integration-spec.ts` previos, que llamaban a los
servicios directamente. Aquí el camino es: petición HTTP → guardas →
controlador → servicio → PostgreSQL → respuesta.

```
pwsh scripts/ecf-test-db/run-focused.ps1 -Pattern "ecf-documents-http"
→ Test Suites: 1 passed, Tests: 3 passed
```

### Alcance declarado (y sus límites)

| Pieza | Cómo entra | Por qué |
| --- | --- | --- |
| Empresa + administrador | **HTTP** (`POST /auth/register-business`) | Es superficie real del backend |
| Sesión | **HTTP** (`POST /auth/login`) | Prueba que el backend nuevo autentica igual |
| Configuración e-CF | **HTTP** (`PATCH /ecf/config`) | Superficie e-CF |
| Numeración | **HTTP** (`POST /ecf/sequences`) | Superficie e-CF |
| Preparación E31/E32/E34 | **HTTP** | Superficie bajo prueba |
| Bandeja y detalle | **HTTP** | Superficie bajo prueba |
| Ventas | **Sembrada por Prisma** | Es **precondición**, no código e-CF: el flujo POS completo no es parte de esta superficie |
| Original aceptado (E34) | **Sembrado por Prisma** | Por diseño **no existe endpoint que emita**, así que no puede producirse por HTTP |
| Interfaz gráfica Flutter | **NO PROBADA** | No se automatizó navegación real: se declara como limitación |

Ninguna evidencia es real: las filas sintéticas llevan
`reasonCode: "SYNTHETIC_TEST_ONLY_NOT_DGII"` y `evidenceRef`
`uat://synthetic-not-dgii/…`. **No hay ninguna aceptación de la DGII.**

## 2. Resultados por escenario

### E31 — PROBADO

1. Registro de empresa y **login** por HTTP → token válido.
2. `PATCH /ecf/config {enabled:true}` → 200.
3. `POST /ecf/sequences {E31, 1..20}` → 201.
4. `GET /ecf/capabilities` → `enabled: true`, **`emissionPathAvailable: false`**
   (la emisión no es alcanzable desde HTTP, y eso se comprueba).
5. `POST /ecf/documents/prepare` → `ok:true`, **e-NCF `E310000000001`**,
   `status: LOCAL_VALIDATED`, total `177.00 DOP`.
6. `GET /ecf/documents?documentType=E31` → 1 fila, con **e-NCF, importe, moneda,
   grupo `PENDING` y receptor congelado (`receiverTaxId`)**; el resumen del
   proveedor **no** se expone.
7. `GET /ecf/documents/:id` → historial de estados; **no** expone `fiscalDocument`.
8. **Reintento** de la misma operación → **mismo `documentId` y mismo e-NCF**.
9. PostgreSQL: **1 documento**, y el rango sigue en `nextNumber = 2`
   (el reintento **no** consumió un segundo número).

### E32 — PROBADO

1. Preparación de consumo por HTTP → `documentType: E32`, **`encf: null`**,
   **`numberingState: PENDING_SANDBOX_SLOT`**, `status: LOCAL_VALIDATED`.
2. Los **rangos de la empresa no cambian** (`before === after`) y **no se crea
   ninguna fila de cupo de sandbox** (`ecfSandboxE32Trial.count === 0`).
3. Reintento → mismo documento; **1 documento** en la empresa.
4. Bandeja → 1 fila **sin e-NCF** y sin presentarse como aceptada.

### E34 — PROBADO

1. `GET /ecf/documents/eligible-originals` → el original aparece con
   **saldo `177.00`**.
2. Nota **PARCIAL** (1 de 3) → e-NCF `E340000000001`, reserva **59**.
3. El saldo baja a **`118.00`** (lo calcula el servidor).
4. **Exceso**: pedir la línea completa (177.00) cuando solo quedan 118.00 →
   **HTTP 409 `E34_INSUFFICIENT_FISCAL_BALANCE`** y **no deja reserva**.
5. Segunda nota parcial → e-NCF **`E340000000002`** (el exceso **no** gastó número).
6. Bandeja → 2 filas, con **`originalEncf`** apuntando al original y total `59.00`.
7. PostgreSQL: 2 documentos, **2 reservas**, **0 movimientos de inventario**,
   **1 venta** (la original, intacta).

## 3. Defectos encontrados y corregidos por el E2E

Ninguno de estos los detectaban los tests de servicio: aparecen solo al recorrer
el camino HTTP completo.

### 3.1 La bandeja no mostraba el e-NCF ya consumido — CORREGIDO

**Síntoma:** `POST /ecf/documents/prepare` devolvía `encf: E310000000001`, pero la
bandeja mostraba la misma fila con **`encf: null`**.

**Causa:** el e-NCF reservado al preparar vive en `payload_summary.emission.encf`;
la columna `external_document_number` la fija el **despacho**. La bandeja leía
solo la columna, así que todo borrador local aparecía sin número.

**Corrección** (`ecf-document-query.service.ts`): `encf = externalDocumentNumber ?? emission.encf`.
Se conserva `externalDocumentNumber` sin tocar como campo autoritativo, y **la
bandeja pasa a mostrar el número que el comprobante ya tiene consumido** — sin él
es imposible conciliar el borrador contra el rango.

### 3.2 Una nota rechazada por saldo gastaba un e-NCF — CORREGIDO

**Síntoma:** el intento de exceso **consumía** un número: la nota siguiente
recibió `E340000000003` en lugar de `E340000000002`. El número no se devuelve al
pool (correcto), pero se gastaba en una operación que iba a ser rechazada.

**Corrección** (`ecf-preparation.service.ts`): **pre-chequeo de saldo antes de
consumir numeración**. La autoridad sigue siendo la guarda transaccional de
`reserve()`, que cubre la carrera entre dos notas; el pre-chequeo solo
**adelanta** el mismo rechazo (`e34Conflict`, idéntico código).

**Trampa encontrada al corregirlo:** el pre-chequeo **rompía la idempotencia**, y
lo detectó la suite de servicio: en un reintento, el saldo ya está consumido por
la **propia** reserva de la nota, así que el reintento era rechazado. Ahora el
pre-chequeo **se omite cuando la operación ya existe**, consultando la clave de
idempotencia con el mismo generador que usa la preparación real
(`operationKeyFor`, un solo sitio donde vive el formato).

## 4. Matriz de compatibilidad con clientes actuales

**No se ha ejecutado ningún cliente anterior.** No se localizó un instalador ni
binario previo verificable, y no se ejecutan binarios no verificados. Por tanto
esta matriz es **contractual** (lado servidor), no de cliente real.

| # | Escenario | Resultado | Evidencia |
| --- | --- | --- | --- |
| A | Windows **antiguo** + backend nuevo | **BLOQUEADO** | No hay artefacto anterior verificado que ejecutar |
| B | Windows **nuevo** + backend nuevo | **NO PROBADO** | Requiere ejecutar la app |
| C | Web actual + backend nuevo | **NO PROBADO** | Requiere ejecutar la app |
| D | Android/iPhone + backend nuevo | **NO PROBADO** | Requiere dispositivo/emulador |
| E | Empresa **sin e-CF** | **PROBADO** | Sin `enabled`, `/ecf/*` no opera: `ECF_COMPANY_DISABLED` (suite PG E32) |
| F | Empresa con e-CF **deshabilitado** | **PROBADO** | Igual que E; además la app no ofrece la acción (`ecf_prepare_action_test`) |
| G | Empresa con **NCF tradicional** | **NO PROBADO** | No hay cliente real en esta sesión |
| H | Empresa con e-CF **habilitado** | **PROBADO** | E2E E31/E32/E34 completo por HTTP |

### Operaciones críticas

| Operación | Resultado | Evidencia |
| --- | --- | --- |
| **Login** | **PROBADO** | `POST /auth/login` real en el E2E (201 + token usable) |
| Registro de empresa | **PROBADO** | `POST /auth/register-business` en el E2E |
| Autorización por permisos | **PROBADO** | `RolesGuard` real: un rol sin permiso no entra (suite de seguridad existente) |
| Refresh token | **NO PROBADO** | No ejercitado en esta sesión |
| Apertura de turno | **NO PROBADO** | Requiere flujo POS completo |
| Ventas | **NO PROBADO** (por HTTP) | La venta se sembró; el `POST /sales` completo no se ejercitó |
| NCF tradicional | **NO PROBADO** | — |
| Caja / Inventario / Cotizaciones / Abonos / Reportes / Impresión | **NO PROBADO** | — |
| Sincronización offline | **NO PROBADO** | — |
| Actualizador Windows | **NO PROBADO** | — |

### Auditoría estática del diff — PROBADO

No hay artefacto antiguo ejecutable (versión actual `1.0.6+140`; no se
localizaron builds `+130/+132/+133`), así que la evidencia de compatibilidad es
la del **cambio real introducido por la rama**. Total en `apps/api/src`:
**5 archivos, +35 / −4**, y **todo** aditivo o de seguridad:

| Archivo | Cambio | Riesgo |
| --- | --- | --- |
| `app.module.ts` | +2 líneas (registra `EcfModule`) | Ninguno |
| `sales/sales.service.ts` | **+13 / −0**: solo **añade** `itemTypeSnapshot` | Ninguno en la respuesta |
| `common/uat-safety.ts` | Guardas **más estrictas** al arrancar | Ninguno: no cambia API |
| `main.ts` | Solo bajo `APP_ENV=uat && UAT_LOCAL_ONLY=true` | Ninguno fuera de ese modo |

**No hay eliminaciones de campos, ni cambios de forma en ninguna respuesta, ni
campos nuevos obligatorios en las peticiones.** Un cliente antiguo sigue enviando
y recibiendo lo mismo.

**Consideración de despliegue:** `sales.service.ts` escribe una columna nueva, así
que la migración aditiva debe aplicarse **antes** de que el backend nuevo atienda
tráfico.

### Compatibilidad de datos y esquema — PROBADO

- Las migraciones son **aditivas**: la columna `fiscal_document` es opcional y no
  reescribe filas.
- Un documento con `fiscal_document = NULL` (preparado por una versión anterior)
  **sigue funcionando** en bandeja y detalle (probado en
  `ecf-fiscal-document-persistence-postgres`).
- Ningún endpoint exige campos e-CF a empresas que no usan e-CF: el módulo está
  **apagado por defecto** y responde `ECF_COMPANY_DISABLED`.

**Conclusión honesta:** *no* se puede afirmar compatibilidad total con los
clientes instalados. Lo probado es el **contrato del servidor** y la
**compatibilidad de datos**. La matriz A–D y las operaciones no probadas quedan
**abiertas** y son requisito previo a cualquier despliegue.

## 5. Seguridad observada en el E2E

- Toda petición se acota por la empresa del token; los datos de la prueba son de
  empresas distintas y **no se cruzan**.
- Con e-CF apagado, la preparación se rechaza (`ECF_COMPANY_DISABLED`) y **no crea
  documento**.
- `payloadSummary` y `fiscalDocument` **no** se devuelven por las rutas de lectura.
- `emissionPathAvailable: false` se comprueba en el E2E: **ninguna petición HTTP
  puede alcanzar al proveedor**.

## 6. Limitaciones declaradas

1. **No hay E2E de interfaz gráfica.** No se automatizó navegación Flutter.
2. **No hay cliente antiguo ejecutado.** La matriz A–D y G están bloqueadas/no
   probadas.
3. La venta y el original aceptado se **siembran**: son precondiciones.
4. Nada de esto es evidencia fiscal: **no hay emisión, ni numeración real
   consumida, ni aceptación DGII**.

## 7. Cómo reproducirlo

```
pwsh scripts/ecf-test-db/up.ps1
pwsh scripts/ecf-test-db/migrate.ps1
pwsh scripts/ecf-test-db/run-focused.ps1 -Pattern "ecf-documents-http"
pwsh scripts/ecf-test-db/run-tests.ps1
```

La base desechable se crea y se destruye dentro de la propia ejecución.

## 8. GO / NO-GO

| Entorno | Veredicto | Motivo |
| --- | --- | --- |
| **Desarrollo local / UAT aislado** | **GO** | E2E vertical en verde, suites completas en verde, aislamiento histórico intacto |
| **Pruebas externas (Alanube/DGII)** | **NO-GO** | Faltan contrato E32, firma de webhook y credenciales |
| **Producción** | **NO-GO** | Sin certificación, sin matriz de compatibilidad de cliente real, sin E2E de interfaz |
| **Emisión fiscal real** | **NO-GO por construcción** | Ningún endpoint cablea el despacho |
