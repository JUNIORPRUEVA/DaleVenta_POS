# Arquitectura verificada (corrección del plan)

Fecha: 2026-11-16. Sustituye la suposición de los documentos 05–07 sobre **quién manda**.
Todo lo de abajo está verificado leyendo el código y la documentación existente.

---

## 1. La cadena real (verificada)

```
APPYRA web / APPYRA CRM  (interfaz del propietario)
        ↓
ventas_appyra            = FULLTECHPOS_BAKEND_LICENCIA  (backend administrativo)
        ↓  daleventasLicenseController  (puente)
daleventapos_backend     = apps/api de DaleVentas (NestJS)  ← autoridad técnica
        ↓
Company + licencia en PostgreSQL de DaleVentas
```

Prueba documental (`.local-integration/licensing-readiness/PROCEDIMIENTO.md`, 2026-11-14):

> «`FULLTECHPOS_BAKEND_LICENCIA` es el backend del panel APPYRA que el propietario utiliza para
> gestionar las licencias de DaleVentas. Está publicado como `ventas_appyra`… **se conserva como punto
> de administración y de integración del CRM**.»
>
> «Recorrido comprobado: **web APPYRA → `/api/admin/daleventas-licenses/companies/...` en
> `ventas_appyra` → puente `daleventasLicenseController` → `/license/admin/...` en DaleVentas →
> empresa/licencia**.»
>
> «Los **planes y perfiles comerciales de APPYRA** se gestionan además mediante
> `/api/admin/daleventas-commercial`.»

## 2. Qué existe ya en cada sistema

### `FULLTECHPOS_BAKEND_LICENCIA` (APPYRA / `ventas_appyra`)

| Pieza | Verificado |
| --- | --- |
| Planes | Tabla **`daleventas_commercial_plans`** (`code`, `display_name`, `description`, `monthly_equivalent_price`, `currency`, `minimum_billing_months`). Códigos permitidos: **`BASIC`, `BUSINESS`, `PRO`** |
| Perfiles por empresa | Tabla **`daleventas_commercial_profiles`** (`external_company_id`, snapshots de plan y de límites) |
| **Excepciones** | Ya existen: `override_max_users`, `override_max_products`, `override_max_warehouses`, `override_max_devices` |
| Auditoría | `daleventas_commercial_audit_logs` |
| API de planes | `/api/admin/daleventas-commercial/plans` (GET, POST, GET :id, PATCH) |
| API de perfiles | `/profiles`, `/profiles/:companyId`, `/assign-plan`, `/overrides`, `/audit` |
| Puente a DaleVentas | `daleventasLicenseRoutes` → `daleventasLicenseController` → `/license/admin/...` |
| Pagos | `licensePaymentOrdersModel`, `adminLicensePaymentsRoutes` (PayPal), **`bankTransferService` + `serviceBankTransferRoutes`** |
| Banco | **En cuarentena**: responde `503 daleventas_authority_not_integrated`; su tabla `licenses` no es la autoridad de DaleVentas |
| PayPal | **Descartado**: «transferencia bancaria es el único método aprobado» |

### APPYRA CRM (`APPYRA_CRM`)

| Pieza | Verificado |
| --- | --- |
| Pantalla de licencias | `app/lib/features/licencias/licencias_screen.dart` |
| **Botones que ya existen** | **Editar**, **Suspender**, **Reactivar**, **Eliminar (revocar)** |
| Motivo obligatorio | `license_command_dialog.dart` exige motivo de ≥5 caracteres y usa comandos versionados (`expectedVersion`, `action`, `reason`, `fields`, `confirmationName`) |
| Llamada | `manageLicense(...)` → backend del CRM → puente |
| Pantalla de planes | **No existe** (los planes se administran en el backend APPYRA, no en el CRM) |

### DaleVentas (`apps/api` de `DaleVenta_POS`)

