# Publicación y despliegue manual de e-CF

El código está publicado en el [PR41](https://github.com/JUNIORPRUEVA/DaleVenta_POS/pull/41)
hacia `production-main`. Commit de implementación: `50617f39`.
El propietario une los cambios y ejecuta el deploy. El agente no activa merge
automático, no despliega y no reinicia servicios.

## Antes de unir el PR

1. Revisar los cambios y esperar los cuatro controles de GitHub Actions:
   `api-security`, `public-website`, `flutter-regression` y `windows-updater`.
   Los controles corresponden al último commit del PR. Si alguno falla o sigue
   pendiente, no interpretar las pruebas locales como un PASS de CI.
2. Confirmar que el destino sigue siendo `production-main` y que el PR no tiene
   conflictos. Los commits quedan en Git; no hace falta volver a copiar archivos
   desde el checkout anterior ni repetir commits del trabajo ya publicado.
3. Mantener `autoDeploy=false` en los servicios backend y PWA. Unir el PR no debe
   iniciar el despliegue automáticamente.

## Preparar la configuración

Las migraciones fiscales ya están aplicadas y verificadas. No repetir SQL,
`db push`, reset, seed ni restaurar un respaldo sobre ventas posteriores.

En la configuración del backend en EasyPanel, preparar estos permisos antes de
emitir facturas productivas:

```dotenv
DOSA_PRODUCTION_EMISSION_ENABLED=true
DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED=true
RUN_MIGRATIONS=false
```

Conservar el seed deshabilitado, las credenciales, montajes y demás opciones
existentes. La clave pública del asistente DOSA ya está configurada en PWA;
no reemplazarla por la clave ficticia usada en las compilaciones locales.
Estos permisos globales no activan una empresa ni generan una factura por sí solos.

El verificador de solo lectura se ejecuta desde PowerShell7:

```powershell
./scripts/release/verify_ecf_server_predeploy.ps1
```

La clave SSH se utiliza por su ruta; el script no imprime su contenido.
Un resultado2 indica que los controles básicos pasaron pero falta preparar los
permisos productivos. Un resultado1 indica fallo de verificación. Solo0 indica
que los controles implementados por ese script pasaron; no sustituye CI ni la
aceptación del despliegue. No modificar el script para ignorar un bloqueo.

## Orden del despliegue

1. Unir el PR revisado y registrar el SHA final de `production-main`.
2. Construir artefactos inmutables fuera del servidor productivo, usando las
   entradas documentadas en [RELEASE](../RELEASE.md). Las imágenes locales
   etiquetadas `fullpos-ecf-*-review` contienen configuración de QA y no se publican.
3. Desplegar primero la API compatible. Verificar `/health`, login, contexto de
   empresa, venta Normal y preparación fiscal. Mantener las automigraciones
   deshabilitadas. No crear una venta fiscal real como prueba automática.
4. Desplegar después la PWA combinada, conservando el contexto raíz del repositorio
   y `Dockerfile.public-web`. Verificar acceso, rutas públicas, POS y asistente DOSA.
5. Cada empresa completa su certificación con el asistente existente, habilita
   producción explícitamente y registra sus propios rangos autorizados por DGII.
   No copiar credenciales, rangos ni contadores de FULLTECH a otros clientes.
6. Registrar salud, revisión desplegada y aceptación. Hasta contar con la API
   compatible, no iniciar nuevos ensayos con el código fiscal anterior.

La receta Git/Docker actual de EasyPanel puede compilar en el mismo host cuando
se pulsa Deploy. Este trabajo no ejecutó ni autorizó esa compilación productiva;
el procedimiento de release exige construir fuera de producción y desplegar el
artefacto resultante. Confirmar ese camino antes de pulsar el botón.

## Recuperación y trazabilidad

Conservar el esquema aditivo y los respaldos. Después de publicar clientes que
envían `NORMAL`, mantener una API compatible o corregir hacia adelante; no volver
a la API antigua sin analizar los clientes activos. No bajar contadores fiscales.

El [inventario de246 archivos](ECF_PREDEPLOY_FILES_2026-11-13.json) corresponde al
commit de implementación50617f39. Las actualizaciones posteriores de estado,
evidencia y esta guía pertenecen al checkpoint de publicación; no cambian el
código fiscal validado. La [auditoría](ECF_PREDEPLOY_AUDIT_2026-11-13.md) conserva
pruebas, respaldos, limitaciones y riesgos pendientes.
