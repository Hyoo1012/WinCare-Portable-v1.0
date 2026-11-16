# WinCare Portable v2.1 | Comprobación local sin redes ni cambios
# Diseñado por DevPoderSEO. Ejecutar solo bajo petición del técnico.
#requires -Version 5.1
param([switch]$NoPause)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$files=@(
 'WinCare.ps1','AppRules.ps1','DesktopUninstall.ps1','SteamGames.ps1',
 'AppRecommendations.ps1','HardwareAudit.ps1','MaintenanceAudit.ps1',
 'NetworkAudit.ps1','NetworkDiagnostics.ps1','NetworkDiagnosticsCore.ps1',
 'AdvancedNetworkCore.ps1','AdvancedNetwork.ps1','TechToolkit.ps1',
 'SupportTechnician.ps1','CCTVCore.ps1','CCTVAudit.ps1','WinCareHealth.ps1'
)
$errors=New-Object 'System.Collections.Generic.List[string]'
$passed=0
Write-Host 'WinCare Portable v2.1 | Validación local de sintaxis e interfaces'
Write-Host 'Diseñado por DevPoderSEO. No se harán escaneos, limpiezas ni desinstalaciones.'
foreach($relative in $files){
    $path=Join-Path $root $relative
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){
        [void]$errors.Add('Falta archivo: '+$relative)
        continue
    }
    $tokens=$null;$parseErrors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
    if(@($parseErrors).Count -gt 0){
        foreach($problem in $parseErrors){
            [void]$errors.Add(('{0}:{1}: {2}' -f $relative,$problem.Extent.StartLineNumber,$problem.Message))
        }
    }else{$passed++}
}
if($errors.Count -eq 0){
    try{
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        foreach($module in @('WinCare.ps1','NetworkAudit.ps1','NetworkDiagnostics.ps1','AdvancedNetwork.ps1','HardwareAudit.ps1','MaintenanceAudit.ps1','AppRecommendations.ps1','TechToolkit.ps1','SupportTechnician.ps1','CCTVAudit.ps1','WinCareHealth.ps1')){
            Write-Host ('Probando interfaz sin abrir análisis: '+$module)
            & (Join-Path $root $module) -SmokeTest
        }
        & (Join-Path $root 'AdvancedNetwork.ps1') -SafetyTest
        $passed+=12
    }catch{[void]$errors.Add('Falló prueba no destructiva: '+$_.Exception.Message)}
}
if($errors.Count -eq 0){
    Write-Host ('CORRECTO: '+$passed+' comprobaciones. No se hicieron cambios de sistema.') -ForegroundColor Green
    Write-Host 'Esta validación básica no equivale a probar dispositivos, drivers, red, Steam ni hardware real.'
    exit 0
}
Write-Host ('NO APROBADO: '+$errors.Count+' incidencia(s). No uses esta copia en equipos de clientes.') -ForegroundColor Red
foreach($error in $errors){Write-Host ('  ERROR: '+$error) -ForegroundColor Red}
exit 1
