# Preparación para certificación e-CF — estado por área

> **Este documento no certifica nada.** No existe ninguna certificación oficial
> de la DGII ni de Alanube en este repositorio. Lo que aquí se llama
> «validación local» es una prueba ejecutada por el equipo; «validación
> simulada» es un circuito interno sin proveedor; «validación sandbox
> autorizada» es una llamada real y puntual contra el entorno de pruebas del
> proveedor. Nada de eso es una homologación.
>
> Escala de evidencia usada: **HECHO** (ejecutado y verde), **PENDIENTE** (no
> ejecutado o bloqueado).
> ### Actualización 2026-10-18 — correcciones a este documento
>
> Las cifras de §1 son **históricas** (corresponden a la ejecución del 2026-10-16)
> y se conservan tal cual. Lo que ya **no** es cierto:
>
> | Afirmación antigua | Estado real verificado |
> | --- | --- |
> | B2: «partidas fuera de inventario no pueden facturarse y el mensaje promete una vía supervisada inexistente» | **RESUELTO** por F1 (`ECF_F1_CLASSIFICATION_REVIEW.md`): existe registro supervisado append-only, endpoint y diálogo |
> | §11 «UAT visual Windows NO GO (no ejecutada)» | Parcialmente superada: el build y el arranque se ejecutaron, y se detectó un **defecto del procedimiento** (ver `ECF_UAT_PROFILE_BUILD_SAFETY.md`) |
> | 62 suites / 726 pruebas / 41 migraciones | Posteriormente medido: **65 suites / 747 pruebas** y **43 migraciones** (2026-10-16) |
>
> Evidencia nueva del 2026-10-18: `npx tsc --noEmit` exit 0, `prisma validate`
> válido, **43 migraciones al día**, y compatibilidad legacy **10/10** (reintentos
> y turno cerrado incluidos).
## 1. Qué se ejecutó en esta misión

| Comprobación | Comando | Resultado |
| --- | --- | --- |
| Suite e-CF completa | `pwsh scripts/ecf-test-db/run-focused.ps1 -Pattern "src/ecf"` | **62 suites / 726 pruebas, 0 fallos** |
| Compilación TypeScript | `npx tsc -p tsconfig.build.json --noEmit` | **exit 0** |
| Esquema Prisma | `npx prisma validate` | **válido** |
| Estado de migraciones | `npx prisma migrate status` | **41 migraciones, al día** |
| Compatibilidad POS (§8) | `-Pattern "legacy-pos-compatibility"` | **6 pruebas, 0 fallos** |
| Concurrencia E34 | `-Pattern "ecf-e34"` | Incluye inserción directa concurrente en PostgreSQL |
| Aislamiento multiempresa | `-Pattern "ecf-dgii-http"` | 9 pruebas HTTP |

## 2. Estado por área

### 1. Motor fiscal local — **GO (local)**

Motor puro con aritmética decimal (`ecf-money.ts`), redondeo explícito
`ROUND_HALF_UP` a 2 decimales y tolerancia de conciliación de **1 céntimo**,
justificada en el propio código (enteros de céntimos para evitar artefactos de
coma flotante). Un fallo se **devuelve**, nunca se sustituye por un valor por
defecto. Pruebas: `ecf-fiscal-core.spec.ts`, `ecf-validator`, `ecf-money`.

### 2. E31 — **GO (local, simulado)**

Orquestador con transporte simulado. Verificado: un E31 válido termina en
`HUMAN_REVIEW_REQUIRED` con `fiscalSnapshot: null`, y **cero** documentos en
`DGII_ACCEPTED`/`PROVIDER_ACCEPTED`. Un rechazo explícito también va a revisión
humana y **no** libera la secuencia.
Pruebas: `ecf-e31-emission-postgres.integration-spec.ts`.

### 3. E32 — **GO (local, simulado)**

Consumo con despacho simulado correlacionable, sin numeración real.
Pruebas: `ecf-e32-consumo-postgres.integration-spec.ts`,
`ecf-e32-trial-postgres.integration-spec.ts`, `e32-sandbox.spec.ts`,
`e32-response-assessment.spec.ts`, `alanube-dom-e32-compatibility.spec.ts`.

### 4. E34 — **GO (local, simulado)** — la cobertura más fuerte

28 pruebas de integración que incluyen, explícitamente:

- dos reservas incompatibles en paralelo → **una sola gana**;
- 8 réplicas idénticas en paralelo → **una** reserva y **un** evento;
- **inserciones directas concurrentes en PostgreSQL** → una sola pasa (el
  límite lo impone la base, no la aplicación);
- un *trigger* impide sobre-reservar y aplicar sin evidencia;
- resultados `UNKNOWN_RESULT` **retienen** el dinero y no se cancelan solos;
- un rechazo solo libera con evidencia que coincida;
- el saldo disponible nunca queda negativo (`E34_BALANCE_INTEGRITY_VIOLATION`).

