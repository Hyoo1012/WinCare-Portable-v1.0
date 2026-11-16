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
Write-Host 'Probando Centro de mantenimiento sin lectura ni limpieza...'
& (Join-Path $root 'MaintenanceAudit.ps1') -SmokeTest
Write-Host 'Probando catálogo de recomendaciones sin escribir reglas...'
& (Join-Path $root 'AppRecommendations.ps1') -SmokeTest
Write-Host 'Probando Taller técnico sin leer equipos ni ejecutar reparaciones...'
& (Join-Path $root 'TechToolkit.ps1') -SmokeTest
Write-Host 'Probando panel de diagnóstico de redes sin generar tráfico...'
& (Join-Path $root 'NetworkDiagnostics.ps1') -SmokeTest
Write-Host 'Probando soporte PC v1.7 sin alterar servicio de impresión...'
& (Join-Path $root 'SupportTechnician.ps1') -SmokeTest
Write-Host 'Probando catálogo y diagnóstico CCTV v1.8 sin tráfico LAN...'
& (Join-Path $root 'CCTVAudit.ps1') -SmokeTest
Write-Host 'Probando autodiagnóstico WinCare sin escribir archivos...'
& (Join-Path $root 'WinCareHealth.ps1') -SmokeTest
Write-Host 'Probando centro avanzado de redes sin contacto ni consultas...'
& (Join-Path $root 'AdvancedNetwork.ps1') -SmokeTest
Write-Host 'OK: once interfaces construidas sin operaciones destructivas ni tráfico.'
