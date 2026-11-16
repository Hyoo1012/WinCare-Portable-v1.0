# WinCare Portable v2.1 | Pruebas de inicio diferido
# Diseñado por DevPoderSEO. No ejecuta consultas ni operaciones en Windows.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$cases=@(
    @{File='WinCare.ps1';Control='$form';Forbidden='Refresh-Inventory';Expected='Analizar pestaña'},
    @{File='HardwareAudit.ps1';Control='$script:HForm';Forbidden='Refresh-Hardware';Expected='Analizar sección'},
    @{File='NetworkAudit.ps1';Control='$script:NForm';Forbidden='Refresh-NInventory';Expected='Analizar pestaña'},
    @{File='NetworkDiagnostics.ps1';Control='$script:DForm';Forbidden='Read-DPassive';Expected='Analizar información local'},
    @{File='MaintenanceAudit.ps1';Control='$script:MForm';Forbidden='Read-MStatus';Expected='Analizar estado'},
    @{File='SupportTechnician.ps1';Control='$script:SForm';Forbidden='Read-SPrinters';Expected='Revisar impresoras'},
    @{File='WinCareHealth.ps1';Control='$script:HForm';Forbidden='Read-HChecks';Expected='Verificar de nuevo'},
    @{File='CCTVAudit.ps1';Control='$script:CForm';Forbidden='Load-CInterfaces';Expected='Actualizar adaptadores'}
)
foreach($test in $cases){
    $text=Get-Content -LiteralPath (Join-Path $root $test.File) -Raw -Encoding UTF8
    $pattern=[regex]::Escape([string]$test.Control)+'\.Add_Shown\(\{(?s:(.*?))\}\)'
    $match=[regex]::Match($text,$pattern)
    if(-not $match.Success){throw ('No se encontró el evento de inicio: '+$test.File)}
    if($match.Groups[1].Value -match [regex]::Escape([string]$test.Forbidden)){
        throw ('Se ejecuta una consulta automáticamente en '+$test.File+': '+$test.Forbidden)
    }
    if(-not $text.Contains([string]$test.Expected)){throw ('Falta botón/análisis manual: '+$test.File)}
    Write-Host ('OK: sin análisis inicial en '+$test.File)
}
$advanced=Get-Content -LiteralPath (Join-Path $root 'AdvancedNetwork.ps1') -Raw -Encoding UTF8
if($advanced -notmatch '\$script:PConsent.Checked=\$false'){throw 'No se rechazó permiso activo por defecto.'}
if($advanced -notmatch 'Get-WCLanProbeTargets \$iface 16'){throw 'No hay un límite explícito de destinos LAN.'}
if($advanced -notmatch '\$script:PForm.Add_Shown'){throw 'No está definido el evento de arranque a demanda.'}
if($advanced -match '(?s)\$script:PForm.Add_Shown\(\{[^}]*Run-PDiscovery'){throw 'Se ejecuta descubrimiento al abrir.'}
Write-Host 'OK: análisis bajo demanda y autorización activa desmarcada por defecto.'
