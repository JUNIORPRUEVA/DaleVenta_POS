# Release Windows

Esta carpeta empaqueta la aplicacion Windows con Inno Setup desde archivos del repositorio y prerequisitos documentados.

## Que toma el instalador

- Nombre visible del producto: `FullPOS` (define `MyAppName`: accesos directos, Menu Inicio, Panel de control)
- Ejecutable: `fullpos_cloud.exe`
- Icono del setup: `apps/fulltech_app/windows/runner/resources/app_icon.ico`
- Release Flutter esperado: `apps/fulltech_app/build/windows/x64/runner/Release`
- Raiz oficial instalada: `C:\Program Files\DaleVentas POS` (define `MyAppFolderName`)
- Runtime Flutter instalado en: `C:\Program Files\DaleVentas POS\app`
- Datos locales preservados: `databases`, `backups`, `media_cache`, `logs`, `config`
- Redistributables opcionales: `installer/redist/VC_redist.x64.exe` y `installer/redist/MicrosoftEdgeWebView2RuntimeInstallerX64.exe`

### Por que el nombre visible y la carpeta difieren

El producto se muestra como `FullPOS`, pero la carpeta de instalacion sigue siendo
`C:\Program Files\DaleVentas POS`. Es intencional: el cliente resuelve la base de datos,
backups, `media_cache`, logs y config en `%ProgramFiles%\DaleVentas POS`
(ver `apps/fulltech_app/lib/core/storage/windows_product_paths.dart`). Renombrar la
carpeta dejaria sin acceso los datos de instalaciones existentes. Por la misma razon
el `AppId` del instalador no cambia: asi la actualizacion reemplaza la version previa
en el mismo directorio. `setup.iss` elimina ademas los accesos directos antiguos
(`DaleVentas POS`) para no dejar entradas huerfanas duplicadas.

### Iconos

Los iconos de aplicacion se generan con:

```powershell
python scripts\branding\generate_app_icons.py
```

Ese script produce el `.ico` multi-resolucion (16/24/32/48/64/128/256) usado por el
ejecutable, el acceso directo y este instalador, ademas del maestro cuadrado
(`apps/fulltech_app/assets/image/logo_launcher.png`) que consume `flutter_launcher_icons`
para los iconos launcher de Android. No corras `flutter_launcher_icons` con
`windows.generate: true`: sobrescribiria el `.ico` con uno de una sola resolucion.

`installer/redist/` esta ignorado por git para no versionar binarios de terceros. Si esos instaladores estan presentes se incluyen y se ejecutan de forma silenciosa; si no estan presentes, el instalador se genera sin ellos.

## Redistributables

- `VC_redist.x64.exe`: Microsoft Visual C++ Redistributable x64. Usar solo el instalador oficial de Microsoft.
- `MicrosoftEdgeWebView2RuntimeInstallerX64.exe`: Microsoft Edge WebView2 Evergreen Runtime. Usar solo el instalador oficial de Microsoft.

No copies binarios desde carpetas historicas de otra maquina/proyecto. Descargalos desde Microsoft cuando se decida empaquetarlos y valida licencia/hash antes de publicar.

## Generar el setup

```powershell
.\scripts\release\build_windows_release.ps1
```

Despues compila el instalador desde `installer`:

```powershell
Set-Location ..\..\installer
.\find_and_build_inno.ps1 -Version '1.0.3+120' -VersionInfo '1.0.3.120'
```

Tambien puedes llamar directamente a Inno Setup si ya conoces la ruta de `ISCC.exe`:

```powershell
& "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe" .\setup.iss /DMyAppVersion=1.0.3+120 /DMyAppVersionInfo=1.0.3.120
```

El ejecutable final queda en `installer/output/FullPOS-Setup-<version>.exe`.

Si quieres forzar otra version puntual:

```powershell
.\find_and_build_inno.ps1 -Version '1.2.0+5' -VersionInfo '1.2.0.5'
```

## Overrides opcionales en setup.iss

`setup.iss` acepta estos defines opcionales:

- `MyAppName` (nombre visible; por defecto `FullPOS`)
- `MyAppFolderName` (carpeta de instalacion; por defecto `DaleVentas POS`)
- `MyAppPublisher`
- `MyAppPublisherURL`
- `MyAppSupportURL`
- `SupportLabel`
- `MyAppLicenseFile`
- `BrandWizardImage`
- `BrandWizardSmallImage`
