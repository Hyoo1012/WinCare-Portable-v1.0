# WinCare Portable v2.1 - Diagnóstico avanzado a demanda
# Diseñado por DevPoderSEO | Windows PowerShell 5.1
# No sondea redes ni captura paquetes automáticamente.
#requires -Version 5.1
param([object]$Owner,[switch]$SmokeTest,[switch]$SafetyTest)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'NetworkDiagnosticsCore.ps1')
. (Join-Path $PSScriptRoot 'AdvancedNetworkCore.ps1')
$script:PBg=[Drawing.Color]::FromArgb(17,26,38)
$script:PPanel=[Drawing.Color]::FromArgb(28,42,59)
$script:PText=[Drawing.Color]::FromArgb(238,245,253)
$script:PBlue=[Drawing.Color]::FromArgb(36,132,214)
$script:PWarn=[Drawing.Color]::FromArgb(250,196,115)
$script:PBusy=$false
$script:PInterfaces=@()
$script:POui=@{}
$script:PTrusted=@()
$script:PDevices=New-Object System.Data.DataTable
foreach($name in @('IP','MAC','Fabricante','Origen','Estado','SO','Confianza')){[void]$script:PDevices.Columns.Add($name,[string])}
$script:PMetrics=New-Object System.Data.DataTable
foreach($name in @('Momento','IP','Pérdida','RTT medio','Jitter','Estado')){[void]$script:PMetrics.Columns.Add($name,[string])}
$script:PFlows=New-Object System.Data.DataTable
foreach($name in @('Proceso','PID','Conexiones','Remotos')){[void]$script:PFlows.Columns.Add($name,[string])}
$script:PProtocols=New-Object System.Data.DataTable
foreach($name in @('Protocolo','Estado','Detalle')){[void]$script:PProtocols.Columns.Add($name,[string])}
function New-PGrid($Data){
    $g=New-Object Windows.Forms.DataGridView
    $g.Dock='Fill';$g.ReadOnly=$true;$g.RowHeadersVisible=$false
    $g.AllowUserToAddRows=$false;$g.AllowUserToDeleteRows=$false
    $g.AutoGenerateColumns=$false;$g.AutoSizeColumnsMode='DisplayedCells'
    $g.SelectionMode='FullRowSelect';$g.BackgroundColor=$script:PPanel
    $g.EnableHeadersVisualStyles=$false
    $g.ColumnHeadersDefaultCellStyle.BackColor=[Drawing.Color]::FromArgb(42,57,76)
    $g.ColumnHeadersDefaultCellStyle.ForeColor=$script:PText
    $g.DefaultCellStyle.BackColor=$script:PPanel;$g.DefaultCellStyle.ForeColor=$script:PText
    $g.DefaultCellStyle.SelectionBackColor=[Drawing.Color]::FromArgb(43,108,174)
    $g.DefaultCellStyle.SelectionForeColor=[Drawing.Color]::White
    foreach($c in $Data.Columns){
        $col=New-Object Windows.Forms.DataGridViewTextBoxColumn
        $col.Name=[string]$c.ColumnName;$col.HeaderText=$col.Name;$col.DataPropertyName=$col.Name
        [void]$g.Columns.Add($col)
    }
    $g.DataSource=$Data.DefaultView
    return $g
}
function Set-PStatus([string]$Text){$script:PStatus.Text=$Text}
function Get-PInterface {
    $iface=$script:PInterface.SelectedItem
    if($null -eq $iface){Set-PStatus 'Primero pulsa Analizar adaptadores y elige una interfaz privada activa.';return $null}
    return $iface
}
function Confirm-PActive([string]$Text) {
    if(-not $script:PConsent.Checked){
        [void][Windows.Forms.MessageBox]::Show('Debes marcar que tienes autorización para hacer pruebas activas de red.','Permiso requerido','OK','Warning')
        return $false
    }
    return ([Windows.Forms.MessageBox]::Show(($Text+[Environment]::NewLine+'Los equipos podrían registrar estas comprobaciones. ¿Continuar?'),'Prueba de red autorizada','YesNo','Warning','Button2') -eq [Windows.Forms.DialogResult]::Yes)
}
function Read-PAdapters {
    if($script:PBusy){return}
    $script:PBusy=$true
    try {
        $script:PInterfaces=@();$script:PInterface.Items.Clear()
        foreach($cfg in @(Get-NetIPConfiguration -ErrorAction Stop)){
            if(-not $cfg.NetAdapter -or [string]$cfg.NetAdapter.Status -ne 'Up'){continue}
            foreach($v4 in @($cfg.IPv4Address)){
                $address=[string]$v4.IPAddress;$prefix=[int]$v4.PrefixLength
                if((Get-WCIPv4Scope $address) -ne 'Privada' -or $prefix -lt 8 -or $prefix -gt 30){continue}
                $gateway=''
                if($cfg.IPv4DefaultGateway){$gateway=[string]$cfg.IPv4DefaultGateway.NextHop}
                $one=[pscustomobject]@{Name=[string]$cfg.InterfaceAlias;IPv4=$address;Prefix=$prefix;Gateway=$gateway;Index=[int]$cfg.InterfaceIndex;Display=([string]$cfg.InterfaceAlias+' | '+$address+'/'+$prefix)}
                $script:PInterfaces+=$one
                [void]$script:PInterface.Items.Add($one)
            }
        }
        $script:PInterface.DisplayMember='Display'
        if($script:PInterface.Items.Count){$script:PInterface.SelectedIndex=0}
        Set-PStatus ('Adaptadores privados: '+$script:PInterfaces.Count+'. Ningún paquete enviado.')
    }catch{Set-PStatus ('No se pudo consultar adaptadores: '+$_.Exception.Message)}
    finally{$script:PBusy=$false}
}
function Read-PTrusted {
    $script:PTrusted=@()
    $candidate=Join-Path $PSScriptRoot 'Red-Confiables.json'
    if(-not (Test-Path -LiteralPath $candidate -PathType Leaf)){
        $candidate=Join-Path (Join-Path $PSScriptRoot 'Reportes') 'Red-Confiables.json'
    }
    if(-not (Test-Path -LiteralPath $candidate -PathType Leaf)){return}
    try{
        $file=Get-Item -LiteralPath $candidate -Force -ErrorAction Stop
        if($file.Length -gt 524288){throw 'El catálogo de confianza supera 512 KB.'}
        $raw=Get-Content -LiteralPath $candidate -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $script:PTrusted=@($raw | Where-Object {$_ -and $_.IP} | Select-Object -First 500)
    }catch{Set-PStatus ('Lista de confianza no legible: '+$_.Exception.Message+'. No se bloqueará ningún dispositivo.')}
}
function Get-PConfidence([string]$IP,[string]$Mac){
    if(-not $script:PTrusted.Count){return 'Sin referencias del cliente'}
    $plain=([string]$Mac -replace '[^0-9a-fA-F]','').ToUpperInvariant()
    foreach($entry in $script:PTrusted){
        $saved=([string]$entry.MAC -replace '[^0-9a-fA-F]','').ToUpperInvariant()
        if([string]$entry.IP -eq $IP -and $plain.Length -eq 12 -and $saved -eq $plain){
            return ('Registrado: '+[string]$entry.Nombre)
        }
    }
    foreach($entry in $script:PTrusted){
        $saved=([string]$entry.MAC -replace '[^0-9a-fA-F]','').ToUpperInvariant()
        if($plain.Length -eq 12 -and $saved -eq $plain){return 'MAC conocida, IP diferente (revisar DHCP)'}
        if([string]$entry.IP -eq $IP -and $saved.Length -eq 12 -and $plain.Length -eq 12 -and $saved -ne $plain){return 'IP conocida, MAC diferente (revisar)'}
    }
    return 'No registrado: revisar con el responsable'
}
function Add-PDevice([string]$Address,[string]$Mac,[string]$Origin,[string]$State){
    if((Get-WCIPv4Scope $Address) -ne 'Privada'){return}
    $row=$null
    foreach($r in $script:PDevices.Rows){if([string]$r['IP'] -eq $Address){$row=$r;break}}
    if($null -eq $row){$row=$script:PDevices.NewRow()}
    $row['IP']=$Address
    if($Mac -and $Mac -match '^[0-9A-Fa-f]{2}([:-][0-9A-Fa-f]{2}){5}$'){$row['MAC']=$Mac}
    $row['Fabricante']=Get-WCProMacVendor ([string]$row['MAC']) $script:POui
    $row['Origen']=$Origin;$row['Estado']=$State
    $row['SO']='No determinado'
    $row['Confianza']=Get-PConfidence $Address ([string]$row['MAC'])
    if($row.RowState -eq [Data.DataRowState]::Detached){[void]$script:PDevices.Rows.Add($row)}
}
function Read-PPassive {
    $iface=Get-PInterface
    if($null -eq $iface -or $script:PBusy){return}
    $script:PBusy=$true
    try{
        $script:PDevices.Clear()
        Read-PTrusted
        $script:POui=Read-WCProOui (Join-Path $PSScriptRoot 'Configuracion\fabricantes-oui.csv')
        foreach($n in @(Get-NetNeighbor -InterfaceIndex ([int]$iface.Index) -AddressFamily IPv4 -ErrorAction Stop | Select-Object -First 512)){
            $ip=[string]$n.IPAddress
            if(-not (Test-WCProPrivateTarget $ip $iface)){continue}
            Add-PDevice $ip ([string]$n.LinkLayerAddress) 'Caché ARP' ([string]$n.State)
            if($script:PDevices.Rows.Count -ge 256){break}
        }
        Set-PStatus ('Equipos observados: '+$script:PDevices.Rows.Count+'. La caché ARP no es un inventario completo ni identifica el SO. No registrado NO significa intrusión.')
    }catch{Set-PStatus ('Lectura ARP parcial: '+$_.Exception.Message)}
    finally{$script:PBusy=$false}
}
function Invoke-PPings([string]$Address,[int]$Number,[int]$Timeout=750){
    $list=New-Object 'System.Collections.Generic.List[object]'
    $ping=New-Object Net.NetworkInformation.Ping
    try{
        for($i=0;$i -lt $Number;$i++){
            $ok=$false;$ms=[double]0
            try{
                $r=$ping.Send($Address,$Timeout)
                if([string]$r.Status -eq 'Success'){$ok=$true;$ms=[double]$r.RoundtripTime}
            }catch{}
            [void]$list.Add([pscustomobject]@{Success=$ok;Milliseconds=$ms})
            [Windows.Forms.Application]::DoEvents()
        }
    }finally{$ping.Dispose()}
    return @($list.ToArray())
}
function Run-PDiscovery {
    $iface=Get-PInterface
    if($null -eq $iface -or $script:PBusy){return}
    $targets=@(Get-WCLanProbeTargets $iface 16)
    if($targets.Count -eq 0){Set-PStatus 'No hay IP privadas autorizadas para esta interfaz.';return}
    if(-not (Confirm-PActive ('Se enviará un ping a un máximo de '+$targets.Count+' IPv4 privadas de '+$iface.IPv4+'/'+$iface.Prefix+'. No se escaneará toda la red.'))){return}
    $script:PBusy=$true
    try{
        Read-PTrusted
        $responded=0
        foreach($target in $targets){
            if(-not (Test-WCProPrivateTarget $target $iface)){continue}
            $ping=@(Invoke-PPings $target 1 700)
            if($ping.Count -eq 1 -and $ping[0].Success){
                Add-PDevice $target '' 'ICMP autorizado' 'Respondió ICMP'
                $responded++
            }
        }
        foreach($n in @(Get-NetNeighbor -InterfaceIndex ([int]$iface.Index) -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 512)){
            $ip=[string]$n.IPAddress
            if(Test-WCProPrivateTarget $ip $iface){
                Add-PDevice $ip ([string]$n.LinkLayerAddress) 'Caché ARP' ([string]$n.State)
                if($script:PDevices.Rows.Count -ge 256){break}
            }
        }
        Set-PStatus ('Descubrimiento finalizado: '+$targets.Count+' direcciones consultadas, '+$responded+' respuestas ICMP. No demuestra ausencia de otros equipos.')
    }catch{Set-PStatus ('Descubrimiento parcial: '+$_.Exception.Message)}
    finally{$script:PBusy=$false}
}
function Update-PMap {
    $script:PTree.BeginUpdate()
    try{
        $script:PTree.Nodes.Clear()
        $root=New-Object Windows.Forms.TreeNode('Topología lógica inferida (no representa enlaces físicos L2)')
        $iface=$script:PInterface.SelectedItem
        if($iface){
            $branch=New-Object Windows.Forms.TreeNode(([string]$iface.Name+' '+[string]$iface.IPv4+'/'+[string]$iface.Prefix))
            if($iface.Gateway){[void]$branch.Nodes.Add((New-Object Windows.Forms.TreeNode(('Gateway reportado: '+$iface.Gateway))))}
            foreach($r in $script:PDevices.Rows){
                $label=([string]$r['IP']+' | '+[string]$r['MAC']+' | '+[string]$r['Estado'])
                [void]$branch.Nodes.Add((New-Object Windows.Forms.TreeNode($label)))
            }
            [void]$root.Nodes.Add($branch)
        }else{[void]$root.Nodes.Add((New-Object Windows.Forms.TreeNode('Pulsa Analizar adaptadores antes de generar el mapa.')))}
        [void]$script:PTree.Nodes.Add($root)
        $script:PTree.ExpandAll()
        Set-PStatus 'Mapa lógico actualizado bajo demanda; los enlaces físicos requieren LLDP/SNMP con acceso autorizado.'
    }finally{$script:PTree.EndUpdate()}
}
function Run-PPerformance {
    $iface=Get-PInterface
    if($null -eq $iface -or $script:PBusy){return}
    $ip=([string]$script:PTarget.Text).Trim()
    if(-not $ip){$ip=[string]$iface.Gateway}
    if(-not (Test-WCProPrivateTarget $ip $iface)){Set-PStatus 'Rendimiento: escribe una IPv4 privada de la subred o usa el gateway.';return}
    if(-not (Confirm-PActive ('Se enviarán cinco pings al objetivo '+$ip+' para medir latencia, jitter estimado y pérdida.'))){return}
    $script:PBusy=$true
    try{
        $before=$null;$after=$null
        try{$before=Get-NetAdapterStatistics -Name ([string]$iface.Name) -ErrorAction Stop}catch{}
        $clock=[Diagnostics.Stopwatch]::StartNew()
        $sum=Get-WCProPingSummary @(Invoke-PPings $ip 5 800)
        $clock.Stop()
        try{$after=Get-NetAdapterStatistics -Name ([string]$iface.Name) -ErrorAction Stop}catch{}
        $lossLimit=20.0
        $value=[double]0
        if([double]::TryParse([string]$script:PLoss.Text,[ref]$value) -and $value -ge 0 -and $value -le 100){$lossLimit=$value}
        $state=Get-WCProSeverity $sum $lossLimit 150 40
        [void]$script:PMetrics.Rows.Add([object[]]@((Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$ip,([string]$sum.LossPct+'%'),([string]$sum.AverageMs+' ms'),([string]$sum.JitterMs+' ms'),$state))
        $bandwidth='Contadores de interfaz no disponibles'
        if($before -and $after -and $clock.Elapsed.TotalSeconds -gt 0.01){
            $rx=[double]$after.ReceivedBytes-[double]$before.ReceivedBytes
            $tx=[double]$after.SentBytes-[double]$before.SentBytes
            if($rx -ge 0 -and $tx -ge 0){
                $bandwidth=('Interfaz total: Rx {0} / Tx {1} Mbit/s' -f [math]::Round(($rx*8/$clock.Elapsed.TotalSeconds/1000000),2),[math]::Round(($tx*8/$clock.Elapsed.TotalSeconds/1000000),2))
            }
        }
        Set-PStatus ('Pérdida '+$sum.LossPct+'%; RTT '+$sum.AverageMs+' ms; jitter estimado '+$sum.JitterMs+' ms; '+$bandwidth+'. Muestra puntual, no SLA.')
    }catch{Set-PStatus ('Rendimiento no disponible: '+$_.Exception.Message)}
    finally{$script:PBusy=$false}
}
function Read-PFlows {
    $script:PFlows.Clear()
    try{
        $raw=@(Get-NetTCPConnection -ErrorAction Stop | Where-Object {$_.State -eq 'Established'} | Select-Object -First 5000)
        foreach($g in @($raw | Group-Object OwningProcess | Sort-Object Count -Descending | Select-Object -First 80)){
            $id=[int]$g.Name;$name='Desconocido'
            try{$name=[string](Get-Process -Id $id -ErrorAction Stop).ProcessName}catch{}
            $remote=@($g.Group | ForEach-Object {$_.RemoteAddress} | Select-Object -Unique)
            [void]$script:PFlows.Rows.Add([object[]]@($name,[string]$id,[string]$g.Count,[string]$remote.Count))
        }
        Set-PStatus 'Conexiones TCP agrupadas por proceso. Su cantidad NO refleja bytes consumidos por aplicación.'
    }catch{Set-PStatus ('No fue posible consultar procesos y TCP: '+$_.Exception.Message)}
}
function Read-PWifi([switch]$Nearby){
    if($Nearby -and -not (Confirm-PActive 'Windows explorará redes Wi-Fi cercanas, sin capturar claves ni paquetes.')){return}
    try{
        $exe=Join-Path $env:WINDIR 'System32\netsh.exe'
        if(-not (Test-Path -LiteralPath $exe -PathType Leaf)){throw 'netsh.exe no encontrado.'}
        $out=if($Nearby){& $exe wlan show networks mode=bssid 2>&1}else{& $exe wlan show interfaces 2>&1}
        $txt=[string]($out -join [Environment]::NewLine)
        $script:PWifi.Text=$txt.Substring(0,[math]::Min($txt.Length,15000))
        Set-PStatus 'Consulta Wi-Fi finalizada; Windows puede mostrar porcentaje de señal/canal, no SNR/interferencia fiable ni heatmap.'
    }catch{Set-PStatus ('No fue posible consultar Wi-Fi: '+$_.Exception.Message)}
}
function Run-PTool {
    $op=[string]$script:POperation.SelectedItem
    $target=([string]$script:PToolTarget.Text).Trim()
    $script:PToolOutput.Clear()
    if($op -eq 'Subred'){
        try{
            $prefix=0
            if(-not [int]::TryParse([string]$script:PPrefix.Text,[ref]$prefix)){throw 'Prefijo inválido'}
            $info=Get-WCProSubnetInfo $target $prefix
            $items=@('Red: '+$info.Network,'Máscara: '+$info.Mask,'Broadcast: '+$info.Broadcast,'Primer host: '+$info.FirstHost,'Último host: '+$info.LastHost,'Hosts utilizables: '+$info.TotalUsable)
            $script:PToolOutput.Text=$items -join [Environment]::NewLine
            Set-PStatus 'Subred calculada sin generar tráfico.'
        }catch{Set-PStatus $_.Exception.Message}
        return
    }
    $iface=Get-PInterface
    if($null -eq $iface -or $script:PBusy){return}
    if($op -eq 'DNS A'){
        if($target -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{0,250}[A-Za-z0-9]$'){Set-PStatus 'Dominio inválido.';return}
    }elseif(-not (Test-WCProPrivateTarget $target $iface)){
        Set-PStatus 'Las pruebas de puerto, ping y traceroute solo aceptan una IPv4 privada de la subred local seleccionada.';return
    }
    if(-not (Confirm-PActive ($op+' para '+$target+'. Se realizará una prueba puntual, no un escaneo masivo.'))){return}
    $script:PBusy=$true
    try{
        switch($op){
            'Ping' {
                $sum=Get-WCProPingSummary @(Invoke-PPings $target 3 900)
                $script:PToolOutput.Text=('Respuestas '+$sum.Received+'/'+$sum.Sent+' · Pérdida '+$sum.LossPct+'% · RTT '+$sum.AverageMs+' ms. Un fallo ICMP no significa equipo apagado.')
            }
            'DNS A' {
                $rr=@(Resolve-DnsName -Name $target -Type A -ErrorAction Stop | Where-Object {$_.IPAddress})
                $script:PToolOutput.Text=(@($rr|ForEach-Object {$_.IPAddress}) -join [Environment]::NewLine)
            }
            'Puerto TCP' {
                $port=[int]$script:PPort.SelectedItem
                if($port -notin @(22,53,80,443,445,554,3389,8000,8080)){throw 'Puerto no permitido.'}
                $client=New-Object Net.Sockets.TcpClient
                try{
                    $ar=$client.BeginConnect($target,$port,$null,$null)
                    try{
                        if($ar.AsyncWaitHandle.WaitOne(1000)){
                            try{$client.EndConnect($ar);$script:PToolOutput.Text='TCP accesible: no garantiza aplicación ni fabricante.'}
                            catch{$script:PToolOutput.Text='TCP rechazado.'}
                        }else{$script:PToolOutput.Text='TCP sin respuesta antes del límite.'}
                    }finally{$ar.AsyncWaitHandle.Close()}
                }finally{$client.Close()}
            }
            'Traceroute' {
                $list=New-Object 'System.Collections.Generic.List[string]'
                $ping=New-Object Net.NetworkInformation.Ping
                try{
                    for($ttl=1;$ttl -le 8;$ttl++){
                        $options=New-Object Net.NetworkInformation.PingOptions($ttl,$true)
                        try{
                            $reply=$ping.Send($target,850,([byte[]]@(0,1,2,3)),$options)
                            $hop=if($reply.Address){[string]$reply.Address}else{'*'}
                            [void]$list.Add(('{0}: {1} - {2}' -f $ttl,$hop,$reply.Status))
                            if([string]$reply.Status -eq 'Success'){break}
                        }catch{[void]$list.Add(('{0}: * / tiempo agotado' -f $ttl))}
                        [Windows.Forms.Application]::DoEvents()
                    }
                }finally{$ping.Dispose()}
                $script:PToolOutput.Text=$list -join [Environment]::NewLine
            }
        }
        Set-PStatus ($op+' completado. La respuesta no confirma identidad ni seguridad del equipo.')
    }catch{Set-PStatus ('Error '+$op+': '+$_.Exception.Message)}
    finally{$script:PBusy=$false}
}
function Read-PProtocols {
    $script:PProtocols.Clear()
    foreach($r in @(Get-WCProCapabilityMatrix)){
        [void]$script:PProtocols.Rows.Add([object[]]@($r.Protocolo,$r.Estado,$r.Detalle))
    }
    Set-PStatus 'Capacidades verificadas. SNMP, flows, Syslog, DPI y alertas remotas requieren integraciones dedicadas.'
}
function Get-PRows($Table){
    $list=@()
    foreach($row in $Table.Rows){
        $obj=[ordered]@{}
        foreach($column in $Table.Columns){$obj[[string]$column.ColumnName]=[string]$row[[string]$column.ColumnName]}
        $list += [pscustomobject]$obj
    }
    return $list
}
function Export-PReport {
    if($script:PDevices.Rows.Count+$script:PMetrics.Rows.Count+$script:PFlows.Rows.Count -eq 0){
        [void][Windows.Forms.MessageBox]::Show('Primero ejecuta al menos un análisis con resultados.','No hay datos','OK','Information')
        return
    }
    try{
        $base=Join-Path $PSScriptRoot 'Reportes'
        try{
            if(-not (Test-Path -LiteralPath $base)){[void](New-Item -Path $base -ItemType Directory -Force -ErrorAction Stop)}
            $probe=Join-Path $base ('.check-'+[guid]::NewGuid().ToString('N'))
            [IO.File]::WriteAllText($probe,'ok');Remove-Item -LiteralPath $probe -Force
        }catch{$base=Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WinCarePortable\Reportes'}
        $dir=Join-Path $base ('red-avanzada-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
        [void](New-Item -Path $dir -ItemType Directory -Force -ErrorAction Stop)
        $devices=@(Get-PRows $script:PDevices)
        $metrics=@(Get-PRows $script:PMetrics)
        $flows=@(Get-PRows $script:PFlows)
        $html=New-WCProHtmlReport -Devices $devices -Measurements $metrics -Applications $flows -Comment 'Informe de observaciones puntuales. No equivale a SLA mensual, topología física ni inventario completo.'
        [IO.File]::WriteAllText((Join-Path $dir 'informe.html'),$html,(New-Object Text.UTF8Encoding($true)))
        if($devices.Count){$devices|Export-Csv -LiteralPath (Join-Path $dir 'equipos.csv') -Encoding UTF8 -NoTypeInformation}
        if($metrics.Count){$metrics|Export-Csv -LiteralPath (Join-Path $dir 'metricas.csv') -Encoding UTF8 -NoTypeInformation}
        if($flows.Count){$flows|Export-Csv -LiteralPath (Join-Path $dir 'procesos.csv') -Encoding UTF8 -NoTypeInformation}
        Set-PStatus ('Reportes generados en '+$dir+'; no se enviaron por Internet.')
        [void][Windows.Forms.MessageBox]::Show('Informe HTML/CSV guardado. Para PDF abre informe.html e imprime con Microsoft Print to PDF. Los datos IP/MAC pueden ser sensibles.','Informe técnico','OK','Information')
    }catch{Set-PStatus ('Error al guardar informe: '+$_.Exception.Message)}
}
function Analyze-PSelected {
    if($script:PBusy){return}
    switch([string]$script:PTabs.SelectedTab.Text){
        'Red local' {Read-PPassive}
        'Topología' {Update-PMap}
        'Rendimiento' {Run-PPerformance}
        'Herramientas' {Run-PTool}
        'Wi-Fi' {Read-PWifi}
        'Aplicaciones' {Read-PFlows}
        'Protocolos' {Read-PProtocols}
    }
}
$script:PForm=New-Object Windows.Forms.Form
$script:PForm.Text='WinCare v2.1 | Redes avanzadas | Diseñado por DevPoderSEO'
$script:PForm.StartPosition='CenterParent'
$script:PForm.Size=New-Object Drawing.Size(1230,820)
$script:PForm.MinimumSize=New-Object Drawing.Size(1030,700)
$script:PForm.BackColor=$script:PBg;$script:PForm.ForeColor=$script:PText
$script:PForm.Font=New-Object Drawing.Font('Segoe UI',9)
$header=New-Object Windows.Forms.Label
$header.Text='Centro de redes · diagnósticos independientes'
$header.Font=New-Object Drawing.Font('Segoe UI Semibold',17,[Drawing.FontStyle]::Bold)
$header.Location=New-Object Drawing.Point(20,15);$header.Size=New-Object Drawing.Size(800,40)
$script:PForm.Controls.Add($header)
$brand=New-Object Windows.Forms.Label
$brand.Text='Diseñado por DevPoderSEO'
$brand.Location=New-Object Drawing.Point(885,24);$brand.Size=New-Object Drawing.Size(305,26)
$brand.ForeColor=$script:PBlue;$brand.Anchor='Top,Right';$brand.TextAlign='MiddleRight'
$script:PForm.Controls.Add($brand)
$description=New-Object Windows.Forms.Label
$description.Text='Ninguna prueba automática. Selecciona sección, pulsa Analizar y confirma antes de enviar tráfico.'
$description.Location=New-Object Drawing.Point(22,59);$description.Size=New-Object Drawing.Size(1150,24)
$script:PForm.Controls.Add($description)
function New-PButton([string]$Text,[int]$X,[int]$W,[scriptblock]$Action){
    $b=New-Object Windows.Forms.Button
    $b.Text=$Text;$b.Location=New-Object Drawing.Point($X,96);$b.Size=New-Object Drawing.Size($W,34)
    $b.BackColor=$script:PBlue;$b.ForeColor=[Drawing.Color]::White;$b.FlatStyle='Flat'
    $b.Add_Click($Action);$script:PForm.Controls.Add($b)
    return $b
}
$adapterButton=New-PButton 'Analizar adaptadores' 20 176 {Read-PAdapters}
$script:PInterface=New-Object Windows.Forms.ComboBox
$script:PInterface.Location=New-Object Drawing.Point(204,97);$script:PInterface.Size=New-Object Drawing.Size(318,30)
$script:PInterface.DropDownStyle='DropDownList';$script:PInterface.DisplayMember='Display'
$script:PForm.Controls.Add($script:PInterface)
$analyze=New-PButton 'Analizar pestaña' 530 165 {Analyze-PSelected}
$script:PConsent=New-Object Windows.Forms.CheckBox
$script:PConsent.Text='Tengo autorización para comprobar esta red'
$script:PConsent.Checked=$false
$script:PConsent.Location=New-Object Drawing.Point(703,96);$script:PConsent.Size=New-Object Drawing.Size(294,35)
$script:PConsent.ForeColor=$script:PWarn;$script:PForm.Controls.Add($script:PConsent)
$export=New-PButton 'Exportar informe' 1006 180 {Export-PReport}
$export.Anchor='Top,Right'
$script:PTabs=New-Object Windows.Forms.TabControl
$script:PTabs.Location=New-Object Drawing.Point(20,145)
$script:PTabs.Size=New-Object Drawing.Size(1171,557)
$script:PTabs.Anchor='Top,Bottom,Left,Right'
$script:PForm.Controls.Add($script:PTabs)
$pages=@{}
foreach($name in @('Red local','Topología','Rendimiento','Herramientas','Wi-Fi','Aplicaciones','Protocolos')){
    $page=New-Object Windows.Forms.TabPage
    $page.Text=$name;$page.BackColor=$script:PPanel
    [void]$script:PTabs.TabPages.Add($page);$pages[$name]=$page
}
$devicesGrid=New-PGrid $script:PDevices
$pages['Red local'].Controls.Add($devicesGrid)
$localBar=New-Object Windows.Forms.FlowLayoutPanel
$localBar.Dock='Top';$localBar.Height=49
$discovery=New-Object Windows.Forms.Button
$discovery.Text='Descubrir hasta 16 IP (autorizado)';$discovery.Size=New-Object Drawing.Size(290,35)
$discovery.Add_Click({Run-PDiscovery})
$localBar.Controls.Add($discovery)
$localNote=New-Object Windows.Forms.Label
$localNote.Text='ARP pasivo · OUI opcional · Confianza: comparación con Red-Confiables.json, NO detección de intrusión.'
$localNote.ForeColor=$script:PWarn;$localNote.Width=735;$localNote.Height=38
$localBar.Controls.Add($localNote)
$pages['Red local'].Controls.Add($localBar);$localBar.BringToFront()
$script:PTree=New-Object Windows.Forms.TreeView
$script:PTree.Dock='Fill';$script:PTree.Font=New-Object Drawing.Font('Segoe UI',11)
$script:PTree.BackColor=$script:PPanel;$script:PTree.ForeColor=$script:PText
$pages['Topología'].Controls.Add($script:PTree)
$topNote=New-Object Windows.Forms.Label
$topNote.Dock='Top';$topNote.Height=40;$topNote.ForeColor=$script:PWarn
$topNote.Text='Mapa lógico L3; no representa conexiones físicas ni estado de enlaces sin LLDP/SNMP.'
$pages['Topología'].Controls.Add($topNote);$topNote.BringToFront()
$metricGrid=New-PGrid $script:PMetrics
$pages['Rendimiento'].Controls.Add($metricGrid)
$metricBar=New-Object Windows.Forms.FlowLayoutPanel
$metricBar.Dock='Top';$metricBar.Height=53
$targetNote=New-Object Windows.Forms.Label
$targetNote.Text='Destino IP (vacío = gateway)';$targetNote.Width=175;$targetNote.Height=32;$metricBar.Controls.Add($targetNote)
$script:PTarget=New-Object Windows.Forms.TextBox
$script:PTarget.Width=190;$metricBar.Controls.Add($script:PTarget)
$lossNote=New-Object Windows.Forms.Label
$lossNote.Text='Alerta pérdida %';$lossNote.Width=125;$lossNote.Height=30;$metricBar.Controls.Add($lossNote)
$script:PLoss=New-Object Windows.Forms.TextBox
$script:PLoss.Text='20';$script:PLoss.Width=65;$metricBar.Controls.Add($script:PLoss)
$metricInfo=New-Object Windows.Forms.Label
$metricInfo.Text='5 pings por clic · jitter aproximado · estado orientativo, sin SLA continuo'
$metricInfo.Width=440;$metricInfo.Height=36;$metricInfo.ForeColor=$script:PWarn
$metricBar.Controls.Add($metricInfo)
$pages['Rendimiento'].Controls.Add($metricBar);$metricBar.BringToFront()
$script:PToolOutput=New-Object Windows.Forms.TextBox
$script:PToolOutput.Dock='Fill';$script:PToolOutput.Multiline=$true
$script:PToolOutput.ReadOnly=$true;$script:PToolOutput.ScrollBars='Both'
$script:PToolOutput.BackColor=$script:PPanel;$script:PToolOutput.ForeColor=$script:PText
$script:PToolOutput.Font=New-Object Drawing.Font('Consolas',11)
$pages['Herramientas'].Controls.Add($script:PToolOutput)
$toolBar=New-Object Windows.Forms.FlowLayoutPanel
$toolBar.Dock='Top';$toolBar.Height=55
$script:POperation=New-Object Windows.Forms.ComboBox
$script:POperation.DropDownStyle='DropDownList';$script:POperation.Width=185
$script:POperation.Items.AddRange([object[]]@('Ping','Traceroute','DNS A','Puerto TCP','Subred'))
$script:POperation.SelectedIndex=0;$toolBar.Controls.Add($script:POperation)
$script:PToolTarget=New-Object Windows.Forms.TextBox
$script:PToolTarget.Width=290;$toolBar.Controls.Add($script:PToolTarget)
$script:PPort=New-Object Windows.Forms.ComboBox
$script:PPort.DropDownStyle='DropDownList';$script:PPort.Width=115
$script:PPort.Items.AddRange([object[]]@('22','53','80','443','445','554','3389','8000','8080'))
$script:PPort.SelectedItem='443';$toolBar.Controls.Add($script:PPort)
$script:PPrefix=New-Object Windows.Forms.TextBox
$script:PPrefix.Text='24';$script:PPrefix.Width=65;$toolBar.Controls.Add($script:PPrefix)
$toolHint=New-Object Windows.Forms.Label
$toolHint.Text='IP o dominio · Puerto · Prefijo'
$toolHint.Width=300;$toolHint.Height=30;$toolBar.Controls.Add($toolHint)
$pages['Herramientas'].Controls.Add($toolBar);$toolBar.BringToFront()
$script:PWifi=New-Object Windows.Forms.TextBox
$script:PWifi.Dock='Fill';$script:PWifi.ReadOnly=$true;$script:PWifi.Multiline=$true
$script:PWifi.ScrollBars='Both';$script:PWifi.Font=New-Object Drawing.Font('Consolas',10)
$script:PWifi.BackColor=$script:PPanel;$script:PWifi.ForeColor=$script:PText
$pages['Wi-Fi'].Controls.Add($script:PWifi)
$wifiBar=New-Object Windows.Forms.FlowLayoutPanel
$wifiBar.Dock='Top';$wifiBar.Height=49
$near=New-Object Windows.Forms.Button
$near.Text='Explorar redes cercanas (permiso)'
$near.Size=New-Object Drawing.Size(265,35);$near.Add_Click({Read-PWifi -Nearby})
$wifiBar.Controls.Add($near)
$wifiDisclaimer=New-Object Windows.Forms.Label
$wifiDisclaimer.Text='Señal/canal disponibles según controlador; SNR, interferencia y mapa de calor requieren instrumentación.'
$wifiDisclaimer.Width=760;$wifiDisclaimer.Height=38;$wifiDisclaimer.ForeColor=$script:PWarn
$wifiBar.Controls.Add($wifiDisclaimer)
$pages['Wi-Fi'].Controls.Add($wifiBar);$wifiBar.BringToFront()
$flowGrid=New-PGrid $script:PFlows
$pages['Aplicaciones'].Controls.Add($flowGrid)
$flowNote=New-Object Windows.Forms.Label
$flowNote.Text='Conteo de conexiones TCP por PID: no mide ancho de banda por aplicación ni inspecciona contenido de paquetes.'
$flowNote.Dock='Top';$flowNote.Height=39;$flowNote.ForeColor=$script:PWarn
$pages['Aplicaciones'].Controls.Add($flowNote);$flowNote.BringToFront()
$protocolGrid=New-PGrid $script:PProtocols
$pages['Protocolos'].Controls.Add($protocolGrid)
$protocolNote=New-Object Windows.Forms.Label
$protocolNote.Dock='Top';$protocolNote.Height=38;$protocolNote.ForeColor=$script:PWarn
$protocolNote.Text='Matriz de capacidades: los colectores, sensores, SNMPv3, DPI, nube y alertas externas no están incluidos.'
$pages['Protocolos'].Controls.Add($protocolNote);$protocolNote.BringToFront()
$script:PStatus=New-Object Windows.Forms.Label
$script:PStatus.Location=New-Object Drawing.Point(23,715);$script:PStatus.Size=New-Object Drawing.Size(1162,42)
$script:PStatus.Anchor='Bottom,Left,Right'
$script:PStatus.ForeColor=$script:PWarn
$script:PStatus.Text='Sin analizar. Ninguna consulta ni prueba de red iniciada.'
$script:PForm.Controls.Add($script:PStatus)
if($SmokeTest){
    if($script:PTabs.TabPages.Count -ne 7 -or $script:PConsent.Checked){throw 'Pestañas incompletas o consentimiento activo por defecto.'}
    if($script:PDevices.Rows.Count -or $script:PMetrics.Rows.Count -or $script:PFlows.Rows.Count){throw 'Se ejecutó diagnóstico sin clic.'}
    if($devicesGrid.Columns.Count -ne 7){throw 'Falta estado de confianza del equipo.'}
    Write-Host 'OK: siete pestañas de redes avanzadas sin tráfico ni consultas automáticas.'
    $script:PForm.Dispose();return
}
if($SafetyTest){
    $iface=[pscustomobject]@{IPv4='192.168.5.25';Prefix=24;Gateway='192.168.5.1'}
    if(-not (Test-WCProPrivateTarget '192.168.5.10' $iface) -or (Test-WCProPrivateTarget '192.168.6.10' $iface) -or (Test-WCProPrivateTarget '1.1.1.1' $iface)){throw 'Validación de objetivo privado falló.'}
    $subnet=Get-WCProSubnetInfo '192.168.5.25' 24
    if($subnet.Network -ne '192.168.5.0' -or $subnet.TotalUsable -ne 254){throw 'Subred incorrecta.'}
    $metric=Get-WCProPingSummary @([pscustomobject]@{Success=$true;Milliseconds=10},[pscustomobject]@{Success=$false;Milliseconds=0},[pscustomobject]@{Success=$true;Milliseconds=20})
    if($metric.LossPct -ne 33.33 -or $metric.JitterMs -ne 10){throw 'Métricas incorrectas.'}
    $html=New-WCProHtmlReport -Devices @([pscustomobject]@{IP='<script>alert(1)</script>';MAC='';Fabricante='';Origen='';Estado='';SO=''}) -Measurements @() -Applications @() -Comment '<img src=x>'
    if($html -match '<script>alert' -or $html -notmatch '&lt;script&gt;' -or $html -match '<img src=x>'){throw 'HTML sin escape.'}
    Write-Host 'OK: alcance privado, subred, métricas y salida HTML validada sin hacer red.'
    $script:PForm.Dispose();return
}
$script:PForm.Add_Shown({Set-PStatus 'Sin analizar. Selecciona una sección y pulsa Analizar; primero analiza adaptadores para pruebas LAN.'})
try{
    if($Owner -is [Windows.Forms.IWin32Window]){[void]$script:PForm.ShowDialog($Owner)}
    else{[void]$script:PForm.ShowDialog()}
}finally{$script:PForm.Dispose()}
