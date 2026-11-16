# WinCare Portable v2.1 - Crear ZIP confiable para USB Ventoy
# Diseñado por DevPoderSEO. No requiere elevación ni descarga de Internet.
#requires -Version 5.1
param([string]$DestinationDirectory='')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if([string]::IsNullOrWhiteSpace($DestinationDirectory)){$DestinationDirectory=Join-Path $root 'dist'}
$required=@(
 'WinCare.ps1','DesktopUninstall.ps1','SteamGames.ps1','AppRules.ps1','AppRecommendations.ps1',
 'NetworkAudit.ps1','NetworkDiagnostics.ps1','NetworkDiagnosticsCore.ps1','HardwareAudit.ps1',
 'MaintenanceAudit.ps1','TechToolkit.ps1','SupportTechnician.ps1','CCTVCore.ps1','CCTVAudit.ps1',
 'WinCareHealth.ps1','AdvancedNetworkCore.ps1','AdvancedNetwork.ps1','INICIAR_WINCARE.bat','LEEME.txt','README.md'
)
$example='Configuracion/recomendaciones.ejemplo.json'
$ouiExample='Configuracion/fabricantes-oui.ejemplo.csv'
foreach($rel in $required+@($example,$ouiExample)){
    if(-not (Test-Path -LiteralPath (Join-Path $root $rel) -PathType Leaf)){
        throw ('No se puede crear el paquete; falta '+$rel)
    }
}
if(-not (Test-Path -LiteralPath $DestinationDirectory)){
    [void](New-Item -Path $DestinationDirectory -ItemType Directory -Force)
}
$work=Join-Path ([IO.Path]::GetTempPath()) ('WinCare-Paquete-'+[guid]::NewGuid().ToString('N'))
$stage=Join-Path $work 'WinCarePortable'
$verify=Join-Path $work 'Comprobacion'
$zip=Join-Path $DestinationDirectory 'WinCarePortable-v2.1.zip'
try{
    [void](New-Item -Path $stage -ItemType Directory -Force)
    foreach($rel in $required){
        Copy-Item -LiteralPath (Join-Path $root $rel) -Destination (Join-Path $stage $rel) -ErrorAction Stop
    }
    $cfg=Join-Path $stage 'Configuracion'
    [void](New-Item -Path $cfg -ItemType Directory -Force)
    Copy-Item -LiteralPath (Join-Path $root $example) -Destination (Join-Path $cfg 'recomendaciones.ejemplo.json') -ErrorAction Stop
    Copy-Item -LiteralPath (Join-Path $root $ouiExample) -Destination (Join-Path $cfg 'fabricantes-oui.ejemplo.csv') -ErrorAction Stop
    $version='WinCare Portable v2.1'+[Environment]::NewLine+'Diseñado por DevPoderSEO'+[Environment]::NewLine+'Generado: '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+[Environment]::NewLine+'Se ejecuta dentro de Windows 10/11.'+[Environment]::NewLine
    [IO.File]::WriteAllText((Join-Path $stage 'VERSION.txt'),$version,(New-Object Text.UTF8Encoding($true)))
    $lines=New-Object 'System.Collections.Generic.List[string]'
    foreach($f in @(Get-ChildItem -LiteralPath $stage -File -Recurse -ErrorAction Stop | Sort-Object FullName)){
        $hash=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
        $relative=$f.FullName.Substring($stage.Length+1).Replace('\','/')
        [void]$lines.Add(($hash+'  '+$relative))
    }
    [IO.File]::WriteAllLines((Join-Path $stage 'SHA256SUMS.txt'),$lines.ToArray(),(New-Object Text.UTF8Encoding($true)))
    if(Test-Path -LiteralPath $zip){Remove-Item -LiteralPath $zip -Force}
    Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal -ErrorAction Stop
    [void](New-Item -Path $verify -ItemType Directory -Force)
    Expand-Archive -LiteralPath $zip -DestinationPath $verify -Force -ErrorAction Stop
    foreach($rel in $required+@($example,$ouiExample,'SHA256SUMS.txt','VERSION.txt')){
        if(-not (Test-Path -LiteralPath (Join-Path (Join-Path $verify 'WinCarePortable') $rel) -PathType Leaf)){
            throw ('Paquete ZIP incompleto: '+$rel)
        }
    }
    $verifiedRoot=Join-Path $verify 'WinCarePortable'
    foreach($line in @(Get-Content -LiteralPath (Join-Path $verifiedRoot 'SHA256SUMS.txt') -Encoding UTF8 -ErrorAction Stop)){
        if($line -notmatch '^([0-9A-Fa-f]{64})  ([A-Za-z0-9_.\/-]+)$'){throw 'Línea SHA256 inválida dentro del ZIP.'}
        $expected=[string]$matches[1];$relative=[string]$matches[2]
        if($relative -match '(^|/)\.\.(/|$)'){throw 'Ruta inválida en manifiesto SHA256.'}
        $file=[IO.Path]::GetFullPath((Join-Path $verifiedRoot $relative.Replace('/','\')))
        $prefix=[IO.Path]::GetFullPath($verifiedRoot).TrimEnd('\')+'\'
        if(-not $file.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){
            throw 'Una ruta del manifiesto sale del paquete.'
        }
        $actual=(Get-FileHash -LiteralPath $file -Algorithm SHA256 -ErrorAction Stop).Hash
        if($actual -ne $expected){throw ('Integridad SHA256 incorrecta: '+$relative)}
    }
    foreach($forbidden in @('Reportes','Configuracion/recomendaciones.json','Configuracion/cctv-dispositivos.json','.env')){
        if(Test-Path -LiteralPath (Join-Path (Join-Path $verify 'WinCarePortable') $forbidden)){throw ('El ZIP contiene datos privados: '+$forbidden)}
    }
    Write-Host ('OK: ZIP portátil completo, verificado y sin reportes privados: '+$zip)
}finally{
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
