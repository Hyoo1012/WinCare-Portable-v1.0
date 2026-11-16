# WinCare v1.6 - Reglas seguras de diagnostico de red
# Diseñado por DevPoderSEO. No genera tráfico ni cambia Windows.
#requires -Version 5.1

function Convert-WCIPv4Number([string]$Address) {
    $ip=$null
    if(-not [Net.IPAddress]::TryParse($Address,[ref]$ip)){return $null}
    if($ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork){return $null}
    $b=$ip.GetAddressBytes()
    return ([uint64]$b[0]*16777216+[uint64]$b[1]*65536+[uint64]$b[2]*256+[uint64]$b[3])
}
function Convert-WCNumberIPv4([uint64]$Number) {
    if($Number -gt [uint64]4294967295){return ''}
    $a=[int][math]::Floor($Number/16777216)
    $b=[int][math]::Floor(($Number%16777216)/65536)
    $c=[int][math]::Floor(($Number%65536)/256)
    $d=[int]($Number%256)
    return ('{0}.{1}.{2}.{3}' -f $a,$b,$c,$d)
}
function Get-WCIPv4Scope([string]$Address) {
    $ip=$null
    if(-not [Net.IPAddress]::TryParse($Address,[ref]$ip)){return 'Inválida'}
    if($ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork){return 'No IPv4'}
    $b=$ip.GetAddressBytes()
    if($b[0] -eq 10 -or ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or ($b[0] -eq 192 -and $b[1] -eq 168)){return 'Privada'}
    if($b[0] -eq 169 -and $b[1] -eq 254){return 'Enlace local / APIPA'}
    if($b[0] -eq 127){return 'Loopback'}
    if($b[0] -eq 100 -and $b[1] -ge 64 -and $b[1] -le 127){return 'CGNAT'}
    if($b[0] -eq 0 -or $b[0] -ge 224){return 'Reservada'}
    return 'Pública u otra'
}
function Test-WCIPv4Subnet([string]$Address,[string]$LocalAddress,[int]$PrefixLength) {
    if($PrefixLength -lt 1 -or $PrefixLength -gt 32){return $false}
    $a=Convert-WCIPv4Number $Address
    $local=Convert-WCIPv4Number $LocalAddress
    if($null -eq $a -or $null -eq $local){return $false}
    $block=[uint64][math]::Pow(2,32-$PrefixLength)
    return ([math]::Floor([double]$a/$block) -eq [math]::Floor([double]$local/$block))
}
function Test-WCLanTargetAllowed([string]$Target,$Interface) {
    if($null -eq $Interface){return $false}
    if((Get-WCIPv4Scope $Target) -ne 'Privada'){return $false}
    $address=[string]$Interface.IPv4
    $prefix=0
    try{$prefix=[int]$Interface.Prefix}catch{return $false}
    if($prefix -lt 8 -or $prefix -gt 30){return $false}
    if((Get-WCIPv4Scope $address) -ne 'Privada'){return $false}
    if(-not (Test-WCIPv4Subnet $Target $address $prefix)){return $false}
    $targetNumber=Convert-WCIPv4Number $Target
    $ipNumber=Convert-WCIPv4Number $address
    $block=[uint64][math]::Pow(2,32-$prefix)
    $start=[uint64]([math]::Floor([double]$ipNumber/$block)*$block)
    $end=$start+$block-1
    if($targetNumber -le $start -or $targetNumber -ge $end){return $false}
    return $true
}
function Get-WCLanProbeTargets($Interface,[int]$Maximum=16) {
    # Máximo fijo: no es un escáner de subredes completas.
    if($Maximum -lt 1 -or $Maximum -gt 16){return @()}
    if($null -eq $Interface){return @()}
    $own=[string]$Interface.IPv4
    $gateway=[string]$Interface.Gateway
    if((Get-WCIPv4Scope $own) -ne 'Privada'){return @()}
    $prefix=0
    try{$prefix=[int]$Interface.Prefix}catch{return @()}
    if($prefix -lt 8 -or $prefix -gt 30){return @()}
    $ownNumber=Convert-WCIPv4Number $own
    $gwNumber=Convert-WCIPv4Number $gateway
    $visited=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $list=New-Object 'System.Collections.Generic.List[string]'
    # Se mezclan pocos hosts próximos a la puerta de enlace y al equipo.
    # No se descubre toda la red; la lista de vecinos pasiva aporta otros IP.
    $candidates=New-Object 'System.Collections.Generic.List[uint64]'
    if($null -ne $gwNumber -and (Test-WCLanTargetAllowed $gateway $Interface)){
        [void]$candidates.Add([uint64]$gwNumber)
        for($offset=1;$offset -le 8;$offset++){[void]$candidates.Add([uint64]($gwNumber+$offset))}
    }
    for($delta=-4;$delta -le 12;$delta++){
        $candidate=[int64]$ownNumber+$delta
        if($candidate -ge 0 -and $candidate -le 4294967295){[void]$candidates.Add([uint64]$candidate)}
    }
    foreach($num in $candidates) {
        $target=Convert-WCNumberIPv4 $num
        if($target -eq $own){continue}
        if(-not (Test-WCLanTargetAllowed $target $Interface)){continue}
        if($visited.Add($target)){
            [void]$list.Add($target)
            if($list.Count -ge $Maximum){break}
        }
    }
    return @($list.ToArray())
}
