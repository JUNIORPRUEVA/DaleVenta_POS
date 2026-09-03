#ifndef MyAppName
#define MyAppName "FullPOS Cloud"
#endif
#ifndef MyAppPublisher
#define MyAppPublisher "FullPOS Cloud"
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
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=output
OutputBaseFilename=FullPOS-Cloud-Setup-{#StringChange(MyAppVersion, "+", "-")}
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
#ifexist VcRedistPath
Source: "{#VcRedistPath}"; DestDir: "{tmp}"; Flags: deleteafterinstall
#endif
#ifexist WebView2RedistPath
Source: "{#WebView2RedistPath}"; DestDir: "{tmp}"; Flags: deleteafterinstall
#endif

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Crear icono en el escritorio"; GroupDescription: "Opciones adicionales:"; Flags: unchecked

[Run]
#ifexist VcRedistPath
Filename: "{tmp}\VC_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Instalando Microsoft Visual C++ Runtime..."; Flags: waituntilterminated
#endif
#ifexist WebView2RedistPath
Filename: "{tmp}\MicrosoftEdgeWebView2RuntimeInstallerX64.exe"; Parameters: "/silent /install"; StatusMsg: "Instalando Microsoft Edge WebView2 Runtime..."; Flags: waituntilterminated
#endif
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir {#MyAppName}"; Flags: nowait postinstall skipifsilent
