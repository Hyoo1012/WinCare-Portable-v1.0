@echo off
REM WinCare Portable - Diseñado por DevPoderSEO
REM Prueba local y voluntaria: no desinstala, no limpia, no explora la red.
setlocal
cd /d "%~dp0"
if not exist "%~dp0ValidarWinCare.ps1" (
  echo ERROR: No se encontro ValidarWinCare.ps1.
  pause
  exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0ValidarWinCare.ps1"
set "CODIGO=%ERRORLEVEL%"
echo.
if "%CODIGO%"=="0" (echo VALIDACION BASICA COMPLETADA.) else (echo VALIDACION FALLIDA. Copia el error para su revision.)
pause
exit /b %CODIGO%
