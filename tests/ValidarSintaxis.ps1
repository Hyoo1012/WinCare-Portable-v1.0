# Diseñado por DevPoderSEO
# Comprobación de sintaxis con el analizador nativo de PowerShell.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$files = @('WinCare.ps1','NetworkAudit.ps1','HardwareAudit.ps1','MaintenanceAudit.ps1','AppRules.ps1','AppRecommendations.ps1','TechToolkit.ps1','NetworkDiagnosticsCore.ps1','NetworkDiagnostics.ps1','SupportTechnician.ps1','CCTVCore.ps1','CCTVAudit.ps1','DesktopUninstall.ps1','SteamGames.ps1','WinCareHealth.ps1','packaging/CrearPaquete.ps1')
$hasErrors = $false
foreach ($name in $files) {
    $path = Join-Path $root $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw ("Falta el archivo " + $name) }
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        $hasErrors = $true
        foreach ($errorItem in $errors) {
            Write-Host ("ERROR: {0}:{1}:{2}: {3}" -f $name, $errorItem.Extent.StartLineNumber, $errorItem.Extent.StartColumnNumber, $errorItem.Message)
        }
    } else {
        Write-Host ("SINTAXIS CORRECTA: " + $name)
    }
}
if ($hasErrors) { exit 1 }
Write-Host 'OK: Código WinCare Portable - Diseñado por DevPoderSEO.'
