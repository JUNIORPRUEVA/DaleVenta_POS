# Auditoría completa: APPYRA y FULLTECHPOS_BAKEND_LICENCIA

Fecha: 2026-11-16. Solo lectura: **no se modificó ningún archivo** de estos dos sistemas.
Cada hallazgo cita el archivo donde se comprobó.

---

## 1. Alcance y método

| Sistema | Ruta auditada | Qué se revisó |
| --- | --- | --- |
| Backend de licencias | `FULLTECHPOS_BAKEND_LICENCIA/backend` | 37 archivos de rutas, controladores, modelos, servicios, `server.js`, migraciones |
| Panel administrativo | `FULLTECHPOS_BAKEND_LICENCIA/admin` | páginas y acciones |
| CRM | `APPYRA_CRM` (Flutter + backend Node) | pantallas, repositorio, cliente de licencias, rutas y WhatsApp |

No se ejecutaron escrituras ni peticiones contra producción.

## 2. Inventario del backend de licencias

**170 endpoints** detectados en **37 archivos de rutas**. Los grupos relevantes:

| Grupo | Prefijo | Endpoints clave |
| --- | --- | --- |
| Licencias (legacy APPYRA) | `/api/admin/licenses` | crear, listar, `bloquear`, `vencer`, `activar-manual`, `desbloquear`, `extender-dias`, `reset-activations`, `license-file` |
| **Puente DaleVentas (admin)** | `/api/admin/daleventas-licenses` | `GET /companies`, `GET /companies/:id`, `/usage`, `PATCH /companies/:id`, `POST /activate`, `POST /block`, `DELETE`, `DELETE /permanent` |
| **Servicio DaleVentas (token)** | `/api/service/daleventas` | `GET /whoami`, `/projects`, **`/plans`**, `/licenses`, `/licenses/:id`, `/customers`, `/customers/:id`, `/bank-transfers` → **501** |
| Comercial APPYRA | `/api/admin/daleventas-commercial` | `plans` (GET/POST/PATCH), `profiles`, `assign-plan`, `overrides`, `audit` |
| Pagos | `/api/admin/license-payments` | órdenes PayPal (crear, capturar, listar, health), `demo` |
| Público | `/api/public/license…` | validar, demo, `projects/:code/billing`, PayPal, `register-or-find`, `import-activation` |
| Portal | `/api/billing-portal` | `plans`, `subscriptions`, `license`, `subscription/status` |
| Banco | `/api/service/bank-transfers` | **No montado**; el router además devuelve `503 daleventas_authority_not_integrated` |

### Base de datos comercial (la buena)

| Tabla | Contenido verificado |
| --- | --- |
| `daleventas_commercial_plans` | `code` (**BASIC, BUSINESS, PRO**), `display_name`, `monthly_equivalent_price`, `currency`, `minimum_billing_months`, `minimum_payment` |
| `daleventas_commercial_profiles` | `external_company_id`, snapshots de plan y límites, **`override_max_users/products/warehouses/devices`** |
| `daleventas_commercial_audit_logs` | auditoría de cambios |

## 3. Inventario del CRM de APPYRA

### Pantallas (Flutter)

`app/lib/features/`: `licencias`, `cobros`, `clientes`, `soporte`, `seguimiento`, `whatsapp`, `ajustes`, `usuarios`, `perfil`, `compartir`.

En `licencias`: `licencias_screen.dart`, `license_activity_panel.dart`, **`license_command_dialog.dart`**, `preview/`.

### Rutas de licencias que expone el CRM

`GET /api/admin/licensing/status | projects | plans | licenses | customers | payments`
`POST /api/admin/licensing/licenses/:id/commands` ← reenvía a `/api/service/daleventas/licenses/:id/commands`

### WhatsApp del CRM

`backend/server/whatsapp.mjs`: usa **solo la API oficial de Meta** (`graph.facebook.com`), con
`WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`, y sabe **listar plantillas** del WABA.
Nunca registra el token.

## 4. Flujos verificados

### ✅ Lectura (funciona)

```
CRM (Flutter) → /api/admin/licensing/* → /api/service/daleventas/* → APPYRA → datos
```
Los planes se sirven desde `daleventas_commercial_plans`, con `authority: 'DALEVENTAS'`.

### ❌ Escritura desde el CRM (no existe el endpoint)

```
CRM → POST /api/admin/licensing/licenses/:id/commands
    → POST /api/service/daleventas/licenses/:id/commands   ← NO EXISTE
```

`serviceDaleventasRoutes.js` solo define **8 rutas GET**. No hay `commands` ni `activity`.
→ **Los botones Editar, Suspender, Reactivar y Revocar del CRM fallan contra DaleVentas.**

### ✅ Escritura real (solo desde el panel web APPYRA)

