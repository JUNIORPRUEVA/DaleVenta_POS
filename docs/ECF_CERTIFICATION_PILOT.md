# Piloto del portal de certificación — identidad fiscal y despliegue

Complemento operativo de `docs/ECF_CERTIFICATION_PORTAL.md`. Aquí está lo que
cambió tras el hallazgo del RNC y lo que hay que saber antes de desplegar.

---

## 1. Hallazgo del RNC: origen y corrección

**Qué pasó.** El arnés local de pruebas creó una empresa con
`commercialName = "FULLTECH SRL"` y `rnc = 133306001`. Ese RNC es el ejemplo
genérico que usan las pruebas unitarias del proveedor DOSA
(`dosa-*.spec.ts`, y el comentario de `dosa-certification-intent.service.ts:70`),
**no** el de Fulltech.

**Alcance real (verificado).**

| Comprobación | Resultado |
| --- | --- |
| `133306001` en código de producción | Solo aparece en un **comentario** de ejemplo |
| `133306001` en `app_config` de producción | **0 filas** |
| `133306001` en tablas de producción | **0 filas** (esas tablas aún no existen allí) |
| Empresa afectada | Solo la empresa sintética del arnés local (`ce0914a6…`) |
| Credenciales / eventos / postulaciones con ese RNC | 0 credenciales, 0 webhooks, 1 intento local sin postulación |

**Corrección aplicada.** En la BD desechable se retiró el RNC prestado:

```
companies.name            → "PRUEBA LOCAL (no es FULLTECH)"
app_config.rnc            → "000000000"   (valor reservado, imposible como RNC real)
app_config.companyName    → "PRUEBA LOCAL (no es FULLTECH)"
ecf_dosa_certification_sessions.rnc → "000000000"
```

Verificado después: `133306001` aparece **0 veces** en `app_config`, en sesiones
y en credenciales.

**Regla que queda establecida.** El RNC de un cliente **solo** puede venir de su
registro fiscal canónico: `ecf_dgii_application_snapshots.payload.company.rnc`
(expediente) o `app_config.rnc`. Nunca de un valor escrito a mano, ni del
navegador, ni de otro cliente.

**Identidad canónica de FULLTECH en producción** (lectura puntual, sin cambios):

```
companyId : 165e3fca-6225-479b-8805-d2205f10536c
nombre    : FULLTECH, SRL
RNC       : 133080206   ← el registrado por la empresa en su configuración fiscal
```

> Hay una segunda empresa llamada `fulltech` sin RNC (7325b7c9…). Por eso el
> piloto se autoriza por **companyId**, no por nombre ni por RNC.

---

## 2. Compuerta del piloto (desactivada por defecto)

Variable de entorno:

```
ECF_PORTAL_PILOT_COMPANY_IDS=165e3fca-6225-479b-8805-d2205f10536c
```

- Acepta varios `companyId` separados por comas.
- **Vacía o ausente ⇒ portal cerrado para todos** (no hay valor por defecto
  permisivo).
- Se aplica en tres puntos: emisión de ticket, canje de sesión y lectura de
  contexto. Si una empresa sale de la lista, sus sesiones vivas dejan de servir.
- No basta con tener `manageEcfOnboarding`: hace falta ser de una empresa de la
  lista. Una empresa ajena recibe **403**.

Validación en vivo contra la API local (allowlist = empresa piloto):

```
PILOTO_A_TICKET=201     AJENA_B_TICKET=403
A_EXCHANGE=201          A_CONTEXT=200 (empresa y RNC del expediente, ecf=False)
SIN_TICKET=401
```

Y con la allowlist vacía:

```
TICKET_SIN_PILOTO=403   ← cerrado por defecto, incluso para la empresa piloto
```

---

## 3. Migraciones pendientes en producción (verificado 2026-11-02)

Producción tiene **183** migraciones aplicadas y **ninguna** tabla `ecf_*`. Faltan
**25** migraciones del repositorio, es decir, **todo el módulo e-CF**, no solo el
portal:

