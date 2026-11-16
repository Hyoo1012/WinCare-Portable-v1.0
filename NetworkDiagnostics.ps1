# WinCare Portable v1.6 - Diagnóstico inteligente de redes
# Diseñado por DevPoderSEO
# No cambia IP, DNS, DHCP, firewall ni otros ajustes.
# Las pruebas activas requieren consentimiento individual.
#requires -Version 5.1
param([object]$Owner,[switch]$SmokeTest,[switch]$SafetyTest)

$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'NetworkDiagnosticsCore.ps1')

$script:DColors=@{
 Bg=[Drawing.Color]::FromArgb(15,24,36)
 Surface=[Drawing.Color]::FromArgb(27,39,56)
 Accent=[Drawing.Color]::FromArgb(41,139,224)
 Text=[Drawing.Color]::FromArgb(240,246,252)
 Muted=[Drawing.Color]::FromArgb(174,190,205)
 Warn=[Drawing.Color]::FromArgb(248,195,109)
 Good=[Drawing.Color]::FromArgb(126,218,181)
}
$script:DInterfaces=@()
$script:DKnown=@()
$script:DWarnings=New-Object 'System.Collections.Generic.List[string]'
$script:DActiveLog=New-Object 'System.Collections.Generic.List[string]'
$script:DResults=New-Object System.Data.DataTable
foreach($col in @('Área','Prueba','Resultado','Estado','Posible causa','Recomendación')){[void]$script:DResults.Columns.Add($col,[string])}
$script:DLan=New-Object System.Data.DataTable
foreach($col in @('IP','MAC','Interfaz','Origen','Resultado','Identificación')){[void]$script:DLan.Columns.Add($col,[string])}
$script:DBusy=$false

