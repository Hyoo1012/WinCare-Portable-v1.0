# WinCare Portable v1.6 | Diseñado por DevPoderSEO
# Pruebas puras: no realiza pings, consultas DNS, escaneos ni cambios en Windows.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'NetworkDiagnosticsCore.ps1')
if((Get-WCIPv4Scope '192.168.2.2') -ne 'Privada'){throw 'No reconoció rango LAN privado.'}
if((Get-WCIPv4Scope '169.254.1.2') -ne 'Enlace local / APIPA'){throw 'No reconoció APIPA.'}
if((Get-WCIPv4Scope '8.8.8.8') -eq 'Privada'){throw 'IP pública mal clasificada.'}
if(-not (Test-WCIPv4Subnet '192.168.5.254' '192.168.5.20' 24)){throw 'Error de subred /24.'}
if(Test-WCIPv4Subnet '192.168.6.254' '192.168.5.20' 24){throw 'Aceptó fuera de subred.'}
$interface=[pscustomobject]@{Name='Test';IPv4='192.168.5.125';Prefix=24;Gateway='192.168.5.1';InterfaceIndex=1}
$targets=@(Get-WCLanProbeTargets $interface 16)
if($targets.Count -eq 0 -or $targets.Count -gt 16){throw 'Cantidad de hosts incorrecta.'}
foreach($target in $targets){if(-not (Test-WCLanTargetAllowed $target $interface)){throw ('Destino prohibido: '+$target)}}
foreach($ip in @('8.8.8.8','192.168.6.10','169.254.12.5','127.0.0.1','224.0.0.1','0.0.0.0')){
    if(Test-WCLanTargetAllowed $ip $interface){throw ('Se aceptó IP no autorizada: '+$ip)}
}
if(@(Get-WCLanProbeTargets ([pscustomobject]@{Name='Public';IPv4='1.1.1.1';Prefix=24;Gateway='1.1.1.254'}) 16).Count -ne 0){throw 'Sondeo de red pública permitido.'}
$small=[pscustomobject]@{Name='Small';IPv4='10.1.1.2';Prefix=30;Gateway='10.1.1.1'}
if(@(Get-WCLanProbeTargets $small 16).Count -gt 1){throw 'Sondeó broadcast/red en /30.'}
& (Join-Path $root 'NetworkDiagnostics.ps1') -SafetyTest
Write-Host 'OK: validaciones de red local, exclusión de públicos, rango limitado, sin pruebas activas.'
