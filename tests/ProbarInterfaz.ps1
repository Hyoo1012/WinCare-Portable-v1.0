# Pruebas locales no destructivas - Diseñado por DevPoderSEO
# Se ejecuta en Windows PowerShell 5.1 con Windows Forms disponible.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Write-Host 'Iniciando prueba de construccion de WinCare (sin inventario ni desinstalacion)...'
& (Join-Path $root 'WinCare.ps1') -SmokeTest
Write-Host 'Iniciando prueba de construccion de seguridad de red (sin escaneo ni ping)...'
& (Join-Path $root 'NetworkAudit.ps1') -SmokeTest
Write-Host 'Probando ventana Hardware y salud sin leer ni modificar el equipo...'
& (Join-Path $root 'HardwareAudit.ps1') -SmokeTest
Write-Host 'OK: las tres interfaces iniciaron tablas sin columnas nulas.'
