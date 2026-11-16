@echo off
REM WinCare Portable - Diseñado por DevPoderSEO
REM Herramienta local para Windows; el modulo de red no bloquea conexiones.
setlocal
cd /d "%~dp0"
if not exist "%~dp0WinCare.ps1" (
  echo ERROR: No se encontro WinCare.ps1 junto al iniciador.
  pause
  exit /b 1
)
if not exist "%~dp0NetworkAudit.ps1" (
  echo ADVERTENCIA: falta NetworkAudit.ps1. Seguridad de red no estara disponible.
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0WinCare.ps1"
if errorlevel 1 pause
endlocal
