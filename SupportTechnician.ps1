# WinCare Portable v1.7 - Soporte y reparaciones
# Diseñado por DevPoderSEO | Windows PowerShell 5.1 | Sin acciones automáticas
#requires -Version 5.1
param([object]$Owner,[switch]$SmokeTest,[switch]$SafetyTest)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$script:SColors=@{Bg=[Drawing.Color]::FromArgb(16,24,35);Panel=[Drawing.Color]::FromArgb(29,41,59);Text=[Drawing.Color]::FromArgb(240,245,251);Muted=[Drawing.Color]::FromArgb(179,191,208);Accent=[Drawing.Color]::FromArgb(41,132,212);Warning=[Drawing.Color]::FromArgb(248,193,113)}
$script:SPrinters=New-Object System.Data.DataTable
foreach($c in @('Nombre','Estado','Tipo','Detalle','Recomendación')){[void]$script:SPrinters.Columns.Add($c,[string])}
$script:SEvents=New-Object System.Data.DataTable
foreach($c in @('Fecha','Evento','Proveedor','Nivel','Resumen','Recomendación')){[void]$script:SEvents.Columns.Add($c,[string])}
$script:SStartup=New-Object System.Data.DataTable
foreach($c in @('Nombre','Ubicación','Usuario','Comando','Observación')){[void]$script:SStartup.Columns.Add($c,[string])}

