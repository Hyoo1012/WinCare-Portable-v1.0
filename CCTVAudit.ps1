# WinCare Portable v1.8 - Diagnóstico CCTV / Cámara IP / NVR / DVR
# Diseñado por DevPoderSEO
# Inventario local sin credenciales. Cada ping y puerto requiere permiso explícito.
#requires -Version 5.1
param([object]$Owner,[switch]$SmokeTest,[switch]$SafetyTest)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'NetworkDiagnosticsCore.ps1')
. (Join-Path $PSScriptRoot 'CCTVCore.ps1')
$script:CColors=@{Bg=[Drawing.Color]::FromArgb(15,23,34);Panel=[Drawing.Color]::FromArgb(29,42,60);Accent=[Drawing.Color]::FromArgb(39,135,222);Text=[Drawing.Color]::FromArgb(240,246,252);Muted=[Drawing.Color]::FromArgb(176,191,207);Warning=[Drawing.Color]::FromArgb(250,190,106)}
$script:CDevices=@()
$script:CPath=''
$script:CLast=@()
$script:CInterfaces=@()
$script:CBusy=$false
$script:CSavedOK=$true
$script:CTable=New-Object System.Data.DataTable
foreach($c in @('Nombre','IP','Tipo','Puerto','Ubicación','Notas','Id')){[void]$script:CTable.Columns.Add($c,[string])}
$script:CResults=New-Object System.Data.DataTable
foreach($c in @('Fecha','Dispositivo','IP','Prueba','Resultado','Interpretación')){[void]$script:CResults.Columns.Add($c,[string])}

