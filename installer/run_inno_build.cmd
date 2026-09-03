@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_inno_build.ps1" -ScriptName "setup.iss" -LogName "inno-build-report.txt" %*