Cumple el requisito obligatorio de §5 de la misión.

### 5. Multiempresa — **GO (local)**

Aislamiento por `companyId` derivado del contexto autenticado, con claves
foráneas compuestas que lo hacen imposible incluso por SQL directo.
Pruebas: `ecf-dgii-http.e2e-spec.ts`, casos 3/17/28 de `ecf-e34-postgres`.

### 6. RBAC — **GO (local)**

Permisos por cadena, con alias para lo ya concedido y **sin alias** para las dos
operaciones sensibles. Verificado por HTTP: 401 sin token, 403 por permiso,
403 al consultar sin permiso de vista, ADMIN por rol.

### 7. Persistencia — **GO (local)**

Inmutabilidad por *trigger*, historial *append-only*, idempotencia por
`requestFingerprint` con detección de reintento divergente.

### 8. Migraciones — **GO CON RESERVA**

Ver `ECF_PRISMA_MIGRATION_RISK.md`. Deriva preexistente **no corregida** a
propósito.

### 9. Compatibilidad POS — **GO (local)**

Ver `ECF_LEGACY_POS_COMPATIBILITY.md`. Incluye dos dependencias abiertas
(valor del interruptor en producción y la brecha de partidas sin producto).

### 10. Flutter — **GO (local)**

`flutter analyze` sin hallazgos; suite completa verde. El cliente no afirma nada
que el backend no afirme.

### 11. UAT visual Windows — **NO GO (no ejecutado en esta misión)**

La copia aislada en ruta corta (`C:\b\ecf`) sigue siendo el método válido, pero
**no se recompiló ni se ejecutó la UAT visual en esta misión**. No se declara
PASS visual sin ejecución.

### 12. Alanube — **NO GO**

Contrato aclarado solo en parte: persiste la discrepancia de `stampDate`,
`trackId` y `signatureDate` en `GET /invoices/{id}`. Hay preguntas bloqueantes
sin responder (`ECF_ALANUBE_PROVIDER_QUESTIONS.md`).

### 13. DGII — **NO GO**

No hay ninguna comunicación oficial de la DGII en este repositorio. La
habilitación por empresa es **seguimiento interno**; `APPROVED` solo se alcanza
registrando un documento oficial revisado, y eso no lo verifica el producto.

### 14. Emisión real — **NO GO por diseño**

`PRODUCTION_EMISSION_IMPLEMENTED = false`. El interruptor de seguridad exige
`environment === "SANDBOX"` en la primera comprobación, así que producción es
estructuralmente imposible. **No se implementó ningún bypass.**

### 15. Producción — **NO GO**

No se desplegó, no se migró, no se emitió, no se consumió numeración.

## 3. Brechas abiertas (priorizadas)

| # | Brecha | Impacto | Acción propuesta | Estado |
| --- | --- | --- | --- | --- |
| B1 | `FINANCIAL_LEGACY_COMPAT` sin confirmar en producción | Los clientes instalados antiguos podrían no poder vender | Confirmar el valor real en el entorno | **PENDIENTE** |
| B2 | Partidas fuera de inventario no pueden facturarse electrónicamente y el mensaje promete una vía supervisada inexistente | Bloquea un tipo de venta legítimo | Decisión de producto (retirar la promesa o añadir `itemType` al DTO) | **PENDIENTE** |
| B3 | Los endpoints `prepare*` devuelven 2xx con `ok:false` | Un cliente que solo mire el estado creerá que preparó | Documentado; conviene valorar un código de estado acorde | **HECHO / riesgo aceptado** |
| B4 | Discrepancia de esquema en la lectura de Alanube | Reconciliación no fiable | Respuesta escrita del proveedor | **PENDIENTE** |
| B5 | UAT visual Windows de la interfaz actual | No hay evidencia visual de esta versión | Recompilar en `C:\b\ecf` y ejecutar la UAT | **PENDIENTE** |

## 4. Lo que NO se hizo

Se declara explícitamente para que nadie lo asuma:

- No se crearon matrices separadas por comprobante
  (`ECF_E31_CERTIFICATION_MATRIX.md`, `ECF_E32_*`, `ECF_E34_*`). La cobertura
  real de esos tres documentos **ya existe como pruebas ejecutables** y se
  enumera arriba con sus archivos; duplicarla en tres ficheros habría añadido
  volumen sin evidencia nueva.
- No se ejecutó la UAT visual de Windows.
- No se probó compatibilidad con APKs antiguos en dispositivo real.
- No se hizo ninguna llamada real a Alanube ni a la DGII.
- No se corrigió la deriva preexistente de Prisma.
- No se implementó emisión real ni ningún bypass de sus comprobaciones.
