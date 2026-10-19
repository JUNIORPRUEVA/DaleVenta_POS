; Isolated executable probe A -> B. No commercial identity, elevation or user data cleanup.
#define Bank "C:\src\fullpos-offline-safe-48h\.uat\phase14-native-bank"
[Setup]
AppId=FullPOS-Phase14-Native-UAT-Only
AppName=FullPOS Phase14 Native UAT
AppVersion=1.0.6.14002
DefaultDirName={#Bank}
UsePreviousAppDir=no
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
Uninstallable=no
CreateUninstallRegKey=no
CloseApplications=no
RestartApplications=no
OutputDir={#Bank}\packages
OutputBaseFilename=FullPOS-Phase14-Native-UAT-B
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
[Files]
Source: "{#Bank}\version-b\*"; DestDir: "{app}\app"; Flags: ignoreversion recursesubdirs createallsubdirs
[Code]
function InitializeSetup(): Boolean;
begin
  Result := CompareText(ExpandConstant('{param:DIR|{#Bank}}'), '{#Bank}') = 0;
end;
var PausedOnce: Boolean;
procedure CurInstallProgressChanged(CurProgress, MaxProgress: Integer);
begin
  if (not PausedOnce) and (CurProgress > 0) and (ExpandConstant('{param:PHASE14PAUSE|0}') = '1') then
  begin
    PausedOnce := True;
    SaveStringToFile('{#Bank}\interrupted.marker', 'Isolated fixture paused during file replacement', False);
    Sleep(30000);
  end;
end;
