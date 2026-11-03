# Consolidación en EasyPanel y publicación de la PWA

Estado: **procedimiento preparado, nada ejecutado**. Requiere autorización.

Contexto: el backend e-CF está en producción por una imagen transferida a mano
(`daleventapos-prod-api:1.0.7-ecf-pilot`). EasyPanel sigue apuntando a
`production-main`, que **no** contiene e-CF.

> **Actualización 2026-11-03 (integración lista, sin publicar).** La integración
> existe ya en la rama local `integration/ecf-into-production` sobre
> `origin/production-main` @ `144bf519`, en dos commits: `da409ea4` (merge con
> los 20 conflictos resueltos a mano) y `27072ac8` (portal dentro de la imagen y
> arreglo del build web). El portal ya **no** se copia a mano: vive en
> `apps/fulltech_app/web/ecf/certificacion/index.html`, entra en la imagen Web
> mediante `flutter build web` y el `Dockerfile` rellena
> `__DOSA_PUBLISHABLE_KEY__` / `__API_BASE__` desde los **Build Args** de
> EasyPanel (`DOSA_ASSISTANT_PUBLISHABLE_KEY`, `ECF_PORTAL_API_BASE`). Si la
> clave falta, el build de la PWA falla a propósito.
> Nada se ha publicado ni desplegado: el push a `production-main` y el botón
> «Implementar» siguen siendo decisiones del responsable.


---

## 1. Qué debe pasar para que EasyPanel conserve esta versión

| # | Paso | Quién | Efecto si se omite |
| --- | --- | --- | --- |
| 1 | Publicar la rama `feature/ecf-alanube` y abrir el cambio hacia `production-main` | responsable | EasyPanel no tiene de dónde construir e-CF |
| 2 | Revisar el diff antes de fusionar (§2) | responsable | riesgo de arrastrar cambios no deseados |
| 3 | Fusionar a `production-main` | responsable | — |
| 4 | En EasyPanel, fijar la variable `ECF_PORTAL_PILOT_COMPANY_IDS=165e3fca-6225-479b-8805-d2205f10536c` en el servicio de backend | responsable | un redespliegue dejaría el portal **cerrado** (seguro, pero inútil) |
| 5 | Pulsar «Implementar» y verificar (§4) | responsable | — |

**Importante:** hoy la variable vive solo en el *spec* del servicio de Swarm
(puesta con `docker service update`). EasyPanel reescribe ese spec cuando
despliega: si la variable no está también en su plantilla/UI, el redespliegue la
elimina. Debe configurarse **en EasyPanel**, no solo por CLI.

Mientras no se complete el paso 3, **no pulsar «Implementar»**: revertiría el
backend a la versión sin e-CF (la app seguiría funcionando porque el esquema es
compatible hacia atrás, pero el portal se quedaría sin API).

---

## 2. Qué revisar antes de fusionar (resumen del diff)

Tomado de `git merge-base production-main HEAD` hasta `HEAD`:

| Área | Archivos |
| --- | --- |
| `apps/api/src/ecf/**` | 264 (módulo e-CF completo, incluido `portal/**`) |
| `apps/api/prisma/**` | 25 migraciones + `schema.prisma` |
| `apps/fulltech_app/lib/features/ecf/**` | 52 |
| `apps/fulltech_app/lib/core/**` | rutas, permisos, navegación, api client |
| Fuera de e-CF | `sales.service.ts` (+13), `settings.service.ts` (+37), `app.module.ts`, `main.ts`, `common/redact-secrets.ts`, `common/uat-safety.ts` |
| Documentación | 81 archivos en `docs/` |
| Scripts | `scripts/isolated-uat/**`, `scripts/dev/**`, `scripts/ops/**` |

Los cambios fuera de `ecf/` están revisados uno a uno y son **aditivos**
(snapshot fiscal en la venta, campo nuevo en la respuesta de ajustes, entradas de
UI que se ocultan solas). El detalle está en `docs/ECF_PRODUCTION_DEPLOYMENT_PLAN.md` §3.

**No volver a ejecutar las 25 migraciones**: ya están aplicadas en producción
(208 vigentes, 0 fallidas). `prisma migrate deploy` las vería como hechas.

---

## 3. Publicación de la PWA (solo si se autoriza)

La PWA también se construye desde GitHub, así que requiere los pasos 1-3.

Antes de publicar, el build debe llevar la bandera del asistente (si no, la
sección no aparece):

```powershell
pwsh -File scripts/dev/build_web_dosa_assistant.ps1 -ApiBaseUrl /api
```

Efecto sobre los demás clientes: **ninguno visible**.

- La entrada «Facturación electrónica» solo aparece si `ecfEnabled` **o** si el
  backend responde `eligible: true` para esa empresa (piloto).
- Sin piloto y sin e-CF: el menú queda exactamente como hoy.
- El botón del portal exige además permiso `manageEcfOnboarding`.

**Procedimiento de publicación (una vez fusionado):**

1. Desplegar la PWA como cualquier release (`docs/RELEASE.md`).
2. Verificar: la app carga, el menú de un cliente normal no cambia, el
   administrador del piloto ve la entrada.
3. Comprobar el portal: Configuración → Facturación electrónica →
   «Iniciar o continuar certificación» → se abre la pestaña del dominio oficial.

**Reversión:** volver a la imagen anterior de la PWA por tag (mismo
procedimiento que cualquier release). El portal estático sigue publicado y no
depende de la PWA; si se quiere cerrar del todo:

```bash
docker service update --env-rm ECF_PORTAL_PILOT_COMPANY_IDS --force daleventapos_backend
docker exec <daleventapos_pwa> rm -rf /usr/share/nginx/html/ecf
```

---

## 4. Verificación posterior al redespliegue de EasyPanel

```
/health ................................. 200
/ecf/certification-portal/eligibility ... 401 sin sesión (ruta viva)
/ecf/certification-portal/context ....... 401 sin sesión
imagen del servicio ..................... la construida por EasyPanel con e-CF
ECF_PORTAL_PILOT_COMPANY_IDS ............ presente en el servicio
```

Si `eligibility` respondiera 404, significa que el servicio volvió a la imagen
anterior: no es un fallo de datos, solo falta el despliegue correcto.

---

## 5. Prueba de acceso real (la ejecuta el responsable)

```powershell
$env:FULLPOS_SMOKE_EMAIL    = 'cuenta admin de FULLTECH SRL'
$env:FULLPOS_SMOKE_PASSWORD = '...'      # no se escribe en el chat
pwsh -File scripts/ops/dosa-portal-smoke.ps1
```

Comprueba login, ticket, canje, identidad (debe coincidir con
`165e3fca-6225-479b-8805-d2205f10536c`), `ecfEnabled=false` y el cierre de
sesión. No imprime credenciales, tickets ni sesiones.

Después, en el navegador: abrir el portal y confirmar que aparece el asistente
DOSA y el evento `cert:ready`. Eso crea una **sesión técnica** del proveedor, que
no es una postulación DGII.
