; Real UAT candidate files; no commercial AppId, shortcuts or mutable-data delete.
#define BenchRoot "C:\src\fullpos-offline-safe-48h\.uat\phase13-update-bench"
#define TargetRoot BenchRoot + "\phase11-flutter-client-update"

[Setup]
AppId=FullPOS-OfflineSafe-Phase13-UAT-Only
AppName=FullPOS Phase13 UAT Bench
AppVersion=1.0.6
DefaultDirName={#TargetRoot}
UsePreviousAppDir=no
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
Uninstallable=no
CreateUninstallRegKey=no
CloseApplications=no
RestartApplications=no
OutputDir={#BenchRoot}\packages
OutputBaseFilename=FullPOS-Phase13-UAT-Candidate
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Files]
Source: "{#BenchRoot}\version-b-final\release\*"; DestDir: "{app}\app"; Flags: ignoreversion recursesubdirs createallsubdirs

[Code]
function InitializeSetup(): Boolean;
begin
  Result := CompareText(ExpandConstant('{param:DIR|{#TargetRoot}}'), '{#TargetRoot}') = 0;
end;

var PausedOnce: Boolean;

procedure CurInstallProgressChanged(CurProgress, MaxProgress: Integer);
begin
  if (not PausedOnce) and (CurProgress > 0) and (ExpandConstant('{param:PHASE13PAUSE|0}') = '1') then
  begin
    PausedOnce := True;
    SaveStringToFile('{#BenchRoot}\phase13-interrupted.marker', 'UAT fixture paused during file replacement', False);
    Sleep(30000);
  end;
end;
