; Nombre visible del producto (accesos directos, Menu Inicio, Panel de control).
#ifndef MyAppName
#define MyAppName "FullPOS"
#endif
; Carpeta de instalacion. Se mantiene "DaleVentas POS" por compatibilidad: el
; cliente resuelve la base de datos, backups, media_cache, logs y config en
; %ProgramFiles%\DaleVentas POS (ver lib/core/storage/windows_product_paths.dart).
#ifndef MyAppFolderName
#define MyAppFolderName "DaleVentas POS"
#endif
#ifndef MyAppPublisher
#define MyAppPublisher "FullPOS"
#endif
#ifndef MyAppPublisherURL
#define MyAppPublisherURL "https://daleventa-pos.local"
#endif
#ifndef MyAppSupportURL
#define MyAppSupportURL "https://daleventa-pos.local"
#endif
#ifndef MyAppExeName
#define MyAppExeName "fullpos_cloud.exe"
#endif
#ifndef MyAppVersion
#define MyAppVersion "1.0.0+1"
#endif
#ifndef MyAppVersionInfo
#define MyAppVersionInfo "1.0.0.1"
#endif

#ifndef MyAppSourceDir
#define MyAppSourceDir "..\apps\fulltech_app\build\windows\x64\runner\Release"
#endif
#define BrandSetupIcon "..\apps\fulltech_app\windows\runner\resources\app_icon.ico"
#define VcRedistPath "redist\VC_redist.x64.exe"
#define WebView2RedistPath "redist\MicrosoftEdgeWebView2RuntimeInstallerX64.exe"

[Setup]
AppId={{0ED49D5E-6E78-4F11-8E78-6D37FDE2078A}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
VersionInfoVersion={#MyAppVersionInfo}
VersionInfoProductVersion={#MyAppVersionInfo}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppPublisherURL}
AppSupportURL={#MyAppSupportURL}
DefaultDirName={autopf}\{#MyAppFolderName}
UsePreviousAppDir=no
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=output
OutputBaseFilename=FullPOS-Setup-{#StringChange(MyAppVersion, "+", "-")}
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
SetupIconFile={#BrandSetupIcon}
PrivilegesRequired=admin
UninstallDisplayIcon={app}\app\{#MyAppExeName}

[Dirs]
Name: "{app}\app"
Name: "{app}\databases"; Permissions: users-modify; Flags: uninsneveruninstall
Name: "{app}\backups"; Permissions: users-modify; Flags: uninsneveruninstall
Name: "{app}\media_cache"; Permissions: users-modify; Flags: uninsneveruninstall
Name: "{app}\logs"; Permissions: users-modify; Flags: uninsneveruninstall
Name: "{app}\config"; Permissions: users-modify; Flags: uninsneveruninstall

[Files]
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}\app"; Excludes: "*.pdb,*.ilk,*.exp,*.lib"; Flags: ignoreversion recursesubdirs createallsubdirs
#ifexist VcRedistPath
Source: "{#VcRedistPath}"; DestDir: "{tmp}"; Flags: deleteafterinstall
#endif
#ifexist WebView2RedistPath
Source: "{#WebView2RedistPath}"; DestDir: "{tmp}"; Flags: deleteafterinstall
#endif

[InstallDelete]
; El nombre visible cambio de "DaleVentas POS" a "FullPOS": al actualizar una
; instalacion previa se eliminan sus accesos directos para no dejar entradas
; huerfanas duplicadas en el Menu Inicio ni en el escritorio.
Type: filesandordirs; Name: "{commonprograms}\DaleVentas POS"
Type: files; Name: "{commondesktop}\DaleVentas POS.lnk"

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\app\{#MyAppExeName}"; WorkingDir: "{app}\app"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\app\{#MyAppExeName}"; WorkingDir: "{app}\app"; Tasks: desktopicon

[Registry]
Root: HKCR; Subkey: ".dvbackup"; ValueType: string; ValueName: ""; ValueData: "DaleVentasBackup"; Flags: uninsdeletevalue
Root: HKCR; Subkey: "DaleVentasBackup"; ValueType: string; ValueName: ""; ValueData: "FullPOS Backup"; Flags: uninsdeletekey
Root: HKCR; Subkey: "DaleVentasBackup\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\app\{#MyAppExeName},0"
Root: HKCR; Subkey: "DaleVentasBackup\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\app\{#MyAppExeName}"" ""%1"""

[Tasks]
Name: "desktopicon"; Description: "Crear icono en el escritorio"; GroupDescription: "Opciones adicionales:"; Flags: unchecked

[Run]
#ifexist VcRedistPath
Filename: "{tmp}\VC_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Instalando Microsoft Visual C++ Runtime..."; Flags: waituntilterminated
#endif
#ifexist WebView2RedistPath
Filename: "{tmp}\MicrosoftEdgeWebView2RuntimeInstallerX64.exe"; Parameters: "/silent /install"; StatusMsg: "Instalando Microsoft Edge WebView2 Runtime..."; Flags: waituntilterminated
#endif
Filename: "{app}\app\{#MyAppExeName}"; Description: "Abrir {#MyAppName}"; WorkingDir: "{app}\app"; Flags: nowait postinstall skipifsilent