function Get-COutput {
    if(Get-Command Resolve-OutputDirectory -ErrorAction SilentlyContinue){return Resolve-OutputDirectory}
    $folder=Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WinCarePortable\Reportes'
    if(-not (Test-Path -LiteralPath $folder)){[void](New-Item -Path $folder -ItemType Directory -Force)}
    return $folder
}
function Write-CAudit([string]$Message){
    try {
        if(Get-Command Write-Audit -ErrorAction SilentlyContinue){Write-Audit ('CCTV: '+$Message);return}
        Add-Content -LiteralPath (Join-Path (Get-COutput) 'auditoria-cctv.txt') -Encoding UTF8 -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Message)
    }catch{}
}
function Add-CResult([string]$Device,[string]$IP,[string]$Test,[string]$Result,[string]$Detail){
    [void]$script:CResults.Rows.Add([object[]]@((Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Device,$IP,$Test,$Result,$Detail))
}
function Encode-CHtml($Value){return [Net.WebUtility]::HtmlEncode([string]$Value)}
function Build-CHtml([object[]]$Devices,[object[]]$Checks,[datetime]$Date){
    $sb=New-Object Text.StringBuilder
    [void]$sb.Append('<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Informe CCTV · WinCare DevPoderSEO</title><style>body{margin:0;background:#121e2d;color:#e9f2fc;font:14px Segoe UI,Arial,sans-serif}main{max-width:1050px;margin:28px auto;padding:25px}header{border-bottom:2px solid #379cf4}table{border-collapse:collapse;width:100%;margin:18px 0 25px;font-size:12px}th,td{border:1px solid #40546c;padding:9px;text-align:left;vertical-align:top;overflow-wrap:anywhere}th{background:#283f5a}.small{color:#b5c7db}@media print{body{background:white;color:#18273b}th{background:#eef3fa;color:#17253a}}</style></head><body><main>')
    [void]$sb.Append('<header><h1>Informe de diagnóstico CCTV / NVR / DVR</h1><p>Diseñado por DevPoderSEO · '+(Encode-CHtml $Date.ToString('yyyy-MM-dd HH:mm'))+'</p></header>')
    [void]$sb.Append('<p>Estado de red orientativo. Una respuesta ICMP o un puerto TCP disponible NO certifica identidad, grabación, imagen, ONVIF, RTSP, autenticación ni seguridad del dispositivo.</p><h2>Inventario del técnico</h2><table><tr><th>Nombre</th><th>IP</th><th>Tipo declarado</th><th>Puerto</th><th>Ubicación</th><th>Observaciones</th></tr>')
    foreach($d in @($Devices)){
        [void]$sb.Append('<tr><td>'+(Encode-CHtml $d.Nombre)+'</td><td>'+(Encode-CHtml $d.IP)+'</td><td>'+(Encode-CHtml $d.Tipo)+'</td><td>'+(Encode-CHtml $d.Puerto)+'</td><td>'+(Encode-CHtml $d.Ubicacion)+'</td><td>'+(Encode-CHtml $d.Notas)+'</td></tr>')
    }
    [void]$sb.Append('</table><h2>Pruebas consentidas</h2><table><tr><th>Fecha</th><th>Dispositivo</th><th>IP</th><th>Prueba</th><th>Resultado</th><th>Interpretación</th></tr>')
    foreach($r in @($Checks)){
        [void]$sb.Append('<tr><td>'+(Encode-CHtml $r.Fecha)+'</td><td>'+(Encode-CHtml $r.Dispositivo)+'</td><td>'+(Encode-CHtml $r.IP)+'</td><td>'+(Encode-CHtml $r.Prueba)+'</td><td>'+(Encode-CHtml $r.Resultado)+'</td><td>'+(Encode-CHtml $r.Interpretacion)+'</td></tr>')
    }
    [void]$sb.Append('</table><p class="small">Las IP, ubicaciones y nombres de equipos pueden ser sensibles. Este informe no incluye claves ni imágenes. No se contacta con servidores externos al generar el archivo.</p></main></body></html>')
    return $sb.ToString()
}
function Read-Catalog {
    $script:CPath=Get-CCTVConfigPath $PSScriptRoot -PreferWritable
    if(-not (Test-Path -LiteralPath $script:CPath -PathType Leaf)){
        $old=Get-CCTVConfigPath $PSScriptRoot
        if($old -ne $script:CPath -and (Test-Path -LiteralPath $old -PathType Leaf)){
            # No sobreescribir la configuración existente en un USB de solo lectura.
            $script:CDevices=@(Read-CCTVDevices $old)
            $script:CStatus.Text='Catálogo leído desde USB; cambios nuevos se guardarán en Documentos.'
            Refresh-CTable
            return
        }
    }
    $script:CDevices=@(Read-CCTVDevices $script:CPath)
    Refresh-CTable
}
function Refresh-CTable {
    $script:CTable.Clear()
    foreach($d in @($script:CDevices)){
        [void]$script:CTable.Rows.Add([object[]]@([string]$d.Nombre,[string]$d.IP,[string]$d.Tipo,[string]$d.Puerto,[string]$d.Ubicacion,[string]$d.Notas,[string]$d.Id))
    }
    $script:CCount.Text=('Equipos registrados: {0} · se guardan en catálogo local, sin contraseñas.' -f $script:CDevices.Count)
    Refresh-CMap
}
function Set-CEditor {
    if(-not $script:CGrid -or $script:CGrid.SelectedRows.Count -ne 1){return}
    $row=$script:CGrid.SelectedRows[0]
    if($row.IsNewRow){return}
    $script:CName.Text=[string]$row.Cells['Nombre'].Value
    $script:CIP.Text=[string]$row.Cells['IP'].Value
    $script:CRole.SelectedItem=[string]$row.Cells['Tipo'].Value
    $script:CPort.SelectedItem=[string]$row.Cells['Puerto'].Value
    $script:CSite.Text=[string]$row.Cells['Ubicación'].Value
    $script:CNotes.Text=[string]$row.Cells['Notas'].Value
    $script:CEditId=[string]$row.Cells['Id'].Value
}
function Clear-CEditor {
    $script:CEditId=''
    $script:CName.Clear();$script:CIP.Clear();$script:CSite.Clear();$script:CNotes.Clear()
    $script:CRole.SelectedIndex=0;$script:CPort.SelectedIndex=0
}
function Save-CEditor {
    if(-not $script:CSavedOK){return}
    try{
        $new=Assert-CCTVDevice ([pscustomobject]@{
            Id=$script:CEditId
            Nombre=$script:CName.Text
            IP=$script:CIP.Text
            Tipo=[string]$script:CRole.SelectedItem
            Puerto=[string]$script:CPort.SelectedItem
            Ubicacion=$script:CSite.Text
            Notas=$script:CNotes.Text
        })
        $copy=@()
        foreach($d in @($script:CDevices)){
            if($d.Id -ne $new.Id){$copy+=$d}
        }
        $copy+=$new
        Save-CCTVDevices -Devices $copy -Path $script:CPath
        $script:CDevices=$copy
        Refresh-CTable
        Clear-CEditor
        Write-CAudit ('Inventario CCTV guardado: '+$copy.Count+' dispositivos. Ninguna prueba de red.')
        $script:CStatus.Text='Equipo guardado. La identificación (tipo) fue declarada por el técnico, no detectada automáticamente.'
    }catch{
        [void][Windows.Forms.MessageBox]::Show(('No se pudo guardar equipo: '+$_.Exception.Message),'Validación de catálogo','OK','Warning')
    }
}
function Remove-CDevice {
    if(-not $script:CSavedOK -or $script:CGrid.SelectedRows.Count -ne 1){return}
    $row=$script:CGrid.SelectedRows[0]
    $id=[string]$row.Cells['Id'].Value
    $name=[string]$row.Cells['Nombre'].Value
    if([Windows.Forms.MessageBox]::Show(('Quitar '+$name+' del catálogo? Esto solo elimina el registro local, NO modifica el equipo ni la cámara.'),'Eliminar del inventario','YesNo','Question','Button2') -ne [Windows.Forms.DialogResult]::Yes){return}
    try{
        $new=@($script:CDevices | Where-Object {$_.Id -ne $id})
        Save-CCTVDevices -Devices $new -Path $script:CPath
        $script:CDevices=$new
        Refresh-CTable
        Clear-CEditor
        Write-CAudit ('Equipo borrado solo del catálogo: '+$name)
    }catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Error','OK','Warning')}
}
function Load-CInterfaces {
    $script:CInterfaces=@()
    $script:CInterface.Items.Clear()
    foreach($cfg in @(Get-NetIPConfiguration -ErrorAction Stop)){
        if(-not $cfg.NetAdapter -or [string]$cfg.NetAdapter.Status -ne 'Up'){continue}
        foreach($ip in @($cfg.IPv4Address)){
            if((Get-WCIPv4Scope ([string]$ip.IPAddress)) -ne 'Privada'){continue}
            if([int]$ip.PrefixLength -lt 8 -or [int]$ip.PrefixLength -gt 30){continue}
            $item=[pscustomobject]@{Name=[string]$cfg.InterfaceAlias;IPv4=[string]$ip.IPAddress;Prefix=[int]$ip.PrefixLength;Display=([string]$cfg.InterfaceAlias+' · '+[string]$ip.IPAddress+'/'+[string]$ip.PrefixLength)}
            $script:CInterfaces+=$item
            [void]$script:CInterface.Items.Add($item)
        }
    }
    $script:CInterface.DisplayMember='Display'
    if($script:CInterface.Items.Count){$script:CInterface.SelectedIndex=0}
}
function Refresh-CMap {
    if(-not $script:CTree){return}
    $script:CTree.BeginUpdate()
    try{
        $script:CTree.Nodes.Clear()
        $root=New-Object Windows.Forms.TreeNode('Inventario lógico CCTV · no representa conexiones físicas')
        foreach($type in $script:CCTVAllowedRoles){
            $group=@($script:CDevices | Where-Object {$_.Tipo -eq $type})
            if($group.Count -eq 0){continue}
            $branch=New-Object Windows.Forms.TreeNode(($type+' · '+$group.Count))
            foreach($device in $group){
                $label=([string]$device.Nombre+' | '+[string]$device.IP+' | '+[string]$device.Ubicacion)
                [void]$branch.Nodes.Add((New-Object Windows.Forms.TreeNode($label)))
            }
            [void]$root.Nodes.Add($branch)
        }
        if($root.Nodes.Count -eq 0){[void]$root.Nodes.Add((New-Object Windows.Forms.TreeNode('Agrega equipos desde Inventario para verlos aquí.')))}
        [void]$script:CTree.Nodes.Add($root)
        $script:CTree.ExpandAll()
    }finally{$script:CTree.EndUpdate()}
}
function Test-CTCP([string]$Address,[int]$Port,[int]$TimeoutMs=900){
    $client=New-Object Net.Sockets.TcpClient
    try{
        $async=$client.BeginConnect($Address,$Port,$null,$null)
        try{
            if(-not $async.AsyncWaitHandle.WaitOne($TimeoutMs)){return $false}
            $client.EndConnect($async)
            return $true
        }finally{$async.AsyncWaitHandle.Close()}
    }catch{return $false}
    finally{$client.Close()}
}
function Test-CICMP([string]$Address) {
    $ping=New-Object Net.NetworkInformation.Ping
    try{
        try {
            $r=$ping.Send($Address,900)
            return ([string]$r.Status -eq 'Success')
        }catch{return $false}
    }finally{$ping.Dispose()}
}
function Run-CInspection {
    if($script:CBusy){return}
    if(-not $script:CConsent.Checked){
        [void][Windows.Forms.MessageBox]::Show('Marca primero «Estoy autorizado a diagnosticar estos equipos CCTV» y confirma la prueba.','Falta autorización','OK','Information');return
    }
    if($script:CGrid.SelectedRows.Count -ne 1){
        [void][Windows.Forms.MessageBox]::Show('Selecciona exactamente un equipo registrado en Inventario.','Seleccionar dispositivo','OK','Information');return
    }
    $iface=$script:CInterface.SelectedItem
    $id=[string]$script:CGrid.SelectedRows[0].Cells['Id'].Value
    $device=@($script:CDevices | Where-Object {$_.Id -eq $id}|Select-Object -First 1)
    if($device.Count -ne 1 -or -not (Test-CCTVTarget $device[0] $iface)){
        [void][Windows.Forms.MessageBox]::Show('Solo se puede comprobar una IPv4 privada en la subred del adaptador activo seleccionado. Ningún paquete fue enviado.','Destino fuera de alcance','OK','Warning');return
    }
    $target=$device[0]
    $detail=('Se enviará un ping ICMP y se intentará una conexión TCP a '+$target.IP+':'+$target.Puerto+'.'+
        [Environment]::NewLine+'El servicio del equipo puede registrar el intento. No se comprobarán credenciales ni accederá a video.'+
        [Environment]::NewLine+'El tipo Cámara/NVR/DVR fue introducido por el técnico; WinCare no certifica su identidad.'+
        [Environment]::NewLine+'¿Confirmas la comprobación de este equipo autorizado?')
    if([Windows.Forms.MessageBox]::Show($detail,'Prueba CCTV autorizada','YesNo','Warning','Button2') -ne [Windows.Forms.DialogResult]::Yes){return}
    $script:CBusy=$true
    $script:CTest.Enabled=$false
    try{
        $icmp=Test-CICMP ([string]$target.IP)
        $icmpStatus=if($icmp){'Respuesta ICMP'}else{'Sin respuesta ICMP'}
        $explain=if($icmp){'Se recibió respuesta. No confirma que la cámara funcione o grabe.'}else{'Posibles causas: ICMP filtrado, falta de PoE/energía, VLAN, cable, equipo apagado o IP incorrecta.'}
        Add-CResult $target.Nombre $target.IP 'Conectividad ICMP' $icmpStatus $explain
        [Windows.Forms.Application]::DoEvents()
        $tcp=Test-CTCP ([string]$target.IP) ([int]$target.Puerto)
        $tcpStatus=if($tcp){'Puerto TCP accesible'}else{'No accesible en esta prueba'}
        $tcpExplain=if($tcp){'El puerto acepta TCP. No confirma imagen, grabación, ONVIF, RTSP ni fabricante.'}else{'Revisar firewall, servicio, switch, VLAN, protocolo y puerto configurado; no implica intrusión.'}
        Add-CResult $target.Nombre $target.IP ('Puerto TCP '+$target.Puerto) $tcpStatus $tcpExplain
        Write-CAudit ('Prueba autorizada equipo '+$target.Nombre+' IP='+$target.IP+' Puerto='+$target.Puerto+' Ping='+$icmp+' TCP='+$tcp)
        $script:CStatus.Text=('Prueba completada de '+$target.Nombre+'. Revisa los resultados; no se accedió al video ni se modificó el equipo.')
        $script:CTabs.SelectedIndex=1
    }finally{$script:CBusy=$false;$script:CTest.Enabled=$true}
}
function Export-CReport {
    try{
        $root=Get-COutput
        $dir=Join-Path $root ('cctv-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
        [void](New-Item -Path $dir -ItemType Directory -Force)
        $devices=@($script:CDevices)
        $rows=@(foreach($r in $script:CResults.Rows){
            [pscustomobject]@{Fecha=[string]$r['Fecha'];Dispositivo=[string]$r['Dispositivo'];IP=[string]$r['IP'];Prueba=[string]$r['Prueba'];Resultado=[string]$r['Resultado'];Interpretacion=[string]$r['Interpretación']}
        })
        $html=Build-CHtml -Devices $devices -Checks $rows -Date (Get-Date)
        [IO.File]::WriteAllText((Join-Path $dir 'informe-cctv.html'),$html,(New-Object Text.UTF8Encoding($true)))
        if($devices.Count){$devices|Export-Csv -LiteralPath (Join-Path $dir 'inventario.csv') -Encoding UTF8 -NoTypeInformation}
        if($rows.Count){$rows|Export-Csv -LiteralPath (Join-Path $dir 'pruebas-autorizadas.csv') -Encoding UTF8 -NoTypeInformation}
        Write-CAudit ('Informe exportado en '+$dir)
        [void][Windows.Forms.MessageBox]::Show(('Informe HTML y CSV guardados localmente en '+$dir),'Reporte CCTV','OK','Information')
        [void](Start-Process -FilePath (Join-Path $dir 'informe-cctv.html') -ErrorAction Stop)
    }catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'No fue posible exportar','OK','Warning')}
}
function New-CButton([string]$Title,[scriptblock]$Handler,$Parent,[int]$Width=185){
    $button=New-Object Windows.Forms.Button
    $button.Text=$Title;$button.Width=$Width;$button.Height=36;$button.Margin=New-Object Windows.Forms.Padding(5,5,5,5)
    $button.BackColor=$script:CColors.Accent;$button.ForeColor=[Drawing.Color]::White;$button.FlatStyle='Flat'
    $button.Add_Click($Handler);$Parent.Controls.Add($button)
    return $button
}
function New-CGrid($Table){
    $grid=New-Object Windows.Forms.DataGridView
    $grid.Dock='Fill';$grid.ReadOnly=$true
    $grid.AllowUserToAddRows=$false;$grid.AllowUserToDeleteRows=$false;$grid.RowHeadersVisible=$false
    $grid.AutoGenerateColumns=$false;$grid.SelectionMode='FullRowSelect';$grid.MultiSelect=$false
    $grid.AutoSizeColumnsMode='DisplayedCells';$grid.BackgroundColor=$script:CColors.Panel;$grid.EnableHeadersVisualStyles=$false
    $grid.ColumnHeadersDefaultCellStyle.BackColor=[Drawing.Color]::FromArgb(44,60,83)
    $grid.ColumnHeadersDefaultCellStyle.ForeColor=$script:CColors.Text
    $grid.DefaultCellStyle.BackColor=$script:CColors.Panel;$grid.DefaultCellStyle.ForeColor=$script:CColors.Text
    $grid.DefaultCellStyle.SelectionBackColor=[Drawing.Color]::FromArgb(42,106,175)
    $grid.DefaultCellStyle.SelectionForeColor=[Drawing.Color]::White
    foreach($dc in $Table.Columns){
        $c=New-Object Windows.Forms.DataGridViewTextBoxColumn
        $c.Name=[string]$dc.ColumnName;$c.DataPropertyName=$c.Name;$c.HeaderText=$c.Name
        if($c.Name -eq 'Id'){$c.Visible=$false}
        [void]$grid.Columns.Add($c)
    }
    $grid.DataSource=$Table.DefaultView
    return $grid
}

