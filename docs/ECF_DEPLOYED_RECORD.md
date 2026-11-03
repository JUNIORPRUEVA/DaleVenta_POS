# Registro del despliegue e-CF en producción (2026-11-03)

Estado: **desplegado y verificado**. Este documento fija qué se publicó
exactamente, para que una implementación posterior no lo sobrescriba por error.

---

## 1. Qué está corriendo en producción

| Elemento | Valor |
| --- | --- |
| Servicio | `daleventapos_backend` (Docker Swarm, proyecto EasyPanel `daleventapos`) |
| Imagen | `daleventapos-prod-api:1.0.7-ecf-pilot` |
| Imagen anterior (rollback) | `daleventapos-prod-api:pre-ecf-20261103-132814` |
| Backup previo | `/root/daleventa-pre-ecf-20261103-132756.dump` (7.168.686 B, 1.311 entradas verificadas) |
| Migraciones | 25 aplicadas · total 208 · 0 fallidas |
| Portal | `https://fullposcloud.fulltechrd.com/ecf/certificacion/` (archivo estático dentro de `daleventapos_pwa`) |
| Piloto | `ECF_PORTAL_PILOT_COMPANY_IDS=165e3fca-6225-479b-8805-d2205f10536c` |
| e-CF | `ecf_company_configurations.enabled = true` → **0 empresas** |

### Prueba de que la imagen desplegada es la construida

El ID de imagen difiere entre local y servidor porque el builder de Docker
Desktop añade manifiestos de attestation y `save`/`load` recompone el config.
La comprobación válida es el contenido:

```
sha256 compilado dentro de la imagen (local y servidor, idéntico):
  47efdde4…71cf  /app/dist/ecf/portal/ecf-certification-portal.service.js
  8a9c001e…9157  /app/dist/ecf/portal/ecf-certification-portal.controller.js
```

---

## 2. Por qué el despliegue fue manual

`feature/ecf-alanube` en GitHub apunta a `6947676f`, pero el trabajo validado
estaba en local (`95e33c86` + cambios sin commit). EasyPanel construye desde el
archivo de un commit de GitHub: desplegar desde ahí habría publicado la versión
**sin** e-CF.

Por eso la imagen se construyó en local y se transfirió (`docker save` →
`scp` → `docker load`), y el servicio se actualizó con:

```bash
docker service update \
  --image daleventapos-prod-api:1.0.7-ecf-pilot \
  --force --update-order start-first --update-failure-action rollback \
  --detach daleventapos_backend
```

**Consecuencia importante:** mientras el código no esté en `production-main`,
pulsar «Implementar» en EasyPanel **revertiría** el backend a la versión anterior
(sin e-CF, sin portal). El esquema nuevo es compatible hacia atrás, así que la
app seguiría funcionando, pero el portal dejaría de tener API.

---

## 3. Consolidación pendiente (requiere autorización)

Para que el estado deje de depender de una imagen transferida a mano:

1. Revisar el diff completo contra `production-main` (533 archivos, 264 en
   `api/ecf`, 52 en `app/ecf`, 25 migraciones, 81 documentos).
2. Publicar la rama y abrir el cambio hacia `production-main` (hoy **no** hecho).
3. Configurar en EasyPanel, para el servicio de backend, la variable
   `ECF_PORTAL_PILOT_COMPANY_IDS` (si no, el portal queda cerrado: es el valor
   por defecto seguro).
4. Dejar que EasyPanel construya desde ese commit y verificar imagen + `/health`.
5. Solo entonces retirar la imagen manual y el tag de rollback.

Mientras no se haga, el estado actual es estable pero **manual**.

---

## 4. Reversión (1 minuto, sin pérdida de datos)

```bash
# Backend a la versión anterior
docker service update --image daleventapos-prod-api:pre-ecf-20261103-132814 \
  --force daleventapos_backend

# Cerrar el portal del piloto (instantáneo)
docker service update --env-rm ECF_PORTAL_PILOT_COMPANY_IDS --force daleventapos_backend

# Retirar la página del portal
docker exec <daleventapos_pwa> rm -rf /usr/share/nginx/html/ecf
```

Las 25 migraciones **no** se revierten: son aditivas (tablas nuevas + una columna
nullable) y el código anterior las ignora. Restaurar el backup solo tendría
sentido si se hubiera corrompido algo, y entonces se restauraría completo.

---

## 5. Verificación posterior al despliegue

```
/health ................................. 200
/ecf/certification-portal/context ....... 401 (sin sesión)
/ecf/dosa/certification-intent .......... 401
PWA (dominio oficial) ................... 200
login con datos inválidos ............... 400 (ruta viva, sin 5xx)
5xx en 10 minutos ....................... 0
portal /ecf/certificacion/ .............. 200 · sin ticket muestra «Falta el enlace»
```