```
admin/*.html → /api/admin/daleventas-licenses/companies/:id/(activate|block|PATCH|DELETE)
             → puente daleventasLicenseController
             → DaleVentas /license/admin/...
```

### ❌ Transferencia bancaria

- `serviceBankTransferRoutes` **no está montado**.
- Su router devuelve `503 daleventas_authority_not_integrated` (cuarentena explícita).
- `/api/service/daleventas/bank-transfers` responde **501 `daleventas_bank_transfers_unavailable`**.
- **PayPal**: se conserva el código, pero el propietario dejó escrito que **no se desarrollará**.

## 5. Hallazgos

| ID | Severidad | Hallazgo | Evidencia |
| --- | --- | --- | --- |
| **H-01** | **Crítico** | Los botones de licencia del CRM apuntan a un endpoint que no existe → 404 | `licensing/client.mjs:191`, `licensing/routes.mjs:202-203`, `serviceDaleventasRoutes.js` (sin `commands`) |
| **H-02** | **Crítico** | Cualquier admin de empresa puede activarse la licencia y subir límites sin pago | `license.service.ts` (`activateMyLicense`, `updateMyLimits`) y documento del propietario |
| **H-03** | **Alto** | Licencia vencida bloquea el **login** (401), impidiendo pagar | `jwt.strategy.ts` |
| **H-04** | **Alto** | APPYRA admite **3 planes**; la web publica **4** | `daleventasCommercialModel.js:3` vs `website/src/config/site.ts` |
| **H-05** | **Alto** | Precios divergentes: APPYRA 1.000/1.500/2.500 · web 1.000/2.000/3.000/4.500 | misma evidencia |
| **H-06** | **Alto** | No existe camino de pago del cliente en DaleVentas (ni orden, ni comprobante) | `apps/api/src/license` |
| **H-07** | **Medio** | No hay flujo bancario operativo en ningún sistema | rutas en cuarentena / 501 |
| **H-08** | **Medio** | WhatsApp: el CRM ya usa Cloud API; DaleVentas solo tiene Evolution (descartado) | `whatsapp.mjs` vs `notifications/evolution-whatsapp.service.ts` |
| **H-09** | **Medio** | `MIGRATION_STRICT=false`: el servicio arranca aunque falle una migración | `scripts/start-prod.sh` |
| **H-10** | **Bajo** | Conviven dos modelos de licencia: `licenses` de APPYRA y `Company` de DaleVentas | rutas admin legacy vs puente |

## 6. Qué falta de verdad para la estrategia

| # | Pieza | Sistema | Estado |
| --- | --- | --- | --- |
| 1 | Comandos de escritura para el CRM | APPYRA (`serviceDaleventasRoutes`) | **Falta** (H-01) |
| 2 | Catálogo de planes legible por la app del cliente | DaleVentas (o endpoint público APPYRA) | **Falta** |
| 3 | Orden + comprobante + activación | DaleVentas | **Falta** (H-06) |
| 4 | Aviso al administrador con la imagen | CRM (ya tiene Cloud API) | Reutilizable |
| 5 | Recordatorios 5 y 1 día al cliente | Por decidir | Falta |
| 6 | Cerrar autoservicio | DaleVentas | **Falta** (H-02) |
| 7 | Acceso del vencido a Planes | DaleVentas + Flutter | **Falta** (H-03) |
| 8 | Alinear plan 4 y precios | APPYRA + web | **Falta** (H-04, H-05) |

## 7. Recomendación revisada

1. **No duplicar nada**: planes y overrides se quedan en APPYRA.
2. **Arreglar H-01 primero**: añadir a `/api/service/daleventas` las rutas `POST /licenses/:id/commands`
   y `GET /licenses/:id/activity`, que reenvíen al puente de DaleVentas. Con eso los botones que ya
   existen en el CRM **empiezan a funcionar** sin tocar la interfaz.
3. **Órdenes y comprobantes en DaleVentas** (es la única base que puede guardarlos junto a la empresa).
4. **El aviso con la imagen sale del CRM** (ya tiene Cloud API y plantillas); DaleVentas solo notifica
   “comprobante recibido” por un canal interno.
5. **Cerrar el autoservicio** y**permitir el login del vencido** en DaleVentas.
6. **Unificar el catálogo**: 4 planes y precios de la web en APPYRA, y la web como espejo.

## 8. Decisiones que necesito

| # | Decisión |
| --- | --- |
| D-1 | ¿Se añaden `ENTERPRISE` y los precios de la web (2.000/3.000/4.500) a APPYRA? |
| D-2 | ¿Implemento los comandos que faltan en APPYRA (H-01) como primera tarea? |
| D-3 | ¿El WhatsApp sale del CRM (Cloud API ya listo) o de DaleVentas? |
| D-4 | ¿Se retira el código PayPal o se deja como está? |
| D-5 | ¿El catálogo de la app se lee de DaleVentas (copia) o de un endpoint público de APPYRA? |