function Add-SPrinter([string]$Name,[string]$Status,[string]$Kind,[string]$Detail,[string]$Advice){
    [void]$script:SPrinters.Rows.Add([object[]]@($Name,$Status,$Kind,$Detail,$Advice))
}
function Add-SEvent([string]$Date,[string]$Event,[string]$Provider,[string]$Level,[string]$Detail,[string]$Advice){
    [void]$script:SEvents.Rows.Add([object[]]@($Date,$Event,$Provider,$Level,$Detail,$Advice))
}
function Get-SReports {
    if(Get-Command Resolve-OutputDirectory -ErrorAction SilentlyContinue){return Resolve-OutputDirectory}
    $folder=Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WinCarePortable\Reportes'
    if(-not (Test-Path -LiteralPath $folder)){[void](New-Item -Path $folder -ItemType Directory -Force)}
    return $folder
}
function Write-SAudit([string]$Message){
    try {
        if(Get-Command Write-Audit -ErrorAction SilentlyContinue){Write-Audit ('SOPORTE: '+$Message);return}
        Add-Content -LiteralPath (Join-Path (Get-SReports) 'auditoria-soporte.txt') -Encoding UTF8 -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Message)
    }catch{}
}
function Test-SAdmin {
    $p=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Encode-SHtml($Value){return [Net.WebUtility]::HtmlEncode([string]$Value)}
function Test-SBackupTarget([string]$Path,[string]$WindowsPath){
    if([string]::IsNullOrWhiteSpace($Path)){return $false}
    try {
        $p=[IO.Path]::GetFullPath($Path).TrimEnd('\')
        $w=[IO.Path]::GetFullPath($WindowsPath).TrimEnd('\')
        if([string]::Equals($p,$w,[StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith(($w+'\'),[StringComparison]::OrdinalIgnoreCase)){return $false}
        $item=Get-Item -LiteralPath $p -Force -ErrorAction Stop
        if($item -isnot [IO.DirectoryInfo]){return $false}
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $false}
        return $true
    }catch{return $false}
}
function Read-SPrinters {
    $script:SPrinters.Clear()
    try{
        $svc=Get-Service -Name Spooler -ErrorAction Stop
        Add-SPrinter 'Cola de impresión (Spooler)' ([string]$svc.Status) 'Servicio Windows' ('Inicio: '+[string]$svc.StartType) 'Si no imprime, revisa el servicio y los errores. No borres la cola sin autorización.'
    }catch{Add-SPrinter 'Cola de impresión' 'No verificable' 'Servicio Windows' $_.Exception.Message 'En algunos equipos el servicio está deshabilitado por diseño.'}
    try {
        $printers=@(Get-Printer -ErrorAction Stop)
        if($printers.Count -eq 0){Add-SPrinter 'Impresoras detectadas' 'Ninguna' 'Inventario' '' 'Comprueba drivers, conexión USB/red y la configuración de Windows.'}
        foreach($printer in $printers){
            $name=[string]$printer.Name
            $status=[string]$printer.PrinterStatus
            $detail='Controlador: '+[string]$printer.DriverName+'; Puerto: '+[string]$printer.PortName
            $advice='El estado reportado no garantiza funcionamiento; prueba una página de prueba solo con el cliente presente.'
            Add-SPrinter $name $status 'Impresora' $detail $advice
            try{
                $jobs=@(Get-PrintJob -PrinterName $name -ErrorAction Stop)
                if($jobs.Count -gt 0){Add-SPrinter ($name+' · trabajos') ([string]$jobs.Count) 'Cola' 'Existen trabajos de impresión pendientes.' 'Revisa antes de reiniciar el servicio. No se eliminarán los documentos.'}
            }catch {
                Add-SPrinter ($name+' · trabajos') 'No disponibles' 'Cola' $_.Exception.Message 'Algunas colas requieren permisos o están desconectadas.'
            }
        }
    }catch{Add-SPrinter 'Inventario de impresoras' 'No disponible' 'Información' $_.Exception.Message 'Revisa permisos y los cmdlets de administración de impresión.'}
    $script:SStatus.Text=('{0} observaciones de impresión. No se cambió la cola.' -f $script:SPrinters.Rows.Count)
}
function Read-SEvents {
    $script:SEvents.Clear()
    $ids=@(41,6008,1001,7000,7001,7009,7023,7031,7034)
    try{
        $filter=@{LogName='System';Id=$ids;StartTime=(Get-Date).AddDays(-14)}
        foreach($evt in @(Get-WinEvent -FilterHashtable $filter -MaxEvents 80 -ErrorAction Stop)){
            $summary=([string]$evt.Message) -replace '\s+',' '
            if($summary.Length -gt 230){$summary=$summary.Substring(0,230)+'...'}
            $suggestion=if($evt.Id -in @(41,6008)){'Apagado inesperado; revisar energía, temperatura y registro anterior. No confirmar causa sin pruebas.'}
                        elseif($evt.Id -eq 1001){'Evento de error/volcado; revisar origen, fecha, controladores y soporte del fabricante.'}
                        else{'Servicio con incidente histórico. Revisar dependencia, errores anteriores y estado actual.'}
            Add-SEvent (([datetime]$evt.TimeCreated).ToString('yyyy-MM-dd HH:mm')) ([string]$evt.Id) ([string]$evt.ProviderName) ([string]$evt.LevelDisplayName) $summary $suggestion
        }
    }catch{
        Add-SEvent (Get-Date -Format 'yyyy-MM-dd HH:mm') 'Sin resultados' 'Windows Event Log' 'Información' $_.Exception.Message 'Sin eventos coincidentes o sin permisos. No significa que el equipo esté libre de fallos.'
    }
    $script:SStatus.Text=('Eventos históricos consultados: '+$script:SEvents.Rows.Count+'. No se ha reparado nada.')
}
function Read-SStartup {
    $script:SStartup.Clear()
    try{
        $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        if($os.LastBootUpTime){
            $boot=([datetime]$os.LastBootUpTime).ToString('yyyy-MM-dd HH:mm')
            [void]$script:SStartup.Rows.Add([object[]]@('Último arranque de Windows','Sistema','','',$boot+' · Referencia de estabilidad, no determina una falla.'))
        }
    }catch{
        [void]$script:SStartup.Rows.Add([object[]]@('Arranque no verificable','Sistema','','',('No se pudo consultar: '+$_.Exception.Message)))
    }
    foreach($name in @('Spooler','wuauserv','BITS','Dhcp','Dnscache','EventLog','LanmanWorkstation')){
        try {
            $svc=Get-Service -Name $name -ErrorAction Stop
            $detail='Estado: '+[string]$svc.Status+'; Inicio: '+[string]$svc.StartType
            [void]$script:SStartup.Rows.Add([object[]]@($svc.DisplayName,'Servicio Windows','',$detail,'Algunos servicios se inician bajo demanda. No los deshabilites sin conocer su dependencia.'))
        }catch{
            [void]$script:SStartup.Rows.Add([object[]]@($name,'Servicio Windows','','No verificable','Puede estar ausente o restringido por el sistema.'))
        }
    }
    try{
        foreach($entry in @(Get-CimInstance Win32_StartupCommand -ErrorAction Stop | Select-Object -First 200)){
            [void]$script:SStartup.Rows.Add([object[]]@([string]$entry.Name,[string]$entry.Location,[string]$entry.User,[string]$entry.Command,'Entrada registrada, no necesariamente activa o maliciosa.'))
        }
    }catch {
        [void]$script:SStartup.Rows.Add([object[]]@('Consulta de inicio parcial','','','',('No fue posible consultar: '+$_.Exception.Message)))
    }
    $script:SStatus.Text=('Observaciones de arranque, servicios e inicio: '+$script:SStartup.Rows.Count+'. No se modificó nada.')
}
function Open-STool([string]$Type){
    $apps=@{
        'Printers'=@('control.exe','printers')
        'Services'=@('mmc.exe','services.msc')
        'Events'=@('mmc.exe','eventvwr.msc')
        'Startup'=@('taskmgr.exe','')
    }
    if(-not $apps.ContainsKey($Type)){return}
    if($Type -eq 'Services'){
        if([Windows.Forms.MessageBox]::Show('La consola Servicios permite modificar el sistema. WinCare solo la abrirá y no alterará servicios. ¿Continuar?','Acceso a Servicios','YesNo','Warning','Button2') -ne [Windows.Forms.DialogResult]::Yes){return}
    }
    try {
        $exe=Join-Path $env:WINDIR ('System32\'+[string]$apps[$Type][0])
        if(-not (Test-Path -LiteralPath $exe)){throw 'Herramienta de Windows no disponible.'}
        $args=[string]$apps[$Type][1]
        if($args){[void](Start-Process -FilePath $exe -ArgumentList $args -ErrorAction Stop)}
        else{[void](Start-Process -FilePath $exe -ErrorAction Stop)}
    }catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Herramienta no disponible','OK','Warning')}
}
function Restart-SSpooler {
    if(-not (Test-SAdmin)){
        [void][Windows.Forms.MessageBox]::Show('Reiniciar Spooler requiere permisos de administrador. Usa Solicitar permisos en WinCare y repite la operación.','Permisos necesarios','OK','Information');return
    }
    $warning='Se detendrá y volverá a iniciar el servicio Cola de impresión. Podría interrumpir los trabajos de impresión o provocar reenvíos.'+
       [Environment]::NewLine+'NO se borrarán los archivos de la cola ni los controladores.'+
       [Environment]::NewLine+'Confirma que el cliente autorizó la interrupción. ¿Continuar?'
    if([Windows.Forms.MessageBox]::Show($warning,'Reiniciar cola de impresión','YesNo','Warning','Button2') -ne [Windows.Forms.DialogResult]::Yes){return}
    if([Windows.Forms.MessageBox]::Show('Segunda confirmación: ¿reiniciar el servicio Spooler ahora?','Confirmar intervención','YesNo','Warning','Button2') -ne [Windows.Forms.DialogResult]::Yes){return}
    try{
        $svc=Get-Service -Name Spooler -ErrorAction Stop
        if($svc.Status -eq 'Running'){Restart-Service -Name Spooler -ErrorAction Stop}
        else{Start-Service -Name Spooler -ErrorAction Stop}
        Write-SAudit 'Se solicitó reinicio/inicio de Spooler con doble consentimiento.'
        [void][Windows.Forms.MessageBox]::Show('Windows aceptó la operación sobre Spooler. Revisa la cola e imprime una página de prueba si corresponde.','Acción solicitada','OK','Information')
        Read-SPrinters
    }catch{
        Write-SAudit ('Error Spooler: '+$_.Exception.Message)
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'No fue posible reiniciar Spooler','OK','Warning')
    }
}
function Build-SIncidentHtml([object[]]$Events,[object[]]$Printers,[string]$Client,[string]$Ticket,[string]$Issue,[string]$Action,[string]$Result){
    $sb=New-Object Text.StringBuilder
    [void]$sb.Append('<!doctype html><html lang="es"><head><meta charset="utf-8"><title>WinCare · Orden de soporte</title>')
    [void]$sb.Append('<style>body{font:14px Segoe UI,Arial,sans-serif;background:#121c2c;color:#e8f1fc}main{max-width:1000px;margin:28px auto;padding:25px}header{border-bottom:2px solid #379be8}section{background:#23344a;padding:14px;margin:16px 0;border-radius:11px;white-space:pre-wrap}table{border-collapse:collapse;width:100%;font-size:12px}th,td{border:1px solid #44566b;text-align:left;padding:8px;vertical-align:top;overflow-wrap:anywhere}@media print{body{background:white;color:#172538}section{background:#f3f6fa}th,td{border-color:#bbb}}</style></head><body><main><header><h1>Registro técnico de intervención</h1><p>Diseñado por DevPoderSEO · '+(Get-Date -Format 'yyyy-MM-dd HH:mm')+'</p></header>')
    foreach($field in @(@('Cliente',$Client),@('Orden / ticket',$Ticket),@('Problema reportado',$Issue),@('Acciones realizadas',$Action),@('Resultado y siguientes pasos',$Result))){
        [void]$sb.Append('<section><strong>'+(Encode-SHtml $field[0])+':</strong> '+(Encode-SHtml $field[1])+'</section>')
    }
    [void]$sb.Append('<h2>Eventos consultados</h2><table><tr><th>Fecha</th><th>ID</th><th>Proveedor</th><th>Resumen</th></tr>')
    foreach($e in @($Events)) {
        [void]$sb.Append('<tr><td>'+(Encode-SHtml $e.Fecha)+'</td><td>'+(Encode-SHtml $e.Evento)+'</td><td>'+(Encode-SHtml $e.Proveedor)+'</td><td>'+(Encode-SHtml $e.Resumen)+'</td></tr>')
    }
    [void]$sb.Append('</table><h2>Impresión consultada</h2><table><tr><th>Nombre</th><th>Estado</th><th>Detalle</th></tr>')
    foreach($p in @($Printers)) {
        [void]$sb.Append('<tr><td>'+(Encode-SHtml $p.Nombre)+'</td><td>'+(Encode-SHtml $p.Estado)+'</td><td>'+(Encode-SHtml $p.Detalle)+'</td></tr>')
    }
    [void]$sb.Append('</table><p>Los datos y posibles causas son informativos. No demuestran fallos actuales ni certifican ausencia de malware. Revisa los datos personales antes de compartir el reporte.</p></main></body></html>')
    return $sb.ToString()
}
function Get-STableRecords($Table){
    $list=@()
    foreach($r in $Table.Rows){
        $obj=[ordered]@{}
        foreach($col in $Table.Columns){$obj[[string]$col.ColumnName]=[string]$r[[string]$col.ColumnName]}
        $list += [pscustomobject]$obj
    }
    return $list
}
function Save-SIntervention {
    $client=[string]$script:SClient.Text
    $ticket=[string]$script:STicket.Text
    $issue=[string]$script:SIssue.Text
    $action=[string]$script:SActions.Text
    $result=[string]$script:SResult.Text
    if([string]::IsNullOrWhiteSpace($issue) -or [string]::IsNullOrWhiteSpace($action)){
        [void][Windows.Forms.MessageBox]::Show('Completa el problema reportado y las acciones realizadas antes de guardar.','Registro incompleto','OK','Information');return
    }
    $message='Se guardará localmente el historial de esta intervención, incluyendo nombres e información técnica que escribiste.'+
       [Environment]::NewLine+'No se envía a Internet. Confirma que puedes registrar esos datos del cliente. ¿Continuar?'
    if([Windows.Forms.MessageBox]::Show($message,'Guardar historial técnico','YesNo','Question','Button2') -ne [Windows.Forms.DialogResult]::Yes){return}
    try{
        $dir=Join-Path (Get-SReports) ('soporte-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
        [void](New-Item -Path $dir -ItemType Directory -Force)
        $events=Get-STableRecords $script:SEvents
        $printers=Get-STableRecords $script:SPrinters
        $html=Build-SIncidentHtml -Events $events -Printers $printers -Client $client -Ticket $ticket -Issue $issue -Action $action -Result $result
        [IO.File]::WriteAllText((Join-Path $dir 'informe-soporte.html'),$html,(New-Object Text.UTF8Encoding($true)))
        if($events.Count){$events|Export-Csv -LiteralPath (Join-Path $dir 'eventos.csv') -NoTypeInformation -Encoding UTF8}
        if($printers.Count){$printers|Export-Csv -LiteralPath (Join-Path $dir 'impresoras.csv') -NoTypeInformation -Encoding UTF8}
        $record=[ordered]@{Fecha=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss');Cliente=$client;Ticket=$ticket;Problema=$issue;Acciones=$action;Resultado=$result}
        [IO.File]::WriteAllText((Join-Path $dir 'intervencion.json'),(ConvertTo-Json -InputObject $record -Depth 4),(New-Object Text.UTF8Encoding($true)))
        Write-SAudit ('Se generó informe local para la orden '+$ticket+' en '+$dir)
        $script:SStatus.Text='Registro guardado en '+$dir
        [void][Windows.Forms.MessageBox]::Show('Informe HTML, JSON y CSV guardados en '+$dir,'Intervención guardada','OK','Information')
    }catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Error al guardar registro','OK','Error')}
}
function Export-SConfiguration {
    $selector=New-Object Windows.Forms.FolderBrowserDialog
    $selector.Description='Selecciona dónde exportar información de red, impresoras e inicio. Recomendada: unidad externa.'
    $selector.ShowNewFolderButton=$true
    if($selector.ShowDialog($script:SForm) -ne [Windows.Forms.DialogResult]::OK){return}
    $parent=[string]$selector.SelectedPath
    if(-not (Test-SBackupTarget $parent $env:WINDIR)){
        [void][Windows.Forms.MessageBox]::Show('No se permiten destinos dentro de Windows, rutas inaccesibles ni enlaces. Selecciona otra carpeta.','Ruta no permitida','OK','Warning')
        return
    }
    $warning='Se exportarán configuraciones técnicas (IP, gateways, DNS, impresoras e inicio) a archivos CSV/JSON. No se guardarán argumentos de ejecución de programas.'+
        [Environment]::NewLine+'Puede incluir direcciones IP, nombres de usuario y rutas de programas. NO incluye contraseñas de Wi-Fi ni claves de autenticación.'+
        [Environment]::NewLine+'Esto NO es un respaldo completo ni podrá restaurar el sistema automáticamente. ¿Continuar?'
    if([Windows.Forms.MessageBox]::Show($warning,'Exportar configuración','YesNo','Warning','Button2') -ne [Windows.Forms.DialogResult]::Yes){return}
    try{
        $dest=Join-Path $parent ('WinCare-Config-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
        [void](New-Item -Path $dest -ItemType Directory -Force)
        $notes=New-Object 'System.Collections.Generic.List[string]'
        try{
            $network=@(Get-NetIPConfiguration -ErrorAction Stop | ForEach-Object {
                [pscustomobject]@{
                    Interfaz=[string]$_.InterfaceAlias
                    IPv4=(@($_.IPv4Address|ForEach-Object {$_.IPAddress}) -join ', ')
                    IPv6=(@($_.IPv6Address|ForEach-Object {$_.IPAddress}) -join ', ')
                    Gateway4=(@($_.IPv4DefaultGateway|ForEach-Object {$_.NextHop}) -join ', ')
                    DNS=(@($_.DNSServer.ServerAddresses) -join ', ')
                }
            })
            if($network.Count){$network|Export-Csv -LiteralPath (Join-Path $dest 'red.csv') -Encoding UTF8 -NoTypeInformation}
        }catch{[void]$notes.Add('Red: '+$_.Exception.Message)}
        try{
            $printers=@(Get-Printer -ErrorAction Stop|Select-Object Name,DriverName,PortName,Shared,PrinterStatus)
            if($printers.Count){$printers|Export-Csv -LiteralPath (Join-Path $dest 'impresoras.csv') -Encoding UTF8 -NoTypeInformation}
        }catch{[void]$notes.Add('Impresoras: '+$_.Exception.Message)}
        try{
            $startup=@(Get-CimInstance Win32_StartupCommand -ErrorAction Stop|Select-Object Name,Location,User)
            if($startup.Count){$startup|Export-Csv -LiteralPath (Join-Path $dest 'inicio.csv') -Encoding UTF8 -NoTypeInformation}
        }catch{[void]$notes.Add('Inicio: '+$_.Exception.Message)}
        ('Exportación técnica WinCare | DevPoderSEO'+[Environment]::NewLine+'NO contiene claves Wi-Fi ni contraseñas.'+[Environment]::NewLine+'No permite restaurar Windows automáticamente.'+[Environment]::NewLine+($notes -join [Environment]::NewLine))|Set-Content -LiteralPath (Join-Path $dest 'LEEME.txt') -Encoding UTF8
        Write-SAudit ('Respaldo técnico informativo exportado a '+$dest)
        [void][Windows.Forms.MessageBox]::Show(('Exportación terminada en '+$dest+'. Revisa los archivos y conserva copia fuera del equipo.'),'Configuración exportada','OK','Information')
    }catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Error al exportar','OK','Warning')}
}
function New-SGrid($Table){
    $grid=New-Object Windows.Forms.DataGridView
    $grid.Dock='Fill';$grid.ReadOnly=$true;$grid.AllowUserToAddRows=$false;$grid.AllowUserToDeleteRows=$false
    $grid.RowHeadersVisible=$false;$grid.AutoGenerateColumns=$false;$grid.SelectionMode='FullRowSelect'
    $grid.AutoSizeColumnsMode='DisplayedCells';$grid.BackgroundColor=$script:SColors.Panel;$grid.EnableHeadersVisualStyles=$false
    $grid.ColumnHeadersDefaultCellStyle.BackColor=[Drawing.Color]::FromArgb(43,58,78)
    $grid.ColumnHeadersDefaultCellStyle.ForeColor=$script:SColors.Text
    $grid.DefaultCellStyle.BackColor=$script:SColors.Panel;$grid.DefaultCellStyle.ForeColor=$script:SColors.Text
    $grid.DefaultCellStyle.SelectionBackColor=[Drawing.Color]::FromArgb(43,112,174);$grid.DefaultCellStyle.SelectionForeColor=[Drawing.Color]::White
    foreach($dc in $Table.Columns){
        $col=New-Object Windows.Forms.DataGridViewTextBoxColumn
        $col.Name=[string]$dc.ColumnName;$col.DataPropertyName=$col.Name;$col.HeaderText=$col.Name
        [void]$grid.Columns.Add($col)
    }
    $grid.DataSource=$Table.DefaultView
    return $grid
}
function New-SButton([string]$Text,[int]$X,[int]$Y,[int]$Width,[scriptblock]$Handler,$Panel){
    $btn=New-Object Windows.Forms.Button
    $btn.Text=$Text;$btn.Location=New-Object Drawing.Point($X,$Y);$btn.Size=New-Object Drawing.Size($Width,36)
    $btn.BackColor=$script:SColors.Accent;$btn.ForeColor=[Drawing.Color]::White;$btn.FlatStyle='Flat'
    $btn.Add_Click($Handler);$Panel.Controls.Add($btn)
    return $btn
}

$script:SForm=New-Object Windows.Forms.Form
$script:SForm.Text='WinCare v1.7 | Soporte y reparaciones | DevPoderSEO'
$script:SForm.StartPosition='CenterParent'
$script:SForm.Size=New-Object Drawing.Size(1210,810)
$script:SForm.MinimumSize=New-Object Drawing.Size(1020,700)
$script:SForm.BackColor=$script:SColors.Bg
$script:SForm.ForeColor=$script:SColors.Text
$script:SForm.Font=New-Object Drawing.Font('Segoe UI',9)
$title=New-Object Windows.Forms.Label
$title.Text='Soporte y reparaciones · v1.7'
$title.Location=New-Object Drawing.Point(22,15);$title.Size=New-Object Drawing.Size(850,38)
$title.Font=New-Object Drawing.Font('Segoe UI Semibold',18,[Drawing.FontStyle]::Bold)
$script:SForm.Controls.Add($title)
$brand=New-Object Windows.Forms.Label
$brand.Text='Diseñado por DevPoderSEO'
$brand.Location=New-Object Drawing.Point(866,22);$brand.Size=New-Object Drawing.Size(295,28)
$brand.Anchor='Top,Right';$brand.TextAlign='MiddleRight';$brand.ForeColor=$script:SColors.Accent
$script:SForm.Controls.Add($brand)
$hint=New-Object Windows.Forms.Label
$hint.Text='Inspecciona primero. Los cambios del sistema requieren permisos, consentimiento y advertencias específicas.'
$hint.Location=New-Object Drawing.Point(22,57);$hint.Size=New-Object Drawing.Size(1135,26);$hint.ForeColor=$script:SColors.Muted
$script:SForm.Controls.Add($hint)

$tabs=New-Object Windows.Forms.TabControl
$tabs.Location=New-Object Drawing.Point(19,96);$tabs.Size=New-Object Drawing.Size(1152,608)
$tabs.Anchor='Top,Bottom,Left,Right'
$script:SForm.Controls.Add($tabs)
$printerTab=New-Object Windows.Forms.TabPage
$printerTab.Text='Impresoras'
$printerTab.BackColor=$script:SColors.Panel
$eventTab=New-Object Windows.Forms.TabPage
$eventTab.Text='Errores de Windows'
$eventTab.BackColor=$script:SColors.Panel
$startupTab=New-Object Windows.Forms.TabPage
$startupTab.Text='Inicio y servicios'
$startupTab.BackColor=$script:SColors.Panel
$recordTab=New-Object Windows.Forms.TabPage
$recordTab.Text='Respaldos e intervenciones'
$recordTab.BackColor=$script:SColors.Panel
[void]$tabs.TabPages.AddRange([Windows.Forms.TabPage[]]@($printerTab,$eventTab,$startupTab,$recordTab))

$printerToolbar=New-Object Windows.Forms.FlowLayoutPanel
$printerToolbar.Dock='Top';$printerToolbar.Height=48;$printerTab.Controls.Add($printerToolbar)
$script:SPrintRead=New-SButton 'Revisar impresoras' 0 0 185 {Read-SPrinters} $printerToolbar
[void](New-SButton 'Abrir impresoras de Windows' 0 0 245 {Open-STool 'Printers'} $printerToolbar)
[void](New-SButton 'Reiniciar Spooler (con permiso)' 0 0 280 {Restart-SSpooler} $printerToolbar)
$script:SPrinterGrid=New-SGrid $script:SPrinters
$printerTab.Controls.Add($script:SPrinterGrid)
$script:SPrinterGrid.BringToFront()
$script:SPrinterGrid.Dock='Fill'
$printerToolbar.BringToFront()

$eventToolbar=New-Object Windows.Forms.FlowLayoutPanel
$eventToolbar.Dock='Top';$eventToolbar.Height=48;$eventTab.Controls.Add($eventToolbar)
[void](New-SButton 'Consultar eventos (14 días)' 0 0 236 {Read-SEvents} $eventToolbar)
[void](New-SButton 'Abrir Visor de eventos' 0 0 210 {Open-STool 'Events'} $eventToolbar)
$script:SEventGrid=New-SGrid $script:SEvents
$eventTab.Controls.Add($script:SEventGrid)
$script:SEventGrid.Dock='Fill';$eventToolbar.BringToFront()

$startupToolbar=New-Object Windows.Forms.FlowLayoutPanel
$startupToolbar.Dock='Top';$startupToolbar.Height=48;$startupTab.Controls.Add($startupToolbar)
[void](New-SButton 'Revisar inicio de Windows' 0 0 225 {Read-SStartup} $startupToolbar)
[void](New-SButton 'Abrir Administrador de tareas' 0 0 250 {Open-STool 'Startup'} $startupToolbar)
[void](New-SButton 'Abrir Servicios (advertencia)' 0 0 260 {Open-STool 'Services'} $startupToolbar)
$script:SStartupGrid=New-SGrid $script:SStartup
$startupTab.Controls.Add($script:SStartupGrid)
$script:SStartupGrid.Dock='Fill';$startupToolbar.BringToFront()

$heading=New-Object Windows.Forms.Label
$heading.Text='Registro de intervención'
$heading.Location=New-Object Drawing.Point(18,14);$heading.Size=New-Object Drawing.Size(780,32)
$heading.Font=New-Object Drawing.Font('Segoe UI Semibold',14,[Drawing.FontStyle]::Bold)
$recordTab.Controls.Add($heading)
$script:SClient=New-Object Windows.Forms.TextBox
$script:SClient.Location=New-Object Drawing.Point(19,58);$script:SClient.Size=New-Object Drawing.Size(340,30)
$recordTab.Controls.Add($script:SClient)
$script:STicket=New-Object Windows.Forms.TextBox
$script:STicket.Location=New-Object Drawing.Point(371,58);$script:STicket.Size=New-Object Drawing.Size(260,30)
$recordTab.Controls.Add($script:STicket)
$clientLbl=New-Object Windows.Forms.Label
$clientLbl.Text='Cliente / empresa (opcional)';$clientLbl.Location=New-Object Drawing.Point(19,40);$clientLbl.Size=New-Object Drawing.Size(285,19)
$clientLbl.ForeColor=$script:SColors.Muted;$recordTab.Controls.Add($clientLbl)
$ticketLbl=New-Object Windows.Forms.Label
$ticketLbl.Text='Orden / ticket';$ticketLbl.Location=New-Object Drawing.Point(371,40);$ticketLbl.Size=New-Object Drawing.Size(230,19)
$ticketLbl.ForeColor=$script:SColors.Muted;$recordTab.Controls.Add($ticketLbl)

$labelTexts=@(@('Problema reportado',104),@('Acciones realizadas',218),@('Resultado y siguientes pasos',332))
foreach($entry in $labelTexts){
    $lbl=New-Object Windows.Forms.Label
    $lbl.Text=[string]$entry[0];$lbl.Location=New-Object Drawing.Point(19,[int]$entry[1])
    $lbl.Size=New-Object Drawing.Size(500,20);$lbl.ForeColor=$script:SColors.Muted
    $recordTab.Controls.Add($lbl)
}
$script:SIssue=New-Object Windows.Forms.TextBox
$script:SIssue.Location=New-Object Drawing.Point(20,124);$script:SIssue.Size=New-Object Drawing.Size(1050,76)
$script:SIssue.Multiline=$true;$script:SIssue.Anchor='Top,Left,Right'
$recordTab.Controls.Add($script:SIssue)
$script:SActions=New-Object Windows.Forms.TextBox
$script:SActions.Location=New-Object Drawing.Point(20,238);$script:SActions.Size=New-Object Drawing.Size(1050,76)
$script:SActions.Multiline=$true;$script:SActions.Anchor='Top,Left,Right'
$recordTab.Controls.Add($script:SActions)
$script:SResult=New-Object Windows.Forms.TextBox
$script:SResult.Location=New-Object Drawing.Point(20,352);$script:SResult.Size=New-Object Drawing.Size(1050,76)
$script:SResult.Multiline=$true;$script:SResult.Anchor='Top,Left,Right'
$recordTab.Controls.Add($script:SResult)
[void](New-SButton 'Guardar historial e informe' 19 458 282 {Save-SIntervention} $recordTab)
[void](New-SButton 'Exportar configuración (sin secretos)' 318 458 348 {Export-SConfiguration} $recordTab)
$privacy=New-Object Windows.Forms.Label
$privacy.Text='Los informes quedan en el equipo o USB. Incluye datos del cliente solo con autorización. No se guardan contraseñas Wi-Fi.'
$privacy.Location=New-Object Drawing.Point(20,524);$privacy.Size=New-Object Drawing.Size(1040,48)
$privacy.Anchor='Bottom,Left,Right';$privacy.ForeColor=$script:SColors.Warning;$recordTab.Controls.Add($privacy)

$script:SStatus=New-Object Windows.Forms.Label
$script:SStatus.Text='Listo. Ninguna reparación ejecutada.'
$script:SStatus.Location=New-Object Drawing.Point(22,724);$script:SStatus.Size=New-Object Drawing.Size(1120,28)
$script:SStatus.Anchor='Bottom,Left,Right';$script:SStatus.ForeColor=$script:SColors.Muted
$script:SForm.Controls.Add($script:SStatus)
if($SmokeTest) {
    if($tabs.TabPages.Count -ne 4 -or $script:SPrinterGrid.Columns.Count -ne 5 -or $script:SEventGrid.Columns.Count -ne 6){throw 'Las secciones de soporte no se construyeron correctamente.'}
    if($script:SPrinters.Rows.Count -gt 0 -or $script:SEvents.Rows.Count -gt 0){throw 'SmokeTest no debe consultar Windows.'}
    Write-Host 'OK: Soporte v1.7, cuatro pestañas e inventarios vacíos sin cambios.'
    $script:SForm.Dispose();return
}
if($SafetyTest){
    $html=Build-SIncidentHtml -Events @() -Printers @() -Client '<script>fallo</script>' -Ticket 'T-1' -Issue '<img src=x>' -Action '& prueba' -Result 'Listo'
    if($html -match '<script>fallo' -or $html -notmatch '&lt;script&gt;' -or $html -notmatch '&lt;img'){throw 'HTML no escapado.'}
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('WinCare-Backup-'+[guid]::NewGuid().ToString('N'))
    [void](New-Item -Path $temp -ItemType Directory -Force)
    try {
        if(-not (Test-SBackupTarget $temp $env:WINDIR)){throw 'Rechazó carpeta de prueba autorizada.'}
        if(Test-SBackupTarget (Join-Path $env:WINDIR 'System32') $env:WINDIR){throw 'Permitió respaldo dentro de Windows.'}
    }finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
    Write-Host 'OK: HTML escapado, respaldo fuera de Windows, ninguna intervención ejecutada.'
    $script:SForm.Dispose();return
}
$script:SForm.Add_Shown({Read-SPrinters})
try {
    if($Owner -is [Windows.Forms.IWin32Window]){[void]$script:SForm.ShowDialog($Owner)}
    else{[void]$script:SForm.ShowDialog()}
}finally{$script:SForm.Dispose()}
