param(
  [string]$Version = '1.0.3+120',
  [string]$VersionInfo = '1.0.3.120',
  [string]$SourceDir = '..\apps\fulltech_app\build\windows\x64\runner\Release'
)

$ErrorActionPreference = 'Stop'

$installerDir = $PSScriptRoot
$setupScript = Join-Path $installerDir 'setup.iss'
$outputExe = Join-Path $installerDir ('output\FullPOS-Cloud-Setup-' + ($Version -replace '\+', '-') + '.exe')
$reportPath = Join-Path $installerDir 'inno-build-report.txt'

function Find-IsccPath {
  $candidates = [System.Collections.Generic.List[string]]::new()

  foreach ($path in @(
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 5\ISCC.exe',
    'C:\Program Files (x86)\Inno Setup 5\ISCC.exe',
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
  )) {
    if (Test-Path -LiteralPath $path) { $candidates.Add($path) }
  }

  foreach ($root in @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
  )) {
    Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
      try {
        $item = Get-ItemProperty $_.PSPath -ErrorAction Stop
        if (($item.DisplayName -as [string]) -like '*Inno Setup*') {
          foreach ($possible in @($item.InstallLocation, (Split-Path ($item.DisplayIcon -as [string]) -Parent))) {
            if ($possible) {
              $iscc = Join-Path $possible 'ISCC.exe'
              if (Test-Path -LiteralPath $iscc) { $candidates.Add($iscc) }
            }
          }
        }
      } catch {}
    }
  }

  foreach ($dir in @('C:\Program Files', 'C:\Program Files (x86)')) {
    Get-ChildItem $dir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'Inno Setup*' } | ForEach-Object {
      $iscc = Join-Path $_.FullName 'ISCC.exe'
      if (Test-Path -LiteralPath $iscc) { $candidates.Add($iscc) }
    }
  }

  return $candidates | Select-Object -Unique | Select-Object -First 1
}

Set-Location $installerDir
$isccPath = Find-IsccPath

if (-not $isccPath) {
  @(
    'RESULT=ISCC_NOT_FOUND',
    "SETUP_SCRIPT=$setupScript",
    "OUTPUT_EXE=$outputExe"
  ) | Set-Content -Path $reportPath -Encoding UTF8
  exit 2
}

$before = if (Test-Path $outputExe) { (Get-Item $outputExe).LastWriteTimeUtc.ToString('o') } else { '' }

& $isccPath $setupScript "/DMyAppVersion=$Version" "/DMyAppVersionInfo=$VersionInfo" "/DMyAppSourceDir=$SourceDir" *> $reportPath

$afterExists = Test-Path $outputExe
$after = if ($afterExists) { (Get-Item $outputExe).LastWriteTimeUtc.ToString('o') } else { '' }

Add-Content -Path $reportPath -Value "`nRESULT=OK"
Add-Content -Path $reportPath -Value "ISCC_PATH=$isccPath"
Add-Content -Path $reportPath -Value "OUTPUT_EXE=$outputExe"
Add-Content -Path $reportPath -Value "BEFORE_UTC=$before"
Add-Content -Path $reportPath -Value "AFTER_EXISTS=$afterExists"
Add-Content -Path $reportPath -Value "AFTER_UTC=$after"
