# Imágenes FullPOS preparadas para despliegue manual

Estado: imágenes publicadas y validadas; cambio de fuente en EasyPanel pendiente
de autorización expresa. No se ejecutó deploy.

## Identidad y evidencia

- Código de aplicación: merge `8fa5eba6cc2f4b7a7be6f51c3ff8d576b15c937c`, PR41.
- Los cuatro controles posteriores al merge pasaron en
  [43549300137](https://github.com/JUNIORPRUEVA/DaleVenta_POS/actions/runs/43549300137).
- Construcción/publicación externa al servidor productivo: GitHub Actions
  [43552244402](https://github.com/JUNIORPRUEVA/DaleVenta_POS/actions/runs/43552244402),
  dos jobs aprobados. El workflow se publicó en la rama aislada
  `agent/ecf-release-preparation-8fa5eba6`, commit `9026faeb`.
- La aplicación se obtiene del merge aprobado, no del HEAD cambiante de esa rama.
  La preparación no añade código de negocio a `production-main`.
- Plataforma comprobada: `linux/amd64`. No se usa una etiqueta `latest`.

## Referencias exactas para EasyPanel

Backend, fuente **Docker Image**:

```text
ghcr.io/juniorprueva/fullpos-cloud-api@sha256:50e6e51217922b48eeefbea6addf34776dc0773e05fa937f5862baa62191e1f6
```

PWA, fuente **Docker Image**:

```text
ghcr.io/juniorprueva/fullpos-cloud-web@sha256:a4841b785239b602869b621ac424fa08d9667af561c3868cc4177a293d434177
```

Ambas imágenes se descargaron realmente por digest desde GHCR sin configurar
credenciales adicionales. No se cambió la visibilidad ni el acceso de paquetes.
Las referencias por digest conservan el contenido aunque cambie una etiqueta.

## Validaciones ejecutadas

| Comprobación | Resultado |
| --- | --- |
| YAML del workflow y sintaxis de sus dos scripts Node | PASS |
| Fuente congelada y CI post-merge, verificados por el workflow | PASS |
| Compilación/publicación de API y web | 2/2 PASS |
| Descarga real de ambos digests | PASS |
| API publicada, runtime Node22.23.4/Nest11/Prisma5.22 | PASS |
| API publicada sin `.env` raíz ni uploads de clientes en la imagen | PASS |
| Portal conserva su clave pública LIVE y destino aprobado | PASS; huella comprobada sin imprimir claves |
| `node website/tests/public-web-smoke.mjs` con imágenes publicadas | 8 grupos PASS;16 assets |
| Sintaxis PowerShell y Python del preflight actualizado | PASS |
| Preflight sin imágenes esperadas, fuente GitHub actual | Controles base PASS; exit2, permisos fiscales apagados |
| Preflight con ambos digests, antes de cambiar las fuentes | Bloqueo esperado exit1; las fuentes siguen siendo GitHub |

La aceptación de las imágenes usó únicamente contenedores locales propios,
PostgreSQL desechable y usuarios sintéticos. Se probó salud y proxy, registro,
duplicados, login, aislamiento de empresa, handoff concurrente de un solo uso,
onboarding, Astro/Brotli, POS/PWA y rutas del portal/webhook/uploads.
Las migraciones de esa base nueva se ejecutaron únicamente para el ensayo local.

La primera prueba conjunta no alcanzó el upstream porque UAT_LOCAL_ONLY=true
vincula la API a127.0.0.1 dentro de su contenedor. El ensayo final utilizó el modo
UAT de servidor en la red Docker local, sin cambiar imágenes ni aserciones.
Un puerto local ocupado se respetó y se usó un puerto libre asignado por Docker.

## Cambio propuesto y protección de producción

Solo después de autorización, cambiar la fuente de `daleventapos/backend` y
`daleventapos/pwa` desde GitHub a Docker Image, con los dos digests anteriores.
No pulsar Deploy al guardar esa preparación.

Conservar el entorno completo, RUN_MIGRATIONS=false, seed deshabilitado,
permisos fiscales globales apagados, montajes, puertos, dominios y ajustes de
despliegue. Sus huellas se registraron antes del cambio; deben coincidir después.
Los contenedores actuales deben mantener sus IDs e imágenes hasta que el
propietario ejecute el despliegue manual.

El preflight admite ambas fuentes: sin parámetros exige GitHub/production-main;
con `-ExpectedApiImage` y `-ExpectedPwaImage` exige coincidencia exacta de los dos
digests del namespace autorizado. No acepta una imagen arbitraria o `latest`.
Mantiene la comprobación de migraciones, salud, documentos sin ambiente y flags.
Exit1 indica fallo; exit2 indica controles base correctos con habilitación fiscal
global pendiente; exit0 indica también esos permisos preparados. Ninguno ejecuta
deploy ni autoriza una emisión. Se corrigió la propagación del código SSH para
conservar estos resultados en PowerShell7.

Ejecutar el verificador de esta rama con las referencias anteriores:

```powershell
./scripts/release/verify_ecf_server_predeploy.ps1 -ExpectedApiImage 'ghcr.io/juniorprueva/fullpos-cloud-api@sha256:50e6e51217922b48eeefbea6addf34776dc0773e05fa937f5862baa62191e1f6' -ExpectedPwaImage 'ghcr.io/juniorprueva/fullpos-cloud-web@sha256:a4841b785239b602869b621ac424fa08d9667af561c3868cc4177a293d434177'
```

## Orden manual y límites

1. Autorizar y guardar únicamente la preparación de fuentes.
2. Comprobar fuentes, huellas del entorno/montajes y contenedores sin reiniciar.
3. El propietario despliega primero backend; comprobar salud, revisión/Node22,
   sesión/contexto de empresa y funcionamiento ordinario antes de continuar.
4. El propietario despliega PWA después de validar la API compatible.
5. La habilitación y aceptación de emisión productiva es una operación separada.
   No se activaron sus permisos globales en esta preparación.

Mantener respaldos y el esquema aditivo. No ejecutar SQL manual otra vez, seed,
reset, db push, restauración de la base sobre ventas posteriores ni retroceso de
contadores. Una vez publicados clientes que envían NORMAL, conservar una API
compatible o corregir hacia adelante; el API anterior no conoce ese marcador.

Estas imágenes cubren API y web/PWA. Los ejecutables instalados de Windows,
Android o iOS requieren su propio canal de publicación; este trabajo no afirma
haber generado nuevos instaladores ni repetido pruebas físicas de impresión.

Evidencia privada local y propuesta revisable, sin valores del entorno productivo:
`C:/Users/pc/.codex/backups/fullpos-release-8fa5eba6-20261114/`.
Incluye recibos de publicación, prueba final y huellas de configuración protegida.