$script:CForm=New-Object Windows.Forms.Form
$script:CForm.Text='WinCare v1.8 | CCTV y seguridad electrónica | DevPoderSEO'
$script:CForm.StartPosition='CenterParent'
$script:CForm.Size=New-Object Drawing.Size(1230,835)
$script:CForm.MinimumSize=New-Object Drawing.Size(1060,720)
$script:CForm.BackColor=$script:CColors.Bg;$script:CForm.ForeColor=$script:CColors.Text
$script:CForm.Font=New-Object Drawing.Font('Segoe UI',9)
$header=New-Object Windows.Forms.Label
$header.Text='CCTV y redes de seguridad · v1.8'
$header.Location=New-Object Drawing.Point(20,14);$header.Size=New-Object Drawing.Size(855,38)
$header.Font=New-Object Drawing.Font('Segoe UI Semibold',18,[Drawing.FontStyle]::Bold)
$script:CForm.Controls.Add($header)
$brand=New-Object Windows.Forms.Label
$brand.Text='Diseñado por DevPoderSEO'
$brand.Location=New-Object Drawing.Point(889,24);$brand.Size=New-Object Drawing.Size(298,25)
$brand.Anchor='Top,Right';$brand.TextAlign='MiddleRight';$brand.ForeColor=$script:CColors.Accent
$script:CForm.Controls.Add($brand)
$sub=New-Object Windows.Forms.Label
$sub.Text='Inventario técnico local. Diagnóstico únicamente de dispositivos propios o autorizados; no se solicitan contraseñas ni video.'
$sub.Location=New-Object Drawing.Point(22,58);$sub.Size=New-Object Drawing.Size(1160,26)
$sub.ForeColor=$script:CColors.Muted;$script:CForm.Controls.Add($sub)
$script:CTabs=New-Object Windows.Forms.TabControl
$script:CTabs.Location=New-Object Drawing.Point(20,97);$script:CTabs.Size=New-Object Drawing.Size(1170,633)
$script:CTabs.Anchor='Top,Bottom,Left,Right'
$script:CForm.Controls.Add($script:CTabs)
$inventTab=New-Object Windows.Forms.TabPage
$inventTab.Text='Inventario CCTV';$inventTab.BackColor=$script:CColors.Panel
$testTab=New-Object Windows.Forms.TabPage
$testTab.Text='Pruebas autorizadas';$testTab.BackColor=$script:CColors.Panel
$mapTab=New-Object Windows.Forms.TabPage
$mapTab.Text='Mapa lógico';$mapTab.BackColor=$script:CColors.Panel
$reportTab=New-Object Windows.Forms.TabPage
$reportTab.Text='Informes';$reportTab.BackColor=$script:CColors.Panel
[void]$script:CTabs.TabPages.AddRange([Windows.Forms.TabPage[]]@($inventTab,$testTab,$mapTab,$reportTab))
$script:CGrid=New-CGrid $script:CTable
$script:CGrid.Dock='Top';$script:CGrid.Height=280;$script:CGrid.Anchor='Top,Left,Right'
$inventTab.Controls.Add($script:CGrid)
$script:CGrid.Add_SelectionChanged({Set-CEditor})
# Los campos se dibujan directamente sobre la pestaña: no crear un Panel Dock=Fill
# por encima del editor porque ocultaría etiquetas y formularios.
function Add-CLabel([string]$Text,[int]$X,[int]$Y,[int]$Width,$Parent){
    $l=New-Object Windows.Forms.Label
    $l.Text=$Text;$l.Location=New-Object Drawing.Point($X,$Y);$l.Size=New-Object Drawing.Size($Width,18)
    $l.ForeColor=$script:CColors.Muted;$Parent.Controls.Add($l)
}
Add-CLabel 'Nombre del equipo' 18 296 260 $inventTab
Add-CLabel 'IPv4 privada' 302 296 170 $inventTab
Add-CLabel 'Tipo declarado' 530 296 190 $inventTab
Add-CLabel 'Puerto técnico' 750 296 170 $inventTab
$script:CName=New-Object Windows.Forms.TextBox
$script:CName.Location=New-Object Drawing.Point(18,318);$script:CName.Size=New-Object Drawing.Size(270,27)
$inventTab.Controls.Add($script:CName)
$script:CIP=New-Object Windows.Forms.TextBox
$script:CIP.Location=New-Object Drawing.Point(300,318);$script:CIP.Size=New-Object Drawing.Size(213,27)
$inventTab.Controls.Add($script:CIP)
$script:CRole=New-Object Windows.Forms.ComboBox
$script:CRole.DropDownStyle='DropDownList'
$script:CRole.Location=New-Object Drawing.Point(525,318);$script:CRole.Size=New-Object Drawing.Size(210,27)
$script:CRole.Items.AddRange([object[]]$script:CCTVAllowedRoles);$script:CRole.SelectedIndex=0
$inventTab.Controls.Add($script:CRole)
$script:CPort=New-Object Windows.Forms.ComboBox
$script:CPort.DropDownStyle='DropDownList'
$script:CPort.Location=New-Object Drawing.Point(748,318);$script:CPort.Size=New-Object Drawing.Size(150,27)
$script:CPort.Items.AddRange([object[]]@('80','443','554','8000','8080','8899'));$script:CPort.SelectedIndex=0
$inventTab.Controls.Add($script:CPort)
Add-CLabel 'Ubicación / sector (opcional)' 18 360 320 $inventTab
$script:CSite=New-Object Windows.Forms.TextBox
$script:CSite.Location=New-Object Drawing.Point(18,382);$script:CSite.Size=New-Object Drawing.Size(410,27)
$inventTab.Controls.Add($script:CSite)
Add-CLabel 'Observaciones sin contraseñas' 445 360 420 $inventTab
$script:CNotes=New-Object Windows.Forms.TextBox
$script:CNotes.Location=New-Object Drawing.Point(445,382);$script:CNotes.Size=New-Object Drawing.Size(630,27)
$script:CNotes.Anchor='Top,Left,Right'
$inventTab.Controls.Add($script:CNotes)
$actions=New-Object Windows.Forms.FlowLayoutPanel
$actions.Location=New-Object Drawing.Point(16,430);$actions.Size=New-Object Drawing.Size(1060,49)
$actions.Anchor='Top,Left,Right'
$inventTab.Controls.Add($actions)
[void](New-CButton 'Nuevo / limpiar ficha' {Clear-CEditor} $actions 205)
[void](New-CButton 'Guardar equipo' {Save-CEditor} $actions 185)
[void](New-CButton 'Quitar del inventario' {Remove-CDevice} $actions 220)
$script:CCount=New-Object Windows.Forms.Label
$script:CCount.Text='Sin equipos registrados.'
$script:CCount.Location=New-Object Drawing.Point(20,503);$script:CCount.Size=New-Object Drawing.Size(1010,32)
$script:CCount.ForeColor=$script:CColors.Muted;$inventTab.Controls.Add($script:CCount)

