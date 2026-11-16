# WinCare Portable v2.1 | Motor puro de diagnóstico avanzado
# Diseñado por DevPoderSEO. No envía tráfico, no modifica el sistema.
#requires -Version 5.1

function Get-WCProSubnetInfo([string]$IPv4,[int]$Prefix){
    if((Get-WCIPv4Scope $IPv4) -ne 'Privada' -or $Prefix -lt 8 -or $Prefix -gt 30){throw 'Selecciona una IPv4 privada con prefijo entre /8 y /30.'}
    $num=Convert-WCIPv4Number $IPv4
    $size=[uint64][math]::Pow(2,(32-$Prefix))
    $first=[uint64]([math]::Floor([double]$num/$size)*$size)
    $last=$first+$size-1
    $mask=[uint64]4294967295-$size+1
    return [pscustomobject]@{
        Address=$IPv4
        Prefix=$Prefix
        Network=(Convert-WCNumberIPv4 $first)
        Mask=(Convert-WCNumberIPv4 $mask)
        Broadcast=(Convert-WCNumberIPv4 $last)
        FirstHost=(Convert-WCNumberIPv4 ($first+1))
        LastHost=(Convert-WCNumberIPv4 ($last-1))
        TotalUsable=[uint64]($size-2)
    }
}

function Get-WCProPingSummary([object[]]$Samples){
    $items=@($Samples)
    $success=@($items | Where-Object {$_.Success -eq $true})
    $count=$items.Count
    $good=$success.Count
    $lost=$count-$good
    $avg=[double]0; $min=[double]0; $max=[double]0; $jitter=[double]0
    $times=@()
    foreach($row in $success){$times+=([double]$row.Milliseconds)}
    if($times.Count){
        $avg=[math]::Round((($times|Measure-Object -Average).Average),2)
        $min=($times|Measure-Object -Minimum).Minimum
        $max=($times|Measure-Object -Maximum).Maximum
        if($times.Count -gt 1){
            $delta=[double]0
            for($n=1;$n -lt $times.Count;$n++){$delta+=[math]::Abs($times[$n]-$times[$n-1])}
            $jitter=[math]::Round(($delta/($times.Count-1)),2)
        }
    }
    return [pscustomobject]@{
        Sent=$count;Received=$good;Lost=$lost
        LossPct=$(if($count){[math]::Round((100.0*$lost/$count),2)}else{0})
        AverageMs=$avg;MinMs=$min;MaxMs=$max;JitterMs=$jitter
        JitterMethod='Media de diferencias absolutas entre RTT exitosos consecutivos; estimación, no RFC3550'
    }
}
function Get-WCProSeverity($Summary,[double]$MaxLossPct=20,[double]$MaxLatencyMs=150,[double]$MaxJitterMs=40){
    if($null -eq $Summary -or [int]$Summary.Sent -eq 0){return 'Sin datos'}
    if([double]$Summary.LossPct -ge $MaxLossPct -or [double]$Summary.AverageMs -gt $MaxLatencyMs -or [double]$Summary.JitterMs -gt $MaxJitterMs){return 'Revisar'}
    return 'Correcto'
}
function Test-WCProPrivateTarget([string]$IP,$Interface){
    return (Test-WCLanTargetAllowed $IP $Interface)
}
function Get-WCProMacVendor([string]$Mac,[hashtable]$Oui){
    if([string]::IsNullOrWhiteSpace($Mac) -or $null -eq $Oui){return 'No disponible'}
    $clean=($Mac -replace '[^0-9A-Fa-f]','').ToUpperInvariant()
    if($clean.Length -lt 6){return 'No disponible'}
    $prefix=$clean.Substring(0,6)
    if($Oui.ContainsKey($prefix)){return [string]$Oui[$prefix]}
    return 'No identificado (sin coincidencia OUI)'
}
function Read-WCProOui([string]$Path){
    $result=@{}
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){return $result}
    $file=Get-Item -LiteralPath $Path -ErrorAction Stop
    if($file.Length -gt 524288){throw 'El catálogo OUI supera el límite de 512 KB.'}
    $lineCount=0
    foreach($line in @(Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop)){
        $lineCount++
        if($lineCount -gt 5000){break}
        if($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)){continue}
        # Archivo deliberadamente sencillo: prefijo hexadecimal de 6 caracteres; nombre.
        if($line -notmatch '^([0-9A-Fa-f]{6});([^;\r\n]{1,120})$'){continue}
        $prefix=([string]$matches[1]).ToUpperInvariant()
        $result[$prefix]=([string]$matches[2]).Trim()
    }
    return $result
}
function Get-WCProCapabilityMatrix {
    return @(
        [pscustomobject]@{Protocolo='ICMP';Estado='Integrado';Detalle='Pruebas manuales de latencia, jitter y pérdida con límites y permiso.'}
        [pscustomobject]@{Protocolo='WMI/CIM local';Estado='Integrado';Detalle='Consulta de adaptadores y procesos del propio PC. No accede remotamente a servidores.'}
        [pscustomobject]@{Protocolo='TCP';Estado='Integrado';Detalle='Un puerto por destino IPv4 privado de la subred seleccionada.'}
        [pscustomobject]@{Protocolo='DNS';Estado='Integrado';Detalle='Resolución puntual elegida por el operador; puede ser enviada a un servidor DNS.'}
        [pscustomobject]@{Protocolo='SNMP v1 / v2c / v3';Estado='Requiere integración';Detalle='No se envían credenciales ni comunidades sin un gestor SNMP dedicado.'}
        [pscustomobject]@{Protocolo='NetFlow / sFlow / IPFIX';Estado='Requiere colector';Detalle='Requieren exportadores en switches/routers y un servicio receptor permanente.'}
        [pscustomobject]@{Protocolo='Syslog';Estado='Requiere colector';Detalle='La escucha continua necesita servicio, puertos/firewall y política de retención.'}
        [pscustomobject]@{Protocolo='DPI / captura PCAP';Estado='Herramienta externa';Detalle='Requiere Npcap/Wireshark o un sensor autorizado; no captura cargas útiles.'}
        [pscustomobject]@{Protocolo='SNR, interferencia, mapa de calor Wi-Fi';Estado='Requiere mediciones';Detalle='Windows ofrece señal/canal; heatmap y SNR fiables precisan puntos de medición y/o hardware.'}
        [pscustomobject]@{Protocolo='Alertas correo / SMS / web / móvil';Estado='Requiere servicio';Detalle='Para alertas persistentes se necesita un agente o servidor, credenciales y autorizaciones.'}
        [pscustomobject]@{Protocolo='Topología L2 física';Estado='Requiere LLDP/SNMP';Detalle='Sin vecinos LLDP, puertos y tablas de bridge solo se produce un mapa lógico inferido.'}
        [pscustomobject]@{Protocolo='PDF';Estado='Imprimible';Detalle='Se genera HTML/CSV; puedes imprimir el HTML mediante Microsoft Print to PDF.'}
    )
}
function Encode-WCProHtml($Value){return [Net.WebUtility]::HtmlEncode([string]$Value)}
function New-WCProHtmlReport([object[]]$Devices,[object[]]$Measurements,[object[]]$Applications,[string]$Comment){
    $sb=New-Object Text.StringBuilder
    [void]$sb.Append('<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Informe WinCare Redes</title><style>body{font:14px Segoe UI,Arial;background:#152131;color:#eaf2fb;max-width:1100px;margin:28px auto}table{border-collapse:collapse;width:100%;margin:15px 0}th,td{border:1px solid #687b8e;padding:8px;text-align:left;overflow-wrap:anywhere}h1,h2{color:#91cfff}@media print{body{color:#18202b;background:white}h1,h2{color:#16365a}}</style></head><body>')
    [void]$sb.Append('<h1>Informe de red · WinCare Portable</h1><p>Diseñado por DevPoderSEO · '+(Get-Date -Format 'yyyy-MM-dd HH:mm')+'</p>')
    [void]$sb.Append('<p>Mapa de red lógico estimado: no demuestra conexiones físicas L2, fabricante ni sistema operativo. Sin agente externo, los datos pueden ser parciales.</p><p>'+(Encode-WCProHtml $Comment)+'</p>')
    foreach($section in @(@('Equipos observados',$Devices,@('IP','MAC','Fabricante','Origen','Estado','SO','Confianza')), @('Métricas',$Measurements,@('Momento','IP','Pérdida','RTT medio','Jitter','Estado')), @('Conexiones por aplicación',$Applications,@('Proceso','PID','Conexiones','Remotos')))){
        [void]$sb.Append('<h2>'+(Encode-WCProHtml $section[0])+'</h2><table><tr>')
        foreach($c in $section[2]){[void]$sb.Append('<th>'+(Encode-WCProHtml $c)+'</th>')}
        [void]$sb.Append('</tr>')
        foreach($row in @($section[1])){
            [void]$sb.Append('<tr>')
            foreach($c in $section[2]){
                $value=''
                if($null -ne $row -and $row.PSObject.Properties.Match($c).Count){$value=$row.$c}
                [void]$sb.Append('<td>'+(Encode-WCProHtml $value)+'</td>')
            }
            [void]$sb.Append('</tr>')
        }
        [void]$sb.Append('</table>')
    }
    [void]$sb.Append('<p>Datos sujetos a privacidad. Pérdida, latencia y jitter son muestras puntuales, no SLA continuo. Para PDF usa Imprimir del navegador.</p></body></html>')
    return $sb.ToString()
}