| Pieza | Verificado |
| --- | --- |
| Autoridad técnica | `Company` + `LicenseStatus` + `maxUsers`/`maxProducts` |
| Puente CRM | `GET /license/integrations/crm/capabilities`, `/companies`, `/companies/:id`, `POST /:companyId/commands` |
| Comandos | `update`, `suspend`, `reactivate`, `revoke`, **con motivo obligatorio** |
| Autoservicio | `POST /license/activate` y `PATCH /license/limits` permiten al admin de la empresa cambiar derechos **sin pago confirmado** (riesgo ya documentado por el propietario) |
| Licencia vencida | bloquea el **login** (401) |

## 3. Qué estaba mal en los documentos 05–07

| Suposición mía | Realidad verificada |
| --- | --- |
| Los planes se crearían en DaleVentas (`license_plans`) | **Ya existen en APPYRA** (`daleventas_commercial_plans`) y su administración está allí |
| Las excepciones se editarían en `Company` | **Ya existen como overrides** en APPYRA (`override_max_*`) |
| Los botones había que construirlos | **Ya existen** en el CRM: Editar, Suspender, Reactivar, Revocar, con motivo obligatorio |
| Solo hay 3–4 planes por decidir | APPYRA admite **3 códigos** (`BASIC`, `BUSINESS`, `PRO`); la web publica **4** (incluye Empresa) |
| El flujo de banco había que crearlo | Hay un prototipo **en cuarentena a propósito**: no se puede usar para licencias de DaleVentas |

## 4. Qué queda realmente por hacer (revisado)

| # | Pieza | Dónde |
| --- | --- | --- |
| 1 | **Catálogo legible por la app**: el cliente necesita ver planes y precios | DaleVentas: proyección **de solo lectura** del catálogo de APPYRA (o endpoint público de APPYRA) |
| 2 | **Órdenes + subida de comprobante** del cliente | DaleVentas (la app habla con su API) |
| 3 | **Activación inmediata** al subir comprobante | DaleVentas (`activateCompany`) |
| 4 | **Aviso por WhatsApp con la imagen** al administrador | Cloud API; ubicación a decidir (DaleVentas o APPYRA) |
| 5 | **Recordatorios 5 y 1 día** | Igual que 4 |
| 6 | **Marcar pago y bloquear** desde el CRM | **Ya existe**: botones + motivo; solo falta enlazar la orden de pago |
| 7 | **Cerrar el autoservicio** (`/license/activate`, `/license/limits`) | DaleVentas |
| 8 | **Acceso del vencido a Planes** | DaleVentas + Flutter |
| 9 | **Alinear la web** con el catálogo | `website/` |

## 5. Conflictos que hay que resolver antes de seguir

| # | Conflicto | Opciones |
| --- | --- | --- |
| **X-1** | APPYRA admite **3 planes** (`BASIC`, `BUSINESS`, `PRO`); la web publica **4** (con Empresa) | (a) añadir `ENTERPRISE` en APPYRA; (b) retirar Empresa de la web |
| **X-2** | Precios: APPYRA tiene 1.000/1.500/2.500 (migración 052); la web 1.000/2.000/3.000/4.500 | Definir cuál manda: **la web es lo publicado**, pero APPYRA es la administración |
| **X-3** | ¿Quién emite el aviso de WhatsApp: DaleVentas o APPYRA? | DaleVentas ya tiene el comprobante y el módulo de notificaciones; APPYRA es el panel donde se revisa |
| **X-4** | El código que ya escribí (`license_plans` en DaleVentas) | (a) convertirlo en **proyección de solo lectura**; (b) descartarlo y consultar APPYRA |
| **X-5** | La cuarentena del banco impide usarlo | Confirmar que la autoridad del pago es DaleVentas y que APPYRA solo revisa |

## 6. Recomendación

1. **No crear un catálogo paralelo**: la autoridad de planes y overrides se queda en APPYRA.
2. En DaleVentas, dejar `license_plans` como **proyección de solo lectura** (se sincroniza por el puente
   existente) para que la app tenga catálogo aunque APPYRA no esté disponible.
3. Las **órdenes y comprobantes** sí viven en DaleVentas, porque es la base de la empresa y del pago.
4. Los **botones siguen en el CRM** y el **motivo ya es obligatorio**.
5. Cerrar el **autoservicio** en DaleVentas (riesgo ya señalado por el propietario).

**Nada de esto se implementa hasta resolver X-1, X-2 y X-4.**
