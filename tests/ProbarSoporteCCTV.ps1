# WinCare Portable v1.7 y v1.8 - Diseñado por DevPoderSEO
# Pruebas aisladas. Nunca reinicia servicios ni contacta cámaras/red.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
& (Join-Path $root 'SupportTechnician.ps1') -SafetyTest
& (Join-Path $root 'CCTVAudit.ps1') -SafetyTest
Write-Host 'OK: soporte y CCTV seguros, reportes escapados, catálogos validados y cero conexiones.'