$testTitle=New-Object Windows.Forms.Label
$testTitle.Text='Verificación limitada de equipos CCTV registrados'
$testTitle.Location=New-Object Drawing.Point(24,20);$testTitle.Size=New-Object Drawing.Size(1080,32)
$testTitle.Font=New-Object Drawing.Font('Segoe UI Semibold',15,[Drawing.FontStyle]::Bold)
$testTab.Controls.Add($testTitle)
$testHint=New-Object Windows.Forms.Label
$testHint.Text='Selecciona primero una cámara/NVR del Inventario y un adaptador local privado. Cada ejecución prueba solo un equipo y un puerto.'+
    [Environment]::NewLine+'No prueba ONVIF, no lee imágenes, no comprueba contraseñas y no modifica cámaras ni grabadores.'
$testHint.Location=New-Object Drawing.Point(25,58);$testHint.Size=New-Object Drawing.Size(1080,55)
$testHint.ForeColor=$script:CColors.Muted;$testTab.Controls.Add($testHint)
$script:CInterface=New-Object Windows.Forms.ComboBox
$script:CInterface.DisplayMember='Display';$script:CInterface.DropDownStyle='DropDownList'
$script:CInterface.Location=New-Object Drawing.Point(25,118);$script:CInterface.Size=New-Object Drawing.Size(405,30)
$testTab.Controls.Add($script:CInterface)
$script:CConsent=New-Object Windows.Forms.CheckBox
$script:CConsent.Text='Estoy autorizado a diagnosticar estos equipos CCTV'
$script:CConsent.Checked=$false
$script:CConsent.Location=New-Object Drawing.Point(446,116);$script:CConsent.Size=New-Object Drawing.Size(450,33)
$script:CConsent.ForeColor=$script:CColors.Warning;$testTab.Controls.Add($script:CConsent)
$testBar=New-Object Windows.Forms.FlowLayoutPanel
$testBar.Location=New-Object Drawing.Point(22,158);$testBar.Size=New-Object Drawing.Size(1050,50)
$testTab.Controls.Add($testBar)
[void](New-CButton 'Actualizar adaptadores' {try{Load-CInterfaces}catch{$script:CStatus.Text=$_.Exception.Message}} $testBar 222)
$script:CTest=New-CButton 'Probar el equipo seleccionado' {Run-CInspection} $testBar 270
$script:CCheckGrid=New-CGrid $script:CResults
$script:CCheckGrid.Location=New-Object Drawing.Point(21,225);$script:CCheckGrid.Size=New-Object Drawing.Size(1080,345)
$script:CCheckGrid.Dock='None';$script:CCheckGrid.Anchor='Top,Bottom,Left,Right'
$testTab.Controls.Add($script:CCheckGrid)
$checkFooter=New-Object Windows.Forms.Label
$checkFooter.Text='Si el ping falla, puede existir un bloqueo ICMP. Si TCP falla, revisa VLAN, PoE, switch, firewall y servicio; evita deducciones precipitadas.'
$checkFooter.Location=New-Object Drawing.Point(23,574);$checkFooter.Size=New-Object Drawing.Size(1060,40)
$checkFooter.Anchor='Bottom,Left,Right'
$checkFooter.ForeColor=$script:CColors.Warning
$testTab.Controls.Add($checkFooter)