function Add-DResult([string]$Area,[string]$Name,[string]$Value,[string]$State='Información',[string]$Cause='',[string]$Advice=''){
    [void]$script:DResults.Rows.Add([object[]]@($Area,$Name,$Value,$State,$Cause,$Advice))
}
function Add-DWarning([string]$Scope,[string]$Description){
    [void]$script:DWarnings.Add(($Scope+': '+$Description))
    Add-DResult $Scope 'Consulta parcial' 'No disponible' 'Información' $Description 'Revisa permisos, adaptador o compatibilidad de Windows.'
}
function Read-DKnown {
    $script:DKnown=@()
    $path=Join-Path $PSScriptRoot 'Red-Confiables.json'
    if(-not (Test-Path -LiteralPath $path -PathType Leaf) -and (Get-Command Resolve-OutputDirectory -ErrorAction SilentlyContinue)){
        $path=Join-Path (Resolve-OutputDirectory) 'Red-Confiables.json'
    }
    if(Test-Path -LiteralPath $path -PathType Leaf){
        try{$script:DKnown=@(Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json | Where-Object {$_.IP})}
        catch{Add-DWarning 'Equipos LAN' ('No se pudo leer la lista de equipos reconocidos: '+$_.Exception.Message)}
    }
}
function Get-DKnownLabel([string]$Address,[string]$Mac){
    foreach($item in @($script:DKnown)){
        if($Mac -and $Mac -notmatch '^00([-:]00){5}$' -and [string]$item.MAC -eq $Mac){return ('Registrado: '+[string]$item.Nombre)}
        if($Address -eq [string]$item.IP -and (-not $Mac -or -not [string]$item.MAC)){return ('Registrado por IP: '+[string]$item.Nombre)}
    }
    return 'No identificado'
}
function Add-DLanRow([string]$IP,[string]$MAC,[string]$Interface,[string]$Origin,[string]$Status,[string]$Label){
    foreach($row in $script:DLan.Rows){
        if([string]$row['IP'] -eq $IP -and [string]$row['Interfaz'] -eq $Interface){
            if($MAC){$row['MAC']=$MAC}
            if($Origin -eq 'Sondeo autorizado'){$row['Origen']='Caché y sondeo'}
            if($Status){$row['Resultado']=$Status}
            if($Label){$row['Identificación']=$Label}
            return
        }
    }
    [void]$script:DLan.Rows.Add([object[]]@($IP,$MAC,$Interface,$Origin,$Status,$Label))
}
function Read-DInterfaces {
    $script:DInterfaces=@()
    $script:DInterfacePicker.Items.Clear()
    $configs=@(Get-NetIPConfiguration -ErrorAction Stop)
    $adapters=@(Get-NetAdapter -ErrorAction SilentlyContinue)
    $connected=@($adapters | Where-Object {$_.Status -eq 'Up'}).Count
    Add-DResult 'Adaptadores' 'Adaptadores activos' ([string]$connected) $(if($connected){'Correcto'}else{'Revisar'}) $(if($connected){''}else{'No se observa interfaz de red conectada.'}) 'Comprueba cable, Wi-Fi, adaptador y controladores.'
    foreach($config in $configs){
        $name=[string]$config.InterfaceAlias
        $status=if($config.NetAdapter){[string]$config.NetAdapter.Status}else{'Sin información'}
        $ip4s=@($config.IPv4Address | Where-Object {$_.IPAddress})
        $ip6s=@($config.IPv6Address | Where-Object {$_.IPAddress})
        $gateway4=@($config.IPv4DefaultGateway | ForEach-Object {$_.NextHop})
        $gateway6=@($config.IPv6DefaultGateway | ForEach-Object {$_.NextHop})
        $dns=@($config.DNSServer.ServerAddresses)
        Add-DResult 'Adaptadores' $name $status $(if($status -eq 'Up'){'Correcto'}else{'Información'}) 'Estado informado por Windows.' 'Si está desconectado, verifica el cable o la red inalámbrica.'
        if($ip4s.Count -eq 0){
            Add-DResult 'IPv4' $name 'No asignada' 'Revisar' 'Puede no haber conectividad IPv4 o estar deshabilitado.' 'Revisa DHCP, dirección estática o adaptador.'
        }
        foreach($ip4 in $ip4s){
            $address=[string]$ip4.IPAddress
            $prefix=[int]$ip4.PrefixLength
            $scope=Get-WCIPv4Scope $address
            $state=if($scope -eq 'Enlace local / APIPA'){'Revisar'}else{'Información'}
            $cause=if($state -eq 'Revisar'){'Windows asignó una dirección 169.254.x.x; podría haber fallado DHCP.'}else{'Red configurada según Windows.'}
            $advice=if($state -eq 'Revisar'){'Verifica enlace, DHCP en el router y configuración del adaptador. No renovar IP sin autorización.'}else{'Confirma que la red y la puerta de enlace sean las esperadas.'}
            Add-DResult 'IPv4' ($name+' /'+$prefix) $address $state $cause $advice
            $gw=if($gateway4.Count){[string]$gateway4[0]}else{''}
            if($scope -eq 'Privada' -and $prefix -ge 8 -and $prefix -le 30){
                $script:DInterfaces+= [pscustomobject]@{Name=$name;IPv4=$address;Prefix=$prefix;Gateway=$gw;InterfaceIndex=[int]$config.InterfaceIndex;Display=($name+' · '+$address+'/'+$prefix)}
            }
        }
        if($ip6s.Count){
            $value=(@($ip6s | ForEach-Object {$_.IPAddress}) -join ', ')
            Add-DResult 'IPv6' $name $value 'Información' 'Direcciones IPv6 configuradas.' 'Si usas IPv6, confirma la puerta de enlace y DNS IPv6.'
        }else{
            Add-DResult 'IPv6' $name 'Sin dirección reportada' 'Información' 'Puede ser normal si tu red usa solo IPv4.' ''
        }
        if($gateway4.Count){
            Add-DResult 'Puerta de enlace' $name ($gateway4 -join ', ') 'Información' 'Router o siguiente salto reportado por Windows.' 'Si no hay Internet, realiza el ping opcional para verificar respuesta.'
        }else{
            Add-DResult 'Puerta de enlace' $name 'No configurada en IPv4' 'Revisar' 'El equipo puede no tener ruta IPv4 predeterminada.' 'Comprueba DHCP, configuración IP o rutas estáticas.'
        }
        if($gateway6.Count){
            Add-DResult 'Puerta de enlace IPv6' $name ($gateway6 -join ', ') 'Información' '' ''
        }
        if($dns.Count){
            Add-DResult 'DNS' $name ($dns -join ', ') 'Información' 'Servidores configurados; esto no prueba que resuelvan.' 'Usa Diagnóstico activo para comprobar resolución DNS.'
        }else{
            Add-DResult 'DNS' $name 'No se reportan servidores' 'Revisar' 'Sin DNS configurado podría fallar la navegación por nombres.' 'Revisa DHCP y la configuración DNS antes de cambiarla.'
        }
        try{
            $i=Get-NetIPInterface -InterfaceIndex ([int]$config.InterfaceIndex) -AddressFamily IPv4 -ErrorAction Stop | Select-Object -First 1
            if($i){Add-DResult 'DHCP' $name ([string]$i.Dhcp) 'Información' 'DHCP deshabilitado puede ser intencional en IP estática.' 'Confirma si el diseño de red usa DHCP o direcciones estáticas.'}
        }catch{Add-DWarning 'DHCP' ($name+': '+$_.Exception.Message)}
    }
    foreach($iface in $script:DInterfaces){[void]$script:DInterfacePicker.Items.Add($iface)}
    $script:DInterfacePicker.DisplayMember='Display'
    if($script:DInterfacePicker.Items.Count){$script:DInterfacePicker.SelectedIndex=0}
}
function Read-DWifi {
    $script:DWifiBox.Text='Consultando interfaz inalámbrica local. No se buscan redes cercanas de forma automática.'
    try {
        $adapter=@(Get-NetAdapter -ErrorAction Stop | Where-Object {
            $_.Name -match '(?i)wi.?fi|wlan|inal[aá]mbric' -or $_.InterfaceDescription -match '(?i)wireless|wi.?fi|802\.11|inal[aá]mbric'
        })
        foreach($a in $adapter){
            Add-DResult 'Wi-Fi' ([string]$a.Name) (([string]$a.Status)+' · '+[string]$a.LinkSpeed) 'Información' 'Velocidad de enlace, no velocidad real de Internet.' 'Para interferencia real se requieren mediciones de espectro/canales.'
        }
        $native=Join-Path $env:WINDIR 'System32\netsh.exe'
        if(Test-Path -LiteralPath $native -PathType Leaf){
            $raw=@(& $native wlan show interfaces 2>&1 | Out-String)
            $script:DWifiBox.Text='Salida informativa de Windows (idioma del equipo):'+[Environment]::NewLine+($raw -join [Environment]::NewLine)
        }else{
            $script:DWifiBox.Text='No está disponible netsh.exe. Verifica si existe adaptador Wi-Fi.'
        }
        Add-DResult 'Wi-Fi' 'Estado local' 'Información disponible en pestaña Wi-Fi' 'Información' 'Puede incluir SSID, BSSID, señal, canal y seguridad.' 'No se ha realizado una búsqueda activa de redes vecinas.'
    }catch{
        $script:DWifiBox.Text='No se pudo leer Wi-Fi: '+$_.Exception.Message
        Add-DWarning 'Wi-Fi' $_.Exception.Message
    }
}
function Read-DNeighbors {
    try{
        Read-DKnown
        foreach($n in @(Get-NetNeighbor -ErrorAction Stop)){
            $ip=[string]$n.IPAddress
            $scope=Get-WCIPv4Scope $ip
            if($scope -ne 'Privada' -and $scope -ne 'Enlace local / APIPA'){continue}
            $mac=[string]$n.LinkLayerAddress
            if($mac -match '^00([-:]00){5}$'){$mac=''}
            $label=Get-DKnownLabel $ip $mac
            Add-DLanRow $ip $mac ([string]$n.InterfaceAlias) 'Caché ARP/ND' ([string]$n.State) $label
        }
        Add-DResult 'Red local' 'Dispositivos observados' ([string]$script:DLan.Rows.Count) 'Información' 'ARP/ND solo contiene vecinos ya observados; no muestra toda la red.' 'Compara con la lista del router; los dispositivos desconocidos no prueban intrusión.'
    }catch{Add-DWarning 'Red local' $_.Exception.Message}
}
function Update-DMap {
    $script:DTree.BeginUpdate()
    try{
        $script:DTree.Nodes.Clear()
        $root=New-Object Windows.Forms.TreeNode('Red local · observaciones, no topología física')
        foreach($iface in @($script:DInterfaces)){
            $text=($iface.Name+' · '+$iface.IPv4+'/'+$iface.Prefix)
            if($iface.Gateway){$text+=' · Router: '+$iface.Gateway}
            $branch=New-Object Windows.Forms.TreeNode($text)
            foreach($row in $script:DLan.Rows){
                if([string]$row['Interfaz'] -ne [string]$iface.Name){continue}
                $line=[string]$row['IP']+' · '+[string]$row['Resultado']+' · '+[string]$row['Identificación']
                [void]$branch.Nodes.Add((New-Object Windows.Forms.TreeNode($line)))
            }
            [void]$root.Nodes.Add($branch)
        }
        if($root.Nodes.Count -eq 0){
            [void]$root.Nodes.Add((New-Object Windows.Forms.TreeNode('No se encontraron interfaces IPv4 privadas activas.')))
        }
        [void]$script:DTree.Nodes.Add($root)
        $script:DTree.ExpandAll()
    }finally{$script:DTree.EndUpdate()}
}
function Read-DPassive {
    if($script:DBusy){return}
    $script:DBusy=$true
    $script:DReadBtn.Enabled=$false
    $script:DResults.Clear()
    $script:DLan.Clear()
    $script:DWarnings.Clear()
    try{
        $script:DStatus.Text='Leyendo configuración local sin enviar pruebas de red...'
        [Windows.Forms.Application]::DoEvents()
        foreach($part in @(
            @('Interfaces',{Read-DInterfaces}),
            @('Wi-Fi',{Read-DWifi}),
            @('Vecinos ARP/ND',{Read-DNeighbors})
        )){
            try{& $part[1]}catch{Add-DWarning ([string]$part[0]) $_.Exception.Message}
        }
        Update-DMap
        $script:DStatus.Text=('{0} resultados · {1} equipos observados · {2} consultas parciales · solo lectura' -f $script:DResults.Rows.Count,$script:DLan.Rows.Count,$script:DWarnings.Count)
    }finally{
        $script:DBusy=$false
        $script:DReadBtn.Enabled=$true
    }
}
function Confirm-DActive([string]$Action,[string]$Details){
    if(-not $script:DConsent.Checked){
        [void][Windows.Forms.MessageBox]::Show('Para realizar una prueba activa, marca primero «Confirmo que soy responsable o estoy autorizado para revisar esta red». Las consultas pasivas siguen disponibles.','Falta autorización','OK','Information')
        return $false
    }
    $message=($Details+[Environment]::NewLine+[Environment]::NewLine+'La red o el servicio de destino pueden registrar estos intentos. No se cambiará ninguna configuración.'+[Environment]::NewLine+'¿Realizar esta prueba ahora?')
    return ([Windows.Forms.MessageBox]::Show($message,$Action,'YesNo','Warning','Button2') -eq [Windows.Forms.DialogResult]::Yes)
}
function Invoke-DPing([string]$Address,[int]$Attempts=2) {
    $ok=0;$sum=[double]0
    $ping=New-Object Net.NetworkInformation.Ping
    try{
        for($i=0;$i -lt $Attempts;$i++){
            try{
                $reply=$ping.Send($Address,850)
                if($reply.Status -eq 'Success'){$ok++;$sum+=[double]$reply.RoundtripTime}
            }catch{}
        }
    }finally{$ping.Dispose()}
    $average=if($ok -gt 0){[math]::Round($sum/$ok,1)}else{$null}
    return [pscustomobject]@{Success=$ok;Total=$Attempts;AverageMs=$average}
}
function Format-DPing($Data) {
    $loss=[math]::Round((($Data.Total-$Data.Success)/[double]$Data.Total)*100,0)
    if($Data.Success -gt 0){return ('{0}/{1} respuestas; pérdida {2}%; promedio {3} ms' -f $Data.Success,$Data.Total,$loss,$Data.AverageMs)}
    return ('0/{0} respuestas; pérdida 100% (ICMP podría estar bloqueado)' -f $Data.Total)
}
function Run-DConnectivity {
    if($script:DBusy){return}
    $iface=$script:DInterfacePicker.SelectedItem
    if($null -eq $iface){
        [void][Windows.Forms.MessageBox]::Show('No se detecta interfaz IPv4 privada para comprobar el router. Revisa la configuración antes de realizar pruebas.','Sin interfaz','OK','Information')
        return
    }
    $details='Se realizarán hasta 2 pings al gateway, 2 pings a 1.1.1.1, una consulta DNS de example.com y una solicitud HTTPS a www.microsoft.com.'+
        [Environment]::NewLine+'Cloudflare, IANA/Microsoft o la red pueden observar el tráfico y tu IP pública de salida.'+
        [Environment]::NewLine+'No se consultan datos personales ni se realiza análisis de intrusos.'
    if(-not (Confirm-DActive 'Diagnóstico activo de Internet' $details)){return}
    $script:DBusy=$true
    $script:DConnectivityBtn.Enabled=$false
    try{
        if($iface.Gateway -and (Test-WCLanTargetAllowed $iface.Gateway $iface)){
            $g=Invoke-DPing ([string]$iface.Gateway)
            Add-DResult 'Pruebas activas' 'Respuesta del gateway' (Format-DPing $g) $(if($g.Success){'Correcto'}else{'Revisar'}) $(if($g.Success){''}else{'El router podría no responder ICMP, incluso si funciona.'}) 'Verifica cable/Wi-Fi y rutas; no consideres un ping fallido como prueba única.'
        }else{
            Add-DResult 'Pruebas activas' 'Gateway' 'Sin destino privado válido' 'Revisar' 'No hay gateway IPv4 privado en esta interfaz.' 'Revisa configuración IP y DHCP.'
        }
        [Windows.Forms.Application]::DoEvents()
        $public=Invoke-DPing '1.1.1.1'
        Add-DResult 'Pruebas activas' 'IP pública de prueba: 1.1.1.1' (Format-DPing $public) $(if($public.Success){'Correcto'}else{'Revisar'}) $(if($public.Success){''}else{'ICMP saliente podría estar bloqueado.'}) 'La ausencia de ping no demuestra falta de Internet; contrasta DNS y HTTPS.'
        [Windows.Forms.Application]::DoEvents()
        try{
            $resolved=@(Resolve-DnsName -Name 'example.com' -Type A -DnsOnly -ErrorAction Stop | Where-Object {$_.IPAddress})
            if($resolved.Count){
                Add-DResult 'Pruebas activas' 'Resolver example.com' ($resolved.IPAddress -join ', ') 'Correcto' 'Consulta DNS completada.' 'Si otros sitios fallan, revisa su DNS o acceso.'
            }else{
                Add-DResult 'Pruebas activas' 'Resolver example.com' 'Sin dirección A reportada' 'Revisar' 'No se obtuvo dirección IPv4.' 'Comprueba servidores DNS, filtros y resolución.'
            }
        }catch{
            Add-DResult 'Pruebas activas' 'Resolver example.com' 'No resuelve' 'Revisar' $_.Exception.Message 'Comprueba DNS y conectividad; algunas redes restringen consultas.'
        }
        [Windows.Forms.Application]::DoEvents()
        $oldTls=[Net.ServicePointManager]::SecurityProtocol
        try{
            [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
            $response=Invoke-WebRequest -Uri 'https://www.microsoft.com' -Method Head -UseBasicParsing -TimeoutSec 7 -ErrorAction Stop
            Add-DResult 'Pruebas activas' 'HTTPS externo' ('Código HTTP '+[string][int]$response.StatusCode) 'Correcto' 'Conexión web completada con el sitio de prueba.' 'Esto no mide la velocidad total del enlace.'
        }catch{
            Add-DResult 'Pruebas activas' 'HTTPS externo' 'No verificado' 'Revisar' $_.Exception.Message 'Puede deberse a proxy, TLS, filtrado, DNS o falta de conectividad.'
        }finally{[Net.ServicePointManager]::SecurityProtocol=$oldTls}
        [void]$script:DActiveLog.Add(((Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+' | Prueba Internet autorizada | '+$iface.Name))
        $script:DStatus.Text='Prueba de conectividad terminada. Compara gateway, IP, DNS y HTTPS; un fallo aislado no prueba una avería.'
        $script:DTabs.SelectedIndex=0
    }finally{$script:DBusy=$false;$script:DConnectivityBtn.Enabled=$true}
}
function Get-DSelectedLanInterface {
    if(-not $script:DInterfacePicker.SelectedItem){return $null}
    return $script:DInterfacePicker.SelectedItem
}
function Run-DLanDiscovery {
    if($script:DBusy){return}
    $iface=Get-DSelectedLanInterface
    if($null -eq $iface){
        [void][Windows.Forms.MessageBox]::Show('Selecciona un adaptador IPv4 privado válido. No se escanearán redes públicas ni subredes arbitrarias.','LAN','OK','Warning')
        return
    }
    $targets=@(Get-WCLanProbeTargets $iface 16)
    if($targets.Count -eq 0){
        [void][Windows.Forms.MessageBox]::Show('No hay destinos privados elegibles. La subred debe tener prefijo /8 a /30 y un IPv4 privado.','LAN','OK','Information')
        return
    }
    $details=('Se enviará UN ping ICMP a un máximo de '+$targets.Count+' IP privadas de la subred local '+$iface.IPv4+'/'+$iface.Prefix+'.'+
        [Environment]::NewLine+'Se revisan pocas direcciones próximas al gateway y al equipo, no toda la red. No hay escaneo de puertos ni acceso a dispositivos.')
    if(-not (Confirm-DActive 'Descubrimiento LAN autorizado' $details)){return}
    $script:DBusy=$true
    $script:DLanBtn.Enabled=$false
    try{
        foreach($target in $targets){
            $ping=Invoke-DPing $target 1
            $state=if($ping.Success){'Respondió ICMP'}else{'No responde ICMP'}
            $known=Get-DKnownLabel $target ''
            Add-DLanRow $target '' ([string]$iface.Name) 'Sondeo autorizado' $state $known
            [Windows.Forms.Application]::DoEvents()
        }
        # ARP/ND posterior al ping puede revelar MAC para equipos que ya fueron alcanzados.
        try{
            foreach($n in @(Get-NetNeighbor -InterfaceIndex ([int]$iface.InterfaceIndex) -AddressFamily IPv4 -ErrorAction SilentlyContinue)){
                $ip=[string]$n.IPAddress
                if(-not ($targets -contains $ip)){continue}
                $mac=[string]$n.LinkLayerAddress
                $label=Get-DKnownLabel $ip $mac
                Add-DLanRow $ip $mac ([string]$iface.Name) 'Sondeo autorizado' '' $label
            }
        }catch{[void]$script:DWarnings.Add('No se pudieron actualizar MAC posteriores al sondeo.')}
        Update-DMap
        [void]$script:DActiveLog.Add(((Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+' | LAN autorizada | '+$iface.Name+' | '+$targets.Count+' IP'))
        $script:DStatus.Text=('Descubrimiento limitado terminado: '+$targets.Count+' IP consultadas. La falta de respuesta no implica equipo apagado.')
        $script:DTabs.SelectedIndex=2
    }finally{$script:DBusy=$false;$script:DLanBtn.Enabled=$true}
}
function Run-DPortCheck {
    if($script:DBusy){return}
    $iface=Get-DSelectedLanInterface
    $target=[string]$script:DTargetIP.Text.Trim()
    $port=0
    if(-not [int]::TryParse([string]$script:DPort.Text,[ref]$port) -or $port -lt 1 -or $port -gt 65535){
        [void][Windows.Forms.MessageBox]::Show('Puerto inválido (1 a 65535).','Prueba de puerto','OK','Warning')
        return
    }
    if(-not (Test-WCLanTargetAllowed $target $iface)){
        [void][Windows.Forms.MessageBox]::Show('Solo se permite una IPv4 privada de la subred activa elegida. No se admiten IP públicas ni equipos externos.','Destino fuera de alcance','OK','Warning')
        return
    }
    $details=('Se intentará UNA conexión TCP a '+$target+':'+$port+' dentro de la red local autorizada.'+
        [Environment]::NewLine+'Un puerto abierto no confirma que el equipo sea seguro ni que ofrezca el servicio esperado; no se enviarán contraseñas.')
    if(-not (Confirm-DActive 'Comprobación de puerto TCP' $details)){return}
    $client=New-Object Net.Sockets.TcpClient
    $connected=$false;$detail=''
    try{
        $async=$client.BeginConnect($target,$port,$null,$null)
        try{
            if($async.AsyncWaitHandle.WaitOne(900)){
                try{$client.EndConnect($async);$connected=$true}catch{$detail=$_.Exception.Message}
            }else{$detail='La conexión superó el tiempo permitido.'}
        }finally{$async.AsyncWaitHandle.Close()}
    }catch{$detail=$_.Exception.Message}
    finally{$client.Close()}
    $state=if($connected){'Correcto'}else{'Información'}
    $value=if($connected){'TCP accesible'}else{'TCP no accesible en esta prueba'}
    Add-DResult 'Puerto LAN' ($target+':'+$port) $value $state $detail 'Un fallo puede indicar filtro, servicio inactivo o puerto cerrado; confirma el servicio con su fabricante.'
    [void]$script:DActiveLog.Add(((Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+' | Puerto autorizado | '+$target+':'+$port))
    $script:DStatus.Text=('Prueba TCP de '+$target+':'+$port+' finalizada: '+$value)
    $script:DTabs.SelectedIndex=0
}
function Run-DWifiScan {
    if($script:DBusy){return}
    if(-not (Confirm-DActive 'Búsqueda de redes Wi-Fi' 'Windows consultará redes Wi-Fi visibles mediante netsh wlan show networks mode=bssid. Puede iniciar búsqueda inalámbrica local y mostrar SSID, BSSID, canales y señal; no se capturan paquetes ni claves.')){return}
    try{
        $exe=Join-Path $env:WINDIR 'System32\netsh.exe'
        if(-not (Test-Path -LiteralPath $exe -PathType Leaf)){throw 'netsh.exe no disponible.'}
        $raw=@(& $exe wlan show networks mode=bssid 2>&1 | Out-String)
        $script:DWifiBox.Text='Búsqueda Wi-Fi voluntaria (idioma de Windows):'+[Environment]::NewLine+($raw -join [Environment]::NewLine)
        Add-DResult 'Wi-Fi' 'Redes cercanas' 'Consulta voluntaria completada' 'Información' 'La presencia de otras redes no prueba interferencia perjudicial.' 'Compara canales y señal; un analizador de espectro ofrece medición más fiable.'
        [void]$script:DActiveLog.Add(((Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+' | Búsqueda Wi-Fi voluntaria'))
        $script:DTabs.SelectedIndex=1
    }catch{
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Wi-Fi','OK','Warning')
    }
}
function Encode-DHtml($Value){return [Net.WebUtility]::HtmlEncode([string]$Value)}
function Build-DHtml([object[]]$Results,[object[]]$Peers,[datetime]$Date) {
    $sb=New-Object Text.StringBuilder
    [void]$sb.Append('<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>WinCare · Diagnóstico de red</title>')
    [void]$sb.Append('<style>body{background:#101827;color:#e9eff9;font:14px Segoe UI,Arial,sans-serif;margin:0}main{max-width:1180px;margin:30px auto;padding:26px}header{border-bottom:2px solid #318cdb;margin-bottom:25px}h1{margin:0}small{color:#b1c6da}table{border-collapse:collapse;width:100%;font-size:12px;margin:16px 0 28px}th,td{padding:9px 8px;border:1px solid #34465d;text-align:left;vertical-align:top;overflow-wrap:anywhere}th{background:#233b56}.warn{color:#ffd29f}footer{color:#acc0d3}@media print{body{background:white;color:#172538}th{background:#eceff5;color:#122238}.warn{color:#8a430c}}</style></head><body><main>')
    [void]$sb.Append('<header><h1>Diagnóstico de red · WinCare Portable</h1><p>Diseñado por DevPoderSEO · '+(Encode-DHtml $Date.ToString('yyyy-MM-dd HH:mm'))+'</p></header>')
    [void]$sb.Append('<p>Este informe es orientativo. Una IP no reconocida NO confirma intrusión; un ping fallido NO confirma equipo apagado. Las pruebas activas requieren autorización.</p>')
    [void]$sb.Append('<h2>Resultados</h2><table><thead><tr><th>Área</th><th>Prueba</th><th>Resultado</th><th>Estado</th><th>Posible causa</th><th>Recomendación</th></tr></thead><tbody>')
    foreach($r in @($Results)){
        [void]$sb.Append('<tr><td>'+(Encode-DHtml $r.Area)+'</td><td>'+(Encode-DHtml $r.Name)+'</td><td>'+(Encode-DHtml $r.Value)+'</td><td>'+(Encode-DHtml $r.Status)+'</td><td>'+(Encode-DHtml $r.Cause)+'</td><td>'+(Encode-DHtml $r.Advice)+'</td></tr>')
    }
    [void]$sb.Append('</tbody></table><h2>Dispositivos observados (caché o sondeo limitado)</h2><table><thead><tr><th>IP</th><th>MAC</th><th>Interfaz</th><th>Origen</th><th>Resultado</th><th>Identificación</th></tr></thead><tbody>')
    foreach($p in @($Peers)){
        [void]$sb.Append('<tr><td>'+(Encode-DHtml $p.IP)+'</td><td>'+(Encode-DHtml $p.MAC)+'</td><td>'+(Encode-DHtml $p.Interface)+'</td><td>'+(Encode-DHtml $p.Source)+'</td><td>'+(Encode-DHtml $p.Result)+'</td><td>'+(Encode-DHtml $p.Label)+'</td></tr>')
    }
    [void]$sb.Append('</tbody></table><footer>WinCare no certifica ausencia de fallos ni amenazas. El mapa representa observaciones lógicas, no cableado físico. Los IP y MAC pueden ser sensibles. No se incluyen scripts remotos ni recursos web.</footer></main></body></html>')
    return $sb.ToString()
}
function Export-DReports {
    try{
        $root=if(Get-Command Resolve-OutputDirectory -ErrorAction SilentlyContinue){Resolve-OutputDirectory}else{Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WinCarePortable\Reportes'}
        if(-not (Test-Path -LiteralPath $root)){[void](New-Item -Path $root -ItemType Directory -Force -ErrorAction Stop)}
        $folder=Join-Path $root ('red-diagnostico-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
        [void](New-Item -Path $folder -ItemType Directory -Force)
        $rows=@(foreach($r in $script:DResults.Rows){
            [pscustomobject]@{Area=[string]$r['Área'];Name=[string]$r['Prueba'];Value=[string]$r['Resultado'];Status=[string]$r['Estado'];Cause=[string]$r['Posible causa'];Advice=[string]$r['Recomendación']}
        })
        $peers=@(foreach($p in $script:DLan.Rows){
            [pscustomobject]@{IP=[string]$p['IP'];MAC=[string]$p['MAC'];Interface=[string]$p['Interfaz'];Source=[string]$p['Origen'];Result=[string]$p['Resultado'];Label=[string]$p['Identificación']}
        })
        if($rows.Count){$rows|Export-Csv -LiteralPath (Join-Path $folder 'diagnostico.csv') -Encoding UTF8 -NoTypeInformation}
        if($peers.Count){$peers|Export-Csv -LiteralPath (Join-Path $folder 'equipos-lan.csv') -Encoding UTF8 -NoTypeInformation}
        $html=Build-DHtml -Results $rows -Peers $peers -Date (Get-Date)
        [IO.File]::WriteAllText((Join-Path $folder 'diagnostico.html'),$html,(New-Object Text.UTF8Encoding($true)))
        ('WinCare · Diseñado por DevPoderSEO'+[Environment]::NewLine+'Las pruebas activas solamente se realizaron tras autorización.'+[Environment]::NewLine+($script:DActiveLog -join [Environment]::NewLine)+[Environment]::NewLine+($script:DWarnings -join [Environment]::NewLine))|Set-Content -LiteralPath (Join-Path $folder 'actividad-y-advertencias.txt') -Encoding UTF8
        [void][Windows.Forms.MessageBox]::Show(('Informe HTML y CSV guardados en '+$folder+'. No se envió a Internet.'),'Exportación de diagnóstico','OK','Information')
        [void](Start-Process -FilePath (Join-Path $folder 'diagnostico.html') -ErrorAction Stop)
    }catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Exportación no completada','OK','Warning')}
}
function New-DGrid($Table) {
    $grid=New-Object Windows.Forms.DataGridView
    $grid.Dock='Fill'
    $grid.ReadOnly=$true
    $grid.AllowUserToAddRows=$false
    $grid.AllowUserToDeleteRows=$false
    $grid.RowHeadersVisible=$false
    $grid.SelectionMode='FullRowSelect'
    $grid.AutoGenerateColumns=$false
    $grid.AutoSizeColumnsMode='DisplayedCells'
    $grid.BackgroundColor=$script:DColors.Surface
    $grid.EnableHeadersVisualStyles=$false
    $grid.ColumnHeadersDefaultCellStyle.BackColor=[Drawing.Color]::FromArgb(39,57,78)
    $grid.ColumnHeadersDefaultCellStyle.ForeColor=$script:DColors.Text
    $grid.DefaultCellStyle.BackColor=$script:DColors.Surface
    $grid.DefaultCellStyle.ForeColor=$script:DColors.Text
    $grid.DefaultCellStyle.SelectionBackColor=[Drawing.Color]::FromArgb(44,112,177)
    $grid.DefaultCellStyle.SelectionForeColor=[Drawing.Color]::White
    foreach($dataColumn in $Table.Columns){
        $name=[string]$dataColumn.ColumnName
        $col=New-Object Windows.Forms.DataGridViewTextBoxColumn
        $col.Name=$name;$col.DataPropertyName=$name;$col.HeaderText=$name
        [void]$grid.Columns.Add($col)
    }
    $grid.DataSource=$Table.DefaultView
    return $grid
}

$script:DForm=New-Object Windows.Forms.Form
$script:DForm.Text='WinCare v1.6 | Diagnóstico inteligente de redes | DevPoderSEO'
$script:DForm.StartPosition='CenterParent'
$script:DForm.Size=New-Object Drawing.Size(1280,815)
$script:DForm.MinimumSize=New-Object Drawing.Size(1050,710)
$script:DForm.BackColor=$script:DColors.Bg
$script:DForm.ForeColor=$script:DColors.Text
$script:DForm.Font=New-Object Drawing.Font('Segoe UI',9)

$heading=New-Object Windows.Forms.Label
$heading.Text='Diagnóstico inteligente de redes'
$heading.Location=New-Object Drawing.Point(20,15)
$heading.Size=New-Object Drawing.Size(860,36)
$heading.Font=New-Object Drawing.Font('Segoe UI Semibold',18,[Drawing.FontStyle]::Bold)
$script:DForm.Controls.Add($heading)
$brand=New-Object Windows.Forms.Label
$brand.Text='Diseñado por DevPoderSEO'
$brand.Location=New-Object Drawing.Point(943,25)
$brand.Size=New-Object Drawing.Size(294,27)
$brand.Anchor='Top,Right'
$brand.TextAlign='MiddleRight'
$brand.ForeColor=$script:DColors.Accent
$script:DForm.Controls.Add($brand)
$subtitle=New-Object Windows.Forms.Label
$subtitle.Text='Análisis inicial pasivo. Las pruebas que envían tráfico requieren autorización expresa.'
$subtitle.Location=New-Object Drawing.Point(22,56)
$subtitle.Size=New-Object Drawing.Size(1160,27)
$subtitle.ForeColor=$script:DColors.Muted
$subtitle.Anchor='Top,Left,Right'
$script:DForm.Controls.Add($subtitle)

$script:DReadBtn=New-Object Windows.Forms.Button
$script:DReadBtn.Text='Actualizar información local'
$script:DReadBtn.Location=New-Object Drawing.Point(20,93)
$script:DReadBtn.Size=New-Object Drawing.Size(210,34)
$script:DReadBtn.BackColor=$script:DColors.Accent
$script:DReadBtn.ForeColor=[Drawing.Color]::White
$script:DReadBtn.FlatStyle='Flat'
$script:DReadBtn.Add_Click({ Read-DPassive })
$script:DForm.Controls.Add($script:DReadBtn)
$script:DInterfacePicker=New-Object Windows.Forms.ComboBox
$script:DInterfacePicker.DropDownStyle='DropDownList'
$script:DInterfacePicker.Location=New-Object Drawing.Point(241,96)
$script:DInterfacePicker.Size=New-Object Drawing.Size(354,29)
$script:DInterfacePicker.BackColor=$script:DColors.Surface
$script:DInterfacePicker.ForeColor=$script:DColors.Text
$script:DForm.Controls.Add($script:DInterfacePicker)
$script:DConsent=New-Object Windows.Forms.CheckBox
$script:DConsent.Text='Estoy autorizado para comprobar esta red'
$script:DConsent.Location=New-Object Drawing.Point(615,93)
$script:DConsent.Size=New-Object Drawing.Size(342,34)
$script:DConsent.ForeColor=$script:DColors.Warn
$script:DConsent.Checked=$false
$script:DForm.Controls.Add($script:DConsent)
$export=New-Object Windows.Forms.Button
$export.Text='Exportar informe'
$export.Location=New-Object Drawing.Point(1000,93)
$export.Size=New-Object Drawing.Size(225,34)
$export.Anchor='Top,Right'
$export.Add_Click({ Export-DReports })
$script:DForm.Controls.Add($export)

$script:DTabs=New-Object Windows.Forms.TabControl
$script:DTabs.Location=New-Object Drawing.Point(20,146)
$script:DTabs.Size=New-Object Drawing.Size(1215,582)
$script:DTabs.Anchor='Top,Bottom,Left,Right'
$script:DForm.Controls.Add($script:DTabs)
$diag=New-Object Windows.Forms.TabPage
$diag.Text='Diagnóstico'
$diag.BackColor=$script:DColors.Surface
$wifi=New-Object Windows.Forms.TabPage
$wifi.Text='Wi-Fi'
$wifi.BackColor=$script:DColors.Surface
$lan=New-Object Windows.Forms.TabPage
$lan.Text='Mapa LAN'
$lan.BackColor=$script:DColors.Surface
$tools=New-Object Windows.Forms.TabPage
$tools.Text='Pruebas autorizadas'
$tools.BackColor=$script:DColors.Surface
[void]$script:DTabs.TabPages.AddRange([Windows.Forms.TabPage[]]@($diag,$wifi,$lan,$tools))
$script:DGrid=New-DGrid $script:DResults
$diag.Controls.Add($script:DGrid)
$script:DGrid.Add_CellFormatting({
    param($sender,$eventArgs)
    if($eventArgs.RowIndex -lt 0 -or $eventArgs.ColumnIndex -lt 0){return}
    if([string]$sender.Columns[$eventArgs.ColumnIndex].Name -ne 'Estado'){return}
    switch([string]$eventArgs.Value){
        'Correcto' {$eventArgs.CellStyle.ForeColor=$script:DColors.Good}
        'Revisar' {$eventArgs.CellStyle.ForeColor=$script:DColors.Warn}
        default {$eventArgs.CellStyle.ForeColor=$script:DColors.Text}
    }
})
$script:DWifiBox=New-Object Windows.Forms.TextBox
$script:DWifiBox.Dock='Fill'
$script:DWifiBox.ReadOnly=$true
$script:DWifiBox.Multiline=$true
$script:DWifiBox.ScrollBars='Both'
$script:DWifiBox.WordWrap=$false
$script:DWifiBox.BackColor=$script:DColors.Surface
$script:DWifiBox.ForeColor=$script:DColors.Text
$script:DWifiBox.Font=New-Object Drawing.Font('Consolas',10)
$script:DWifiBox.Text='Información del Wi-Fi disponible después del análisis pasivo.'
$wifi.Controls.Add($script:DWifiBox)

$lanSplit=New-Object Windows.Forms.SplitContainer
$lanSplit.Dock='Fill'
$lanSplit.Orientation='Horizontal'
$lanSplit.SplitterDistance=212
$lan.Controls.Add($lanSplit)
$script:DTree=New-Object Windows.Forms.TreeView
$script:DTree.Dock='Fill'
$script:DTree.BackColor=$script:DColors.Surface
$script:DTree.ForeColor=$script:DColors.Text
$script:DTree.Font=New-Object Drawing.Font('Segoe UI',10)
$lanSplit.Panel1.Controls.Add($script:DTree)
$script:DLanGrid=New-DGrid $script:DLan
$lanSplit.Panel2.Controls.Add($script:DLanGrid)
$script:DLanGrid.Add_SelectionChanged({
    if($null -eq $script:DTargetIP -or $script:DLanGrid.SelectedRows.Count -ne 1){return}
    $row=$script:DLanGrid.SelectedRows[0]
    if(-not $row.IsNewRow){$script:DTargetIP.Text=[string]$row.Cells['IP'].Value}
})

$controlPanel=New-Object Windows.Forms.FlowLayoutPanel
$controlPanel.Dock='Fill'
$controlPanel.AutoScroll=$true
$controlPanel.FlowDirection='TopDown'
$controlPanel.WrapContents=$false
$tools.Controls.Add($controlPanel)
function Add-DSection([string]$Title,[string]$Note,[scriptblock]$Action,[string]$ButtonText) {
    $box=New-Object Windows.Forms.Panel
    $box.Size=New-Object Drawing.Size(1100,95)
    $box.Margin=New-Object Windows.Forms.Padding(12,9,12,9)
    $box.BackColor=[Drawing.Color]::FromArgb(33,49,69)
    $label=New-Object Windows.Forms.Label
    $label.Text=$Title
    $label.Location=New-Object Drawing.Point(13,9)
    $label.Size=New-Object Drawing.Size(800,28)
    $label.Font=New-Object Drawing.Font('Segoe UI Semibold',12,[Drawing.FontStyle]::Bold)
    $box.Controls.Add($label)
    $desc=New-Object Windows.Forms.Label
    $desc.Text=$Note
    $desc.Location=New-Object Drawing.Point(13,44)
    $desc.Size=New-Object Drawing.Size(800,43)
    $desc.ForeColor=$script:DColors.Muted
    $box.Controls.Add($desc)
    $btn=New-Object Windows.Forms.Button
    $btn.Text=$ButtonText
    $btn.Location=New-Object Drawing.Point(850,29)
    $btn.Size=New-Object Drawing.Size(224,37)
    $btn.BackColor=$script:DColors.Accent
    $btn.ForeColor=[Drawing.Color]::White
    $btn.FlatStyle='Flat'
    $btn.Add_Click($Action)
    $box.Controls.Add($btn)
    $controlPanel.Controls.Add($box)
    return $btn
}
$script:DConnectivityBtn=Add-DSection '01 · Conectividad y DNS' 'Gateway, ping externo, resolución DNS y HTTPS. Las peticiones externas revelan tu IP pública.' { Run-DConnectivity } 'Comprobar Internet'
$script:DLanBtn=Add-DSection '02 · Descubrimiento LAN limitado' 'Hasta 16 destinos IPv4 privados de la subred activa. No recorre toda la red ni prueba credenciales.' { Run-DLanDiscovery } 'Descubrir LAN'
$script:DWifiScanBtn=Add-DSection '03 · Redes Wi-Fi cercanas' 'Búsqueda voluntaria de SSID, canales y BSSID mediante netsh. No captura tráfico ni contraseñas.' { Run-DWifiScan } 'Explorar Wi-Fi'
$portPanel=New-Object Windows.Forms.Panel
$portPanel.Size=New-Object Drawing.Size(1100,112)
$portPanel.Margin=New-Object Windows.Forms.Padding(12,9,12,9)
$portPanel.BackColor=[Drawing.Color]::FromArgb(33,49,69)
$portHeading=New-Object Windows.Forms.Label
$portHeading.Text='04 · Puerto TCP de un dispositivo autorizado'
$portHeading.Location=New-Object Drawing.Point(13,8)
$portHeading.Size=New-Object Drawing.Size(750,28)
$portHeading.Font=New-Object Drawing.Font('Segoe UI Semibold',12,[Drawing.FontStyle]::Bold)
$portPanel.Controls.Add($portHeading)
$portHint=New-Object Windows.Forms.Label
$portHint.Text='Escribe una IP privada autorizada o selecciónala del Mapa LAN. Puertos habituales: 80, 443, 554, 8000, 8080.'
$portHint.Location=New-Object Drawing.Point(13,38)
$portHint.Size=New-Object Drawing.Size(1000,22)
$portHint.ForeColor=$script:DColors.Muted
$portPanel.Controls.Add($portHint)
$script:DTargetIP=New-Object Windows.Forms.TextBox
$script:DTargetIP.Location=New-Object Drawing.Point(14,73)
$script:DTargetIP.Size=New-Object Drawing.Size(305,27)
$script:DTargetIP.Text=''
$portPanel.Controls.Add($script:DTargetIP)
$script:DPort=New-Object Windows.Forms.ComboBox
$script:DPort.DropDownStyle='DropDownList'
$script:DPort.Location=New-Object Drawing.Point(332,73)
$script:DPort.Size=New-Object Drawing.Size(160,27)
$script:DPort.Items.AddRange([object[]]@('80','443','554','8000','8080','3389','22'))
$script:DPort.SelectedIndex=0
$portPanel.Controls.Add($script:DPort)
$script:DPortBtn=New-Object Windows.Forms.Button
$script:DPortBtn.Text='Comprobar puerto'
$script:DPortBtn.Location=New-Object Drawing.Point(850,67)
$script:DPortBtn.Size=New-Object Drawing.Size(224,36)
$script:DPortBtn.Add_Click({Run-DPortCheck})
$portPanel.Controls.Add($script:DPortBtn)
$controlPanel.Controls.Add($portPanel)

$script:DStatus=New-Object Windows.Forms.Label
$script:DStatus.Location=New-Object Drawing.Point(22,739)
$script:DStatus.Size=New-Object Drawing.Size(1192,27)
$script:DStatus.Anchor='Bottom,Left,Right'
$script:DStatus.ForeColor=$script:DColors.Muted
$script:DStatus.Text='Listo. No se ha enviado ninguna prueba activa.'
$script:DForm.Controls.Add($script:DStatus)

if($SmokeTest){
    if($script:DTabs.TabPages.Count -ne 4){throw 'Se esperaban cuatro secciones de diagnóstico.'}
    if($script:DGrid.Columns.Count -ne 6 -or $script:DLanGrid.Columns.Count -ne 6){throw 'Columnas incompletas en diagnóstico.'}
    if($script:DConsent.Checked){throw 'La autorización de tráfico no puede estar marcada por defecto.'}
    if(-not $script:DConnectivityBtn -or -not $script:DLanBtn -or -not $script:DPortBtn){throw 'Faltan acciones activas.'}
    Write-Host 'OK: diagnóstico de redes con cuatro pestañas y autorización desactivada por defecto.'
    $script:DForm.Dispose()
    return
}
if($SafetyTest){
    $interface=[pscustomobject]@{IPv4='192.168.8.105';Prefix=24;Gateway='192.168.8.1';Name='Test';InterfaceIndex=1}
    $probes=@(Get-WCLanProbeTargets $interface 16)
    if($probes.Count -gt 16 -or $probes.Count -eq 0){throw 'Sondeo excedió límites o devolvió cero destinos.'}
    foreach($ip in $probes){if(-not (Test-WCLanTargetAllowed $ip $interface)){throw ('Destino no autorizado: '+$ip)}}
    if(Test-WCLanTargetAllowed '1.1.1.1' $interface){throw 'IP pública permitida.'}
    if(Test-WCLanTargetAllowed '192.168.9.8' $interface){throw 'IP privada fuera de subred permitida.'}
    if(@(Get-WCLanProbeTargets ([pscustomobject]@{IPv4='8.8.8.8';Prefix=24;Gateway='8.8.8.1'}) 16).Count -ne 0){throw 'Sondeo de IP pública permitido.'}
    $html=Build-DHtml -Results @([pscustomobject]@{Area='test';Name='<script>alert(1)</script>';Value='&';Status='Información';Cause='<img>';Advice='ok'}) -Peers @() -Date (Get-Date)
    if($html -match '<script>alert' -or $html -notmatch '&lt;script&gt;'){throw 'Texto no escapado en HTML.'}
    Write-Host 'OK: máximo 16 IP privadas de misma subred, destino externo bloqueado, HTML seguro. CERO pings.'
    $script:DForm.Dispose()
    return
}
$script:DForm.Add_Shown({$script:DStatus.Text='Sin analizar. Pulsa Analizar información local; las pruebas activas también requieren autorización.'})
try{
    if($Owner -is [Windows.Forms.IWin32Window]){[void]$script:DForm.ShowDialog($Owner)}
    else{[void]$script:DForm.ShowDialog()}
}finally{$script:DForm.Dispose()}
