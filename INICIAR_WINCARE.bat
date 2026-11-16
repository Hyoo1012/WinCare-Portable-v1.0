@echo off
REM WinCare Portable - Diseñado por DevPoderSEO
REM Herramienta local para Windows - DevPoderSEO. Limpieza solo con consentimiento.
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
if not exist "%~dp0HardwareAudit.ps1" (
  echo ADVERTENCIA: falta HardwareAudit.ps1. Hardware y salud no estara disponible.
)
if not exist "%~dp0MaintenanceAudit.ps1" (
  echo ADVERTENCIA: falta MaintenanceAudit.ps1. Mantenimiento no estara disponible.
)
if not exist "%~dp0DesktopUninstall.ps1" (
  echo ERROR: falta DesktopUninstall.ps1. No se iniciara WinCare sin las protecciones de desinstalacion.
  pause
  exit /b 1
)
if not exist "%~dp0AppRules.ps1" (
  echo ERROR: falta AppRules.ps1. La proteccion de aplicaciones requiere el proyecto completo.
  pause
  exit /b 1
)
if not exist "%~dp0AppRecommendations.ps1" (
  echo ADVERTENCIA: falta AppRecommendations.ps1. No se podran editar recomendaciones.
)
if not exist "%~dp0TechToolkit.ps1" (
  echo ADVERTENCIA: falta TechToolkit.ps1. El taller tecnico no estara disponible.
)
if not exist "%~dp0NetworkDiagnostics.ps1" (
  echo ADVERTENCIA: falta NetworkDiagnostics.ps1. Diagnostico inteligente de redes no estara disponible.
)
if not exist "%~dp0NetworkDiagnosticsCore.ps1" (
  echo ADVERTENCIA: falta NetworkDiagnosticsCore.ps1. Pruebas de alcance seguro no disponibles.
)
if not exist "%~dp0SupportTechnician.ps1" (
  echo ADVERTENCIA: falta SupportTechnician.ps1. Soporte de PC no estara disponible.
)
if not exist "%~dp0CCTVAudit.ps1" (
  echo ADVERTENCIA: falta CCTVAudit.ps1. Diagnostico CCTV no estara disponible.
)
if not exist "%~dp0CCTVCore.ps1" (
  echo ADVERTENCIA: falta CCTVCore.ps1. Catalogo CCTV no estara disponible.
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0WinCare.ps1"
if errorlevel 1 pause
endlocal
