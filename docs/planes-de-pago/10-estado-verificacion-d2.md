# Estado de verificación — D-2 (H-01) rutas de comando y actividad

Fecha: 2026-11-16 · Rama: `agent/planes-de-pago-impl-20261116` (worktree `C:\src\fullpos-planes-de-pago-impl`)

## Qué se implementó

Hallazgo H-01 de `09-auditoria-completa.md`: los botones del CRM llamaban a
`POST /api/service/daleventas/licenses/:id/commands`, una ruta que **no existía** en el backend de
licencias (sólo había 8 GET). Cualquier edición, suspensión, reactivación o revocación desde el CRM
fallaba.

Implementado en `FULLTECHPOS_BAKEND_LICENCIA` (no en DaleVentas):

| Elemento | Archivo | Detalle |
| --- | --- | --- |
| `GET /licenses/:id/activity` | `backend/routes/serviceDaleventasRoutes.js` | scope `licenses:read`; delega en la ruta interna `/license/integrations/crm/companies/:id` y mapea a `{action, reason, at}` |
| `POST /licenses/:id/commands` | `backend/routes/serviceDaleventasRoutes.js` | scope `licenses:write`; valida UUID, forma del cuerpo, acción, `actorId` (`/^usr_[a-f0-9]{24}$/`), `serviceId`; reenvía a `/license/integrations/crm/:id/commands` |
| Traducción de errores | `backend/routes/serviceDaleventasRoutes.js` | 400/403/404/409/422 pasan con mensaje de negocio; cualquier otro se convierte en 502 seguro (sin filtrar detalles internos) |
| `capabilities.licenseWrite` | `backend/routes/serviceDaleventasRoutes.js` | se deriva de `hasAllScopes(req.service, ['licenses:write'])` |

Las **reglas de negocio siguen viviendo en DaleVentas** (`crm-license.service.ts`): idempotencia por
`operationId`, control de versión por `expectedVersion`, lista blanca de campos y confirmación por
nombre de empresa para revocar. APPYRA sólo transporta y autoriza.

## Qué se probó (ejecutado)

```powershell
cd C:\Users\pc\DEV\PROYECTOS\PRODUCTOS\CARPETA FULLPOS\FULLTECHPOS_BAKEND_LICENCIA
node --test tests/service-daleventas-read.test.js   # 28 tests pass, 0 fail
npm test                                            # 95 tests pass, 0 fail
```

Cobertura añadida (10 casos): reenvío correcto del comando, rechazo sin scope `licenses:write`,
validación de transporte (UUID, acción, actor, confirmación), mapeo de conflicto 409, confirmación de
revocación, `operation_id_reused`, ausencia de fugas de datos internos, excepción del puente → 502,
actividad e incoherencia de empresa.

En DaleVentas (worktree de implementación):

```powershell
cd C:\src\fullpos-planes-de-pago-impl\apps\api
npx prisma validate     # OK
npx prisma generate     # OK
npm test                # 2887 tests, 0 fallos
npx tsc --noEmit        # 0 errores
jest license-plans      # 4/4
```

## Qué NO se probó y por qué

**Prueba E2E desde la interfaz real del CRM: NO EJECUTADA (BLOQUEADA).**

Motivo concreto:

1. El `.env` del backend de licencias apunta a **producción**:
   `DALEVENTAS_LICENSE_API_BASE_URL=https://fullpos-backend-fullpos-backend.onqyr1.easypanel.host` y
   `DATABASE_URL` a un host interno de Docker. Arrancarlo tal cual escribiría en producción.
2. El stack local necesita tres servicios a la vez (licencias, API de DaleVentas y CRM web) más dos
   bases. Hoy hay bases de prueba disponibles
   (`crm-license-management-fixture-20261114` → 169 tablas; `fullpos_license_fiscal_pg_20261115` →
   `fullpos_ecf_ephemeral_test`, 170 tablas y 538 empresas), pero la API de DaleVentas no tiene build
   (`dist` inexistente) y requiere variables obligatorias de arranque.

Consecuencia: **no está verificado** que el cambio se vea en el CRM y en FullPOS, ni que la interfaz
muestre el error cuando el servidor rechaza la orden. Lo verificado es la ruta y su contrato, no la
pantalla.

## Guion para ejecutar el E2E cuando se autorice

1. Postgres aislado para licencias (el fixture de 55519) y otro para DaleVentas.
2. Arrancar DaleVentas desde `fullpos-planes-de-pago-impl\apps\api`:
   `DATABASE_URL` local, `LICENSE_ADMIN_SECRET` de pruebas, `PORT=4099`, `npm run build && npm start`.
3. Arrancar el backend de licencias **con variables de entorno que sobrescriban el `.env`**:
   `DATABASE_URL` local y `DALEVENTAS_LICENSE_API_BASE_URL=http://127.0.0.1:4099`.
4. Sembrar empresa y licencia ficticias, arrancar el backend del CRM y el Flutter web.
5. Ejecutar: editar un dato permitido → suspender → reactivar → revocar, comprobando el efecto en ambos
   lados, el rechazo de un operador sin permiso y el mensaje de error en la interfaz.

## Pendientes (sin autorizar)

- D-1: precios y `ENTERPRISE` de la web frente al catálogo de APPYRA (1.000/2.500/3.500/5.000).
- D-3: emisor de los avisos de WhatsApp.
- D-4: retirar el código de PayPal.
- D-5: catálogo duplicado en DaleVentas (Etapa 1, en revisión) o endpoint público de APPYRA.
- La migración `20261116180000_license_plans_and_orders` **no se ha aplicado** en ninguna base y el
  seed del catálogo **no se ha ejecutado**.
