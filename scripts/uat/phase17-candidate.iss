; Laboratory installer only. No commercial AppId, registry, uninstall or data delete.
#define Bank "C:\src\fullpos-offline-safe-48h\.uat\phase17-update-final-bank"
[Setup]
AppId=FullPOS-Phase17-UAT-Only
AppName=FullPOS Phase17 Candidate UAT
AppVersion=1.0.6.17002
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
OutputBaseFilename=FullPOS-Phase17-Candidate-17002
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