```
20261014120000_add_ecf_onboarding_base                    (crea 5 tablas ecf_*)
20261014143000_add_ecf_document_idempotency               (crea 3 tablas ecf_*)
20261014160000_ecf_stable_operation_identity              (índices)
20261014180000_ecf_e34_credit_integrity                   (índices/constraints)
20261014183000_ecf_fiscal_reference_uniqueness            (índices/constraints)
20261014200000_ecf_evidence_quarantine                    (constraints)
20261014220000_ecf_e32_single_trial                       (índices)
20261015090000_ecf_numbering_ranges                       (crea 2 tablas ecf_*)
20261015120000_sale_item_type_snapshot                    (ADD COLUMN nullable en "SaleItem")
20261015160000_ecf_fiscal_document_snapshot               (columnas en tablas ecf_*)
20261016120000_ecf_dgii_company_habilitation              (crea ecf_dgii_habilitations)
20261016180000_ecf_dgii_evidence_review                   (columnas en ecf_evidences)
20261016190000_ecf_line_classification_supervised         (crea ecf_line_classifications)
20261016191000_ecf_line_classification_audit_action       (valor de enum)
20261019120000_ecf_dgii_application_draft_snapshot_consent(crea ecf_dgii_application_snapshots)
20261019180000_ecf_dgii_draft_revision                    (columna en habilitations)
20261021120000_ecf_onboarding_role_assignment             (permisos/roles)
20261021180000_ecf_support_grants                         (crea ecf_support_grants)
20261021200000_ecf_support_audit_actions                  (valor de enum)
20261102120000_ecf_dosa_certification_sessions            (crea tabla)
20261102180000_ecf_dosa_webhook_events                    (crea tabla)
20261103090000_ecf_dosa_company_credentials               (crea tabla)
20261103150000_ecf_provider_dosa                          (valor de enum)
20261103200000_ecf_dosa_webhook_processing_state          (columna + índice)
20261103210000_ecf_certification_portal                   (crea 2 tablas del portal)
```

**Efecto sobre datos existentes:** las 24 primeras son aditivas. La única que
toca una tabla del POS tradicional es `20261015120000_sale_item_type_snapshot`:

```sql
ALTER TABLE "SaleItem" ADD COLUMN "item_type_snapshot" "product_item_type";
```

Columna **nullable, sin default y sin NOT NULL**: no reescribe ventas existentes
y no rompe a ningún cliente. No hay ningún `DROP` real en la lista (el texto
"DROP COLUMN" que aparece en esa migración está dentro de un comentario).

---

## 4. Riesgos de actualizar la API

| Riesgo | Mitigación |
| --- | --- |
| El servicio de producción tiene `RUN_MIGRATIONS=false` | Aplicar las migraciones **a mano** y verificar después; no confiar en el arranque |
| Desplegar la API sin migrar | Los endpoints e-CF fallarían; el resto del POS no se ve afectado porque los endpoints son nuevos |
| Migrar sin respaldar | `pg_dump` previo y verificación con `pg_restore --list` |
| Cambios en `SaleItem` | Columna nullable: sin impacto en ventas ni reportes existentes |
| Clientes antiguos | No se modifica ningún contrato de API existente; solo se añaden rutas `/ecf/*` |
| Piloto mal configurado | Allowlist vacía = portal cerrado; no se puede abrir por accidente |
| Espacio en disco del host (1 vCPU) | `docker builder prune -f` antes del build; nunca `image prune -a` |

---

## 5. Procedimiento mínimo de publicación

1. **Respaldo**: `pg_dump` de la BD de producción verificado con `pg_restore --list`.
2. **Migraciones** (una sola vez, en orden, sin `migrate reset`):
   `npx prisma migrate deploy` **solo** si el listado de pendientes coincide
   exactamente con las 25 anteriores. Si apareciera cualquier otra, detenerse.
3. **API**: desplegar la imagen nueva; comprobar `/health` y que
   `/ecf/certification-portal/context` responda 401 (ruta viva y cerrada).
4. **Variable del piloto**: `ECF_PORTAL_PILOT_COMPANY_IDS=165e3fca-…` (solo si se
   quiere habilitar ya; si no, dejarla vacía y el portal queda cerrado).
5. **Portal**: `pwsh -File scripts/dev/publish_ecf_portal.ps1 -Apply`
   (una página estática dentro del nginx existente).
6. **Verificación**: abrir el portal desde FullPOS con la cuenta de FULLTECH,
   comprobar recorrido, pulsar el botón y buscar `cert:ready`.

## 6. Reversión

- **Portal**: borrar `/usr/share/nginx/html/ecf` del contenedor. La PWA no se toca.
- **API**: volver a la imagen anterior por tag (la PWA y el POS no dependen de las
  rutas nuevas).
- **Migraciones**: **no** hacer `DROP TABLE` automático. Son tablas nuevas y
  vacías; si se revierte la API pueden quedarse sin efecto. Solo se eliminan a
  mano y con autorización explícita.
