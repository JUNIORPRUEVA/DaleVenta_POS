#ifndef MyAppName
#define MyAppName "DaleVenta POS"
#endif
#ifndef MyAppPublisher
#define MyAppPublisher "DaleVenta POS"
#endif
#ifndef MyAppPublisherURL
#define MyAppPublisherURL "https://daleventa-pos.local"
#endif
#ifndef MyAppSupportURL
#define MyAppSupportURL "https://daleventa-pos.local"
#endif
#ifndef MyAppExeName
#define MyAppExeName "daleventa_pos.exe"
#endif
#ifndef MyAppVersion
#define MyAppVersion "1.0.0+1"
#endif
#ifndef MyAppVersionInfo
#define MyAppVersionInfo "1.0.0.1"
#endif

#define MyAppSourceDir "..\apps\fulltech_app\build\windows\x64\runner\Release"
#define BrandSetupIcon "..\apps\fulltech_app\windows\runner\resources\app_icon.ico"

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
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=output
OutputBaseFilename=DaleVenta-POS-Setup-{#StringChange(MyAppVersion, "+", "-")}
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
SetupIconFile={#BrandSetupIcon}
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#MyAppExeName}

[Files]
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Excludes: "*.pdb,*.ilk,*.exp,*.lib"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "redist\VC_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "redist\MicrosoftEdgeWebView2RuntimeInstallerX64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Crear icono en el escritorio"; GroupDescription: "Opciones adicionales:"; Flags: unchecked

[Run]
Filename: "{tmp}\VC_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Instalando Microsoft Visual C++ Runtime..."; Flags: waituntilterminated
Filename: "{tmp}\MicrosoftEdgeWebView2RuntimeInstallerX64.exe"; Parameters: "/silent /install"; StatusMsg: "Instalando Microsoft Edge WebView2 Runtime..."; Flags: waituntilterminated
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir {#MyAppName}"; Flags: nowait postinstall skipifsilent
