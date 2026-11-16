# WinCare Portable v2.1 | Diseñado por DevPoderSEO
# Pruebas sin escaneo, conectividad externa ni cambios de sistema
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'NetworkDiagnosticsCore.ps1')
. (Join-Path $root 'AdvancedNetworkCore.ps1')
$subnet=Get-WCProSubnetInfo '192.168.10.45' 24
if($subnet.Network -ne '192.168.10.0' -or $subnet.Mask -ne '255.255.255.0' -or $subnet.TotalUsable -ne 254){throw 'No calculó /24.'}
$iface=[pscustomobject]@{IPv4='10.10.10.12';Prefix=24;Gateway='10.10.10.1'}
if(-not (Test-WCProPrivateTarget '10.10.10.22' $iface)){throw 'No reconoció IP privada local.'}
foreach($bad in @('10.10.11.10','8.8.8.8','224.0.0.1','127.0.0.1','169.254.1.1')){
 if(Test-WCProPrivateTarget $bad $iface){throw ('Permitió destino fuera de alcance: '+$bad)}
}
$summary=Get-WCProPingSummary @(
 [pscustomobject]@{Success=$true;Milliseconds=10},
 [pscustomobject]@{Success=$false;Milliseconds=0},
 [pscustomobject]@{Success=$true;Milliseconds=20},
 [pscustomobject]@{Success=$true;Milliseconds=30}
)
if($summary.Sent -ne 4 -or $summary.Received -ne 3 -or $summary.LossPct -ne 25 -or $summary.AverageMs -ne 20 -or $summary.JitterMs -ne 10){throw 'No calculó pérdida/RTT/jitter.'}
if((Get-WCProSeverity $summary 20 150 40) -ne 'Revisar'){throw 'No detectó superación de umbral.'}
$matrix=@(Get-WCProCapabilityMatrix)
foreach($feature in @('SNMP v1 / v2c / v3','NetFlow / sFlow / IPFIX','DPI / captura PCAP','Topología L2 física')){
 $item=@($matrix|Where-Object {$_.Protocolo -eq $feature})
 if($item.Count -ne 1 -or $item[0].Estado -eq 'Integrado'){throw ('Capacidad externa mal declarada: '+$feature)}
}
$html=New-WCProHtmlReport -Devices @([pscustomobject]@{IP='<script>alert(1)</script>';MAC='';Fabricante='';Origen='';Estado='';SO=''}) -Measurements @() -Applications @() -Comment '<img src=x>'
if($html -match '<script>alert' -or $html -match '<img src=x>' -or $html -notmatch '&lt;script&gt;'){throw 'HTML no protegido.'}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('WC-Pro-Config-'+[guid]::NewGuid().ToString('N'))
try{
 [void](New-Item -Path $temp -ItemType Directory -Force)
 $cfg=Join-Path $temp 'switch.cfg'
 Set-Content -LiteralPath $cfg -Encoding UTF8 -Value 'hostname=switch-de-prueba'
 $fingerprint=Get-WCProConfigFingerprint $cfg
 if($fingerprint.Hash -notmatch '^[A-Fa-f0-9]{64}
& (Join-Path $root 'AdvancedNetwork.ps1') -SafetyTest
Write-Host 'OK: redes avanzadas a demanda, métricas, subredes, restricciones LAN y reportes; sin tráfico.'
){throw 'No generó SHA256 de configuración.'}
 $baseline=Join-Path $temp 'config-baselines.json'
 Save-WCProConfigBaseline $baseline 'switch-de-prueba' $fingerprint
 $records=@(Read-WCProConfigBaselines $baseline)
 if($records.Count -ne 1 -or [string]$records[0].SHA256 -ne [string]$fingerprint.Hash){throw 'No guardó referencia SHA256.'}
 Set-Content -LiteralPath $cfg -Encoding UTF8 -Value 'hostname=switch-modificado'
 $changed=Get-WCProConfigFingerprint $cfg
 if($changed.Hash -eq $fingerprint.Hash){throw 'No detectó modificación de archivo.'}
}finally{
 Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
& (Join-Path $root 'AdvancedNetwork.ps1') -SmokeTest
& (Join-Path $root 'AdvancedNetwork.ps1') -SafetyTest
Write-Host 'OK: redes avanzadas a demanda, métricas, subredes, restricciones LAN y reportes; sin tráfico.'