$script:CTree=New-Object Windows.Forms.TreeView
$script:CTree.Dock='Fill'
$script:CTree.BackColor=$script:CColors.Panel;$script:CTree.ForeColor=$script:CColors.Text
$script:CTree.Font=New-Object Drawing.Font('Segoe UI',11)
$mapTab.Controls.Add($script:CTree)

$reportHeading=New-Object Windows.Forms.Label
$reportHeading.Text='Informes técnicos de CCTV'
$reportHeading.Location=New-Object Drawing.Point(32,28);$reportHeading.Size=New-Object Drawing.Size(1060,40)
$reportHeading.Font=New-Object Drawing.Font('Segoe UI Semibold',17,[Drawing.FontStyle]::Bold)
$reportTab.Controls.Add($reportHeading)
$reportHelp=New-Object Windows.Forms.Label
$reportHelp.Text='Genera un informe HTML imprimible y archivos CSV del inventario y de las pruebas que tú hayas autorizado.'+
    [Environment]::NewLine+'Incluye IP, nombres y ubicaciones. Revisa la privacidad y permisos del cliente antes de compartir.'+
    [Environment]::NewLine+'No incluye video, credenciales ni grabaciones.'
$reportHelp.Location=New-Object Drawing.Point(34,84);$reportHelp.Size=New-Object Drawing.Size(1030,100)
$reportHelp.ForeColor=$script:CColors.Muted;$reportTab.Controls.Add($reportHelp)
$exportPanel=New-Object Windows.Forms.FlowLayoutPanel
$exportPanel.Location=New-Object Drawing.Point(29,194);$exportPanel.Size=New-Object Drawing.Size(900,52)
$reportTab.Controls.Add($exportPanel)
[void](New-CButton 'Exportar HTML / CSV' {Export-CReport} $exportPanel 235)
$privacy=New-Object Windows.Forms.Label
$privacy.Text='Una respuesta de puerto NO certifica que RTSP, ONVIF o grabación funcionen. Para validarlo, utiliza las herramientas autorizadas del fabricante.'
$privacy.Location=New-Object Drawing.Point(34,270);$privacy.Size=New-Object Drawing.Size(1030,70)
$privacy.ForeColor=$script:CColors.Warning;$reportTab.Controls.Add($privacy)

