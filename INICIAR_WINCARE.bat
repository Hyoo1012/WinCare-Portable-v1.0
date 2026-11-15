@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0WinCare.ps1" (
  echo ERROR: No se encontro WinCare.ps1 junto a este archivo.
  pause
  exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0WinCare.ps1"
if errorlevel 1 pause
endlocal
