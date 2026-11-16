@echo off
REM WinCare Portable v2.1 - Diseñado por DevPoderSEO
REM Generar paquete desde una copia completa del repositorio en Windows.
setlocal
cd /d "%~dp0"
if not exist "%~dp0packaging\CrearPaquete.ps1" (
  echo ERROR: falta packaging\CrearPaquete.ps1. Descarga el repositorio completo.
  pause
  exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0packaging\CrearPaquete.ps1" -DestinationDirectory "%~dp0dist"
set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" (
  echo ERROR: No se pudo construir el ZIP. Revisa los mensajes de arriba.
) else (
  echo ZIP creado en dist\WinCarePortable-v2.1.zip
  echo Comprueba el ZIP y prueba VALIDAR_WINCARE.bat antes de usarlo con clientes.
)
pause
exit /b %CODE%