# Comparación manual de huellas de configuraciones exportadas por el técnico.
# Solo guarda nombre lógico, fecha, tamaño y SHA256; NO guarda contraseñas ni el archivo original.
function Get-WCProConfigFingerprint([string]$Path){
    $file=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if($file -isnot [IO.FileInfo]){throw 'Selecciona un archivo regular de configuración.'}
    if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'No se admiten enlaces para calcular huellas.'}
    if($file.Length -gt 8388608){throw 'Archivo de configuración demasiado grande (máximo 8 MB).'}
    if($file.Extension.ToLowerInvariant() -notin @('.cfg','.conf','.txt','.json','.ini','.xml','.backup')){throw 'Solo se admiten exportaciones de texto/configuración reconocibles.'}
    return [pscustomobject]@{Name=[string]$file.Name;Bytes=[long]$file.Length;Hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash}
}
function Read-WCProConfigBaselines([string]$Path){
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){return @()}
    $file=Get-Item -LiteralPath $Path -ErrorAction Stop
    if($file.Length -gt 262144){throw 'El registro de huellas supera 256 KB.'}
    $doc=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if([string]$doc.Version -ne '1'){throw 'Versión de huellas no compatible; no se sobrescribirá.'}
    return @($doc.Dispositivos | Where-Object {$_ -and $_.Nombre})
}
function Save-WCProConfigBaseline([string]$Path,[string]$Name,$Fingerprint){
    $Name=$Name.Trim()
    if($Name.Length -lt 1 -or $Name.Length -gt 100 -or $Name -match '[\x00-\x1f]'){throw 'Nombre lógico inválido (1-100 caracteres).'}
    if($null -eq $Fingerprint -or [string]$Fingerprint.Hash -notmatch '^[a-fA-F0-9]{64}$'){throw 'Huella de archivo inválida.'}
    $items=@(Read-WCProConfigBaselines $Path | Where-Object {[string]$_.Nombre -ne $Name})
    $items+= [pscustomobject]@{Nombre=$Name;SHA256=[string]$Fingerprint.Hash;Bytes=[long]$Fingerprint.Bytes;Actualizado=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')}
    if($items.Count -gt 100){throw 'Máximo 100 configuraciones de referencia.'}
    $folder=Split-Path -Parent $Path
    if(-not (Test-Path -LiteralPath $folder)){[void](New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop)}
    $temp=Join-Path $folder ('.huellas-'+[guid]::NewGuid().ToString('N')+'.json')
    try{
        $json=ConvertTo-Json -InputObject ([ordered]@{Version=1;Dispositivos=$items}) -Depth 4
        [IO.File]::WriteAllText($temp,$json,(New-Object Text.UTF8Encoding($true)))
        if(Test-Path -LiteralPath $Path -PathType Leaf){Copy-Item -LiteralPath $Path -Destination ($Path+'.bak') -Force -ErrorAction Stop}
        Move-Item -LiteralPath $temp -Destination $Path -Force -ErrorAction Stop
    }finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue}}
}
