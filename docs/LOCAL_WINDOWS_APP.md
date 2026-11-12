# Aplicación Windows de desarrollo

La aplicación completa de este trabajo está en la rama `ultimos-trabajos`,
en `apps/fulltech_app`, dentro de este repositorio:

`C:/Users/pc/DEV/PROYECTOS/PRODUCTOS/finalesdaleventas`

`C:/b/finales` es una junction hacia ese mismo repositorio, utilizada para
evitar el límite de rutas de MSBuild. No es otra copia del código.

## Ejecutar la aplicación completa

Abrir `finalesdaleventas.code-workspace` y elegir el perfil
`FullPOS Windows - DEBUG (API local 127.0.0.1:4004)`.
Al abrir directamente la carpeta del repositorio, elegir
`FullPOS Windows — UAT Hot Reload (F5)`.

Ambos perfiles usan `lib/main.dart`, el backend local `127.0.0.1:4004`,
actualizaciones desactivadas y almacenamiento UAT en `C:/b/fp-uat-data`.
El backend local debe estar disponible para consultar o sincronizar datos;
la instalación comercial y sus datos no forman parte de esta ejecución.

Para ejecutar desde PowerShell:

```powershell
Set-Location C:/b/finales/apps/fulltech_app
$env:FULLPOS_WINDOWS_CHANNEL = 'uat-mayoreo'
$env:DALEVENTAS_POS_ROOT = 'C:/b/fp-uat-data'
$env:CL = '/FS'
flutter run -d windows --dart-define=APP_ENV=uat --dart-define=FULLPOS_UAT_PROFILE=true --dart-define=DISABLE_APP_UPDATES=true --dart-define=API_BASE_URL=http://127.0.0.1:4004 --dart-define=APP_BASE_URL=http://127.0.0.1:4004
```

Comprobar el proceso por su ruta de ejecutable, no solo por el título
`FullPOS`: distintas ejecuciones pueden compartir ese título.
El ejecutable de este perfil está en
`apps/fulltech_app/build/windows/x64/runner/Debug/fullpos_cloud_uat_mayoreo.exe`.

## Vistas previas y recuperación visual

`C:/b/fp-native-look` y `C:/b/fullpos-panel-qa-20261111` son copias aisladas
utilizadas para validación. No son la fuente de la aplicación completa.
Los archivos `presentation/preview/*` tampoco son el punto de entrada real.

El merge `4423c061` conservó los componentes visuales, pero quitó sus conexiones
de `cotizaciones_screen.dart`. Recompilar ese estado mostraba la interfaz
anterior. La recuperación combina las conexiones visuales de `4fd178d3` con
las capacidades y controles e-CF actuales, sin restaurar pantallas comerciales
retiradas por producción.

La prueba `billing_ecf_selector_visible_test.dart` verifica que la pantalla real
utiliza el buscador, la cabecera, el selector de cliente y los accesos nuevos,
además de mostrar el selector electrónico. Las pruebas aisladas de componentes
no bastan para detectar otra desconexión durante una integración.