$script:CStatus=New-Object Windows.Forms.Label
$script:CStatus.Text='Sin pruebas activas. Agrega dispositivos en Inventario.'
$script:CStatus.Location=New-Object Drawing.Point(21,747);$script:CStatus.Size=New-Object Drawing.Size(1160,30)
$script:CStatus.Anchor='Bottom,Left,Right'
$script:CStatus.ForeColor=$script:CColors.Muted;$script:CForm.Controls.Add($script:CStatus)
$script:CEditId=''
if($SmokeTest){
    if($script:CTabs.TabPages.Count -ne 4 -or $script:CGrid.Columns.Count -ne 7 -or $script:CCheckGrid.Columns.Count -ne 6){throw 'Pantallas CCTV incompletas.'}
    if($script:CConsent.Checked){throw 'Autorización no puede estar marcada al inicio.'}
    if($script:CResults.Rows.Count -gt 0){throw 'SmokeTest no puede enviar pings ni leer dispositivos.'}
    Write-Host 'OK: CCTV v1.8 construye 4 pestañas, catálogo y pruebas desactivadas.'
    $script:CForm.Dispose();return
}
if($SafetyTest){
    $tmp=Join-Path ([IO.Path]::GetTempPath()) ('wincare-cctv-'+[guid]::NewGuid().ToString('N'))
    [void](New-Item -Path $tmp -ItemType Directory -Force)
    try{
        $one=Assert-CCTVDevice ([pscustomobject]@{Id='';Nombre='NVR prueba';IP='192.168.50.20';Tipo='NVR';Puerto=554;Ubicacion='Bodega';Notas='Sin claves'})
        $path=Join-Path $tmp 'cctv.json'
        Save-CCTVDevices -Devices @($one) -Path $path
        $read=@(Read-CCTVDevices $path)
        if($read.Count -ne 1){throw 'Catálogo no persistió.'}
        $iface=[pscustomobject]@{IPv4='192.168.50.25';Prefix=24}
        if(-not (Test-CCTVTarget $read[0] $iface)){throw 'Bloqueó un equipo dentro de subred.'}
        if(Test-CCTVTarget $read[0] ([pscustomobject]@{IPv4='192.168.40.25';Prefix=24})){throw 'Permitió dispositivo fuera de subred.'}
        $blocked=$false
        try{[void](Assert-CCTVDevice ([pscustomobject]@{Nombre='Prueba';IP='1.1.1.1';Tipo='NVR';Puerto=554;Ubicacion='';Notas=''}))}catch{$blocked=$true}
        if(-not $blocked){throw 'Permitió IP pública.'}
        $secret=$false
        try{[void](Assert-CCTVDevice ([pscustomobject]@{Nombre='Prueba';IP='192.168.50.2';Tipo='NVR';Puerto=554;Ubicacion='';Notas='password=12345'}))}catch{$secret=$true}
        if(-not $secret){throw 'Permitió contraseña explícita en notas.'}
        $html=Build-CHtml -Devices @([pscustomobject]@{Nombre='<script>x</script>';IP='192.168.1.3';Tipo='NVR';Puerto=554;Ubicacion='A';Notas='&'}) -Checks @() -Date (Get-Date)
        if($html -match '<script>x' -or $html -notmatch '&lt;script&gt;'){throw 'No codificó HTML.'}
        Write-Host 'OK: inventario JSON aislado, LAN privada, IP externa bloqueada, secretos rechazados y HTML seguro. CERO conexiones.'
    }finally{
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        $script:CForm.Dispose()
    }
    return
}
$script:CForm.Add_Shown({
    try{
        Read-Catalog
        Load-CInterfaces
    }catch{
        $script:CSavedOK=$false
        $script:CStatus.Text='No se pudo leer el catálogo o la configuración de red: '+$_.Exception.Message
        [void][Windows.Forms.MessageBox]::Show(('No se modificó el catálogo. Verifica el archivo original antes de continuar: '+$_.Exception.Message),'Revisión de configuración','OK','Warning')
    }
})
try{
    if($Owner -is [Windows.Forms.IWin32Window]){[void]$script:CForm.ShowDialog($Owner)}
    else{[void]$script:CForm.ShowDialog()}
}finally{$script:CForm.Dispose()}
