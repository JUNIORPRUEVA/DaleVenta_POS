#define MyAppExeName "fulltech_app.exe"
#define MyAppSourceDir "..\apps\fulltech_app\build\windows\x64\runner\Release"
#define BrandSetupIcon "..\apps\fulltech_app\windows\runner\resources\app_icon.ico"

[Setup]
AppId={{0ED49D5E-6E78-4F11-8E78-6D37FDE2078A}-SMOKE}
AppName=FullTech Smoke
AppVersion=1.0.0
DefaultDirName={tmp}\FullTechSmoke
DefaultGroupName=FullTechSmoke
OutputDir=output
OutputBaseFilename=smoke-fulltech-files
SetupIconFile={#BrandSetupIcon}
DisableProgramGroupPage=yes
Uninstallable=no

[Files]
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Excludes: "*.pdb,*.ilk,*.exp,*.lib"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\FullTech Smoke"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
