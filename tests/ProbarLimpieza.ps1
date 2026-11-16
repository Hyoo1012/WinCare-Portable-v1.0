# Diseñado por DevPoderSEO
# Casos seguros: nunca limpia el sistema real; usa ficheros de prueba temporales.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Write-Host 'Probando rutas permitidas, extensiones autorizadas y bloqueo de ejecutables...'
& (Join-Path $root 'MaintenanceAudit.ps1') -SafetyTest
Write-Host 'OK: pruebas conservadoras de candidatos de limpieza.'
