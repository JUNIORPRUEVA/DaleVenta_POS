# Runbook — piloto de la PRIMERA empresa en e-CF

> **Alcance.** Prepara el piloto de la primera empresa real. **No autoriza** la
> emisión fiscal real, ni el despliegue a producción, ni migraciones sobre datos
> compartidos. Cada paso indica quién lo hace y qué evidencia deja.

## 0. Regla que gobierna todo el runbook

`PRODUCTION_EMISSION_IMPLEMENTED = false`. Ningún paso de este documento la
cambia. La emisión real solo se habilita en una tarea futura, explícitamente
autorizada, y después de que §5 esté cerrado.

## 1. Preparación interna (sin la empresa, sin proveedor)

| # | Paso | Evidencia |
| --- | --- | --- |
| 1.1 | Base efímera de pruebas levantada e inmutable la UAT histórica | `pwsh scripts/ecf-test-db/run-tests.ps1` en verde |
| 1.2 | Suite e-CF completa en verde | `pwsh scripts/ecf-test-db/run-focused.ps1 -Pattern "src/ecf"` |
| 1.3 | Cliente Flutter en verde y sin hallazgos | `flutter analyze` + `flutter test` |
| 1.4 | Arnés UAT con proveedor real **apagado** | `ALANUBE_ENABLE_REAL_CALLS=false` |
| 1.5 | Pantalla de habilitación recorrida con evidencia visual | Capturas en el acta del piloto |

## 2. Preparación de la empresa (acompañada)

| # | Paso | Quién | Verificación |
| --- | --- | --- | --- |
| 2.1 | Datos fiscales completos y correctos (RNC, razón social, dirección) | Empresa | Requisito `FISCAL_DATA` resuelto |
| 2.2 | Certificado digital vigente | Empresa | Requisito `DIGITAL_CERTIFICATE` resuelto |
| 2.3 | Registro en el proveedor | Empresa + proveedor | Requisito `ALANUBE_REGISTRATION` resuelto |
| 2.4 | Secuencias e-NCF cargadas y verificadas | Empresa + soporte | Módulo de secuencias |
| 2.5 | Representación impresa acordada | Empresa + soporte | Requisito `PRINTED_REPRESENTATION` |

**Regla:** los requisitos se marcan resueltos cuando el **backend** lo observa
(etapa `COMPLETED`/`CONFIRMED`). La libreta de seguimiento interno no resuelve
nada por sí sola.

## 3. Tramitación externa (fuera del producto)

Solicitud de incorporación, pruebas del SET, simulaciones, declaración jurada y
autorización final **las tramita la empresa ante la DGII**. El producto registra
el avance y guarda la evidencia; no las realiza.

## 4. Registro de la autorización (cuando llegue)

1. Guardar el documento oficial como evidencia `OFFICIAL_DOCUMENT`
   (`POST /ecf/dgii/evidence`).
2. Revisarlo internamente (`PATCH /ecf/dgii/evidence/:id/review` con
   `REVIEWED`). Requiere el permiso `reviewEcfDgiiEvidence`.
3. Registrar la autorización (`POST /ecf/dgii/authorization`) con
   `source: DGII_OFFICIAL_RECORD`, la evidencia revisada y el identificador
   externo. Requiere `recordEcfDgiiOfficialVerification`.

Reglas que el backend impone y no se pueden saltar:

- Una **declaración manual**, aunque se marque como revisada, **no** autoriza.
- Un **documento oficial sin revisar** tampoco autoriza.
- Ninguna llamada HTTP puede poner el estado en `APPROVED`.

Tras el paso 3, la empresa queda `APPROVED` con `officialAuthorization = true`, y
**la emisión real sigue bloqueada** (`ECF_REAL_EMISSION_NOT_IMPLEMENTED`).

## 5. Lista GO / NO-GO del piloto

### GO

- [ ] Suite e-CF del backend en verde.
- [ ] Suite completa del backend en verde (sin fallos nuevos respecto al baseline).
- [ ] `flutter analyze` sin hallazgos y `flutter test` en verde.
- [ ] `tsc` sin errores y `prisma validate` válido.
- [ ] Aislamiento multiempresa verificado (una empresa no alcanza datos de otra).
- [ ] Permisos granulares verificados por HTTP (revisar ≠ autorizar).
- [ ] Evidencia visual de la pantalla de habilitación.
- [ ] La empresa tiene todos los requisitos obligatorios resueltos **por el backend**.
- [ ] Documento oficial archivado y **revisado** antes de registrar la autorización.

### NO-GO

- [ ] Cualquier suite en rojo.
- [ ] Cualquier duda sobre la autenticidad del documento oficial.
- [ ] Cualquier intento de declarar aceptación de la DGII sin evidencia oficial.
- [ ] Si el piloto exige **emisión real**: NO-GO por diseño hasta el cierre de §6.

## 6. Lo que falta antes de emitir de verdad

1. Respuestas escritas del proveedor (`ECF_ALANUBE_PROVIDER_QUESTIONS.md`).
2. Decisión sobre idempotencia y reintento seguro.
3. Implementación del envío real (hoy inexistente).
4. Ventana de UAT con la empresa y un comprobante de prueba **sin efecto fiscal**.
5. Autorización explícita en la tarea que lo habilite.

Mientras 1–5 no estén cerrados, la respuesta a «¿ya podemos emitir?» es
**no**.
