# WinCare Portable | Diseñado por DevPoderSEO
# Verifica codificación HTML del informe, sin ejecutarse diagnósticos ni reparaciones.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
& (Join-Path $root 'TechToolkit.ps1') -SafetyTest
