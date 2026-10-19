; File replacement laboratory only: no commercial AppId, elevation or data delete.
#ifndef Bank
#define Bank "C:\src\fullpos-offline-safe-48h\.uat\phase16-update-bank"
#endif
#ifndef CandidateVersion
#define CandidateVersion "1.0.6.14016"
#endif
[Setup]
AppId=FullPOS-Phase16-Recovery-UAT-Only
AppName=FullPOS Phase16 Recovery UAT
AppVersion={#CandidateVersion}
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
OutputBaseFilename=FullPOS-Phase16-Recovery-UAT
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
[Files]
Source: "{#Bank}\candidate\*"; DestDir: "{app}\app"; Flags: ignoreversion recursesubdirs createallsubdirs
[Code]
procedure PauseAt(Stage: String);
begin
  if ExpandConstant('{param:PAUSEAT|none}') = Stage then
  begin
    SaveStringToFile('{#Bank}\pause-' + Stage + '.marker', Stage, False);
    Sleep(30000);
  end;
end;
function InitializeSetup(): Boolean;
begin
  Result := CompareText(ExpandConstant('{param:DIR|{#Bank}}'), '{#Bank}') = 0;
  if Result then PauseAt('before');
end;
var PausedOnce: Boolean;
procedure CurInstallProgressChanged(CurProgress, MaxProgress: Integer);
begin
  if (not PausedOnce) and (CurProgress > 0) then
  begin
    PausedOnce := True;
    PauseAt('during');
  end;
end;
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then PauseAt('after');
end;
