# Release Windows

Esta carpeta empaqueta la aplicacion Windows con Inno Setup desde archivos del repositorio y prerequisitos documentados.

## Que toma el instalador

- Nombre del producto: `FullPOS Cloud`
- Ejecutable: `fullpos_cloud.exe`
- Icono del setup: `apps/fulltech_app/windows/runner/resources/app_icon.ico`
- Release Flutter esperado: `apps/fulltech_app/build/windows/x64/runner/Release`
- Redistributables opcionales: `installer/redist/VC_redist.x64.exe` y `installer/redist/MicrosoftEdgeWebView2RuntimeInstallerX64.exe`

`installer/redist/` esta ignorado por git para no versionar binarios de terceros. Si esos instaladores estan presentes se incluyen y se ejecutan de forma silenciosa; si no estan presentes, el instalador se genera sin ellos.

## Redistributables

- `VC_redist.x64.exe`: Microsoft Visual C++ Redistributable x64. Usar solo el instalador oficial de Microsoft.
- `MicrosoftEdgeWebView2RuntimeInstallerX64.exe`: Microsoft Edge WebView2 Evergreen Runtime. Usar solo el instalador oficial de Microsoft.

No copies binarios desde carpetas historicas de otra maquina/proyecto. Descargalos desde Microsoft cuando se decida empaquetarlos y valida licencia/hash antes de publicar.

## Generar el setup

```powershell
Set-Location .\apps\fulltech_app
flutter build windows --release --dart-define=API_BASE_URL=https://daleventapos-backend.gcdndd.easypanel.host
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

El ejecutable final queda en `installer/output/FullPOS-Cloud-Setup-<version>.exe`.

Si quieres forzar otra version puntual:

```powershell
.\find_and_build_inno.ps1 -Version '1.2.0+5' -VersionInfo '1.2.0.5'
```

## Overrides opcionales en setup.iss

`setup.iss` acepta estos defines opcionales:

- `MyAppPublisher`
- `MyAppPublisherURL`
- `MyAppSupportURL`
- `SupportLabel`
- `MyAppLicenseFile`
- `BrandWizardImage`
- `BrandWizardSmallImage`
