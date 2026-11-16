# WinCare Portable v1.5 - Taller técnico | Diseñado por DevPoderSEO
# Informe HTML sin Internet, respaldo de drivers y reparaciones guiadas con autorización.
#requires -Version 5.1
param([object]$Owner,[switch]$SmokeTest,[switch]$SafetyTest)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:TColors=@{
    Bg=[Drawing.Color]::FromArgb(16,23,34)
    Surface=[Drawing.Color]::FromArgb(27,39,54)
    Text=[Drawing.Color]::FromArgb(239,245,250)
    Muted=[Drawing.Color]::FromArgb(177,190,205)
    Accent=[Drawing.Color]::FromArgb(35,132,218)
}
$script:TRows=New-Object System.Data.DataTable
foreach($name in @('Área','Componente','Dato','Estado','Observación')){[void]$script:TRows.Columns.Add($name,[string])}
$script:TWarnings=New-Object System.Collections.Generic.List[string]
$script:TLastReport=''

function Add-TInfo([string]$Area,[string]$Name,[string]$Data,[string]$Status='Informativo',[string]$Detail='') {
    [void]$script:TRows.Rows.Add([object[]]@($Area,$Name,$Data,$Status,$Detail))
}
function Format-TBytes($Value) {
    if($null -eq $Value){return 'No disponible'}
    try{ return ('{0:N2} GB' -f ([double]$Value/1GB)) }catch{return 'No disponible'}
}
function Encode-THtml([object]$Value) {
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}
function Get-TReportsFolder {
    if(Get-Command Resolve-OutputDirectory -ErrorAction SilentlyContinue){return Resolve-OutputDirectory}
    $folder=Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WinCarePortable\Reportes'
    if(-not (Test-Path -LiteralPath $folder -PathType Container)){[void](New-Item -Path $folder -ItemType Directory -Force -ErrorAction Stop)}
    return $folder
}
function Write-TAudit([string]$Message) {
    try{
        if(Get-Command Write-Audit -ErrorAction SilentlyContinue){Write-Audit ('TALLER: '+$Message);return}
        Add-Content -LiteralPath (Join-Path (Get-TReportsFolder) 'auditoria-taller.txt') -Encoding UTF8 -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Message)
    }catch{}
}
function Safe-TRead([string]$Area,[scriptblock]$Work) {
    try { & $Work } catch {
        $message=$_.Exception.Message
        Add-TInfo $Area 'Lectura incompleta' 'No disponible' 'Información' $message
        [void]$script:TWarnings.Add(($Area+': '+$message))
    }
}
function Test-TAdmin {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Read-TInventory {
    $script:TScan.Enabled=$false
    $script:TRows.Clear()
    $script:TWarnings.Clear()
    $script:TStatus.Text='Recopilando datos de Windows...'
    [Windows.Forms.Application]::DoEvents()
    try{
        Safe-TRead 'Sistema' {
            $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            $pc=Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
            Add-TInfo 'Sistema' 'Windows' ([string]$os.Caption)
            Add-TInfo 'Sistema' 'Versión / compilación' (([string]$os.Version)+' / '+[string]$os.BuildNumber)
            Add-TInfo 'Sistema' 'Equipo' (([string]$pc.Manufacturer)+' '+[string]$pc.Model)
            Add-TInfo 'Sistema' 'Arquitectura' ([string]$os.OSArchitecture)
            if($script:TIdentifiers.Checked){Add-TInfo 'Sistema' 'Nombre de equipo' $env:COMPUTERNAME}
            Add-TInfo 'Sistema' 'RAM total' (Format-TBytes $pc.TotalPhysicalMemory)
            if($os.LastBootUpTime){Add-TInfo 'Sistema' 'Último arranque' ([datetime]$os.LastBootUpTime).ToString('yyyy-MM-dd HH:mm')}
        }
        Safe-TRead 'Procesador' {
            foreach($cpu in @(Get-CimInstance Win32_Processor -ErrorAction Stop)){
                Add-TInfo 'Procesador' 'Modelo' ([string]$cpu.Name)
                Add-TInfo 'Procesador' 'Núcleos / lógicos' (([string]$cpu.NumberOfCores)+' / '+[string]$cpu.NumberOfLogicalProcessors)
            }
        }
        Safe-TRead 'Almacenamiento' {
            foreach($drive in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop)){
                $free=[double]$drive.FreeSpace;$size=[double]$drive.Size
                $percent=if($size -gt 0){[math]::Round(($free/$size)*100,1)}else{0}
                Add-TInfo 'Almacenamiento' ([string]$drive.DeviceID) ((Format-TBytes $free)+' libres de '+(Format-TBytes $size)) $(if($percent -lt 10){'Revisar'}else{'Informativo'}) ('Libre: '+$percent+'%.')
            }
        }
        Safe-TRead 'Gráficos' {
            foreach($gpu in @(Get-CimInstance Win32_VideoController -ErrorAction Stop)){
                Add-TInfo 'Gráficos' ([string]$gpu.Name) ('Controlador '+[string]$gpu.DriverVersion)
            }
        }
        Safe-TRead 'Dispositivos' {
            $failed=@(Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object {$_.ConfigManagerErrorCode -ne 0})
            Add-TInfo 'Dispositivos' 'Con incidencia reportada' ([string]$failed.Count) $(if($failed.Count){'Revisar'}else{'Informativo'}) 'Los códigos PnP son orientativos; verifica en Administrador de dispositivos.'
            foreach($pnp in @($failed | Select-Object -First 15)){
                Add-TInfo 'Dispositivos' ([string]$pnp.Name) ('Código '+[string]$pnp.ConfigManagerErrorCode) 'Revisar' 'No eliminar drivers automáticamente.'
            }
        }
        Safe-TRead 'Red' {
            $adapters=@(Get-NetAdapter -ErrorAction Stop)
            foreach($adapter in $adapters){
                Add-TInfo 'Red' ([string]$adapter.Name) ([string]$adapter.Status+' | '+[string]$adapter.LinkSpeed)
            }
            if($script:TIdentifiers.Checked){
                foreach($cfg in @(Get-NetIPConfiguration -ErrorAction SilentlyContinue)){
                    Add-TInfo 'Red' ('IP '+[string]$cfg.InterfaceAlias) ((@($cfg.IPv4Address | ForEach-Object {$_.IPAddress})) -join ', ') 'Informativo' 'Dato sensible. Compartir solo con autorización.'
                }
            }
        }
        Safe-TRead 'Seguridad' {
            foreach($fw in @(Get-NetFirewallProfile -ErrorAction Stop)){
                Add-TInfo 'Seguridad' ('Firewall '+[string]$fw.Name) ([string]$fw.Enabled) $(if($fw.Enabled){'Informativo'}else{'Revisar'}) 'El perfil desactivado puede obedecer a una política. Revisa su configuración.'
            }
            try{
                $mp=Get-MpComputerStatus -ErrorAction Stop
                Add-TInfo 'Seguridad' 'Defender tiempo real' ([string]$mp.RealTimeProtectionEnabled) $(if($mp.RealTimeProtectionEnabled){'Informativo'}else{'Revisar'}) 'Si existe otro antivirus, Defender puede estar desactivado legítimamente.'
            }catch{
                Add-TInfo 'Seguridad' 'Defender' 'No verificable' 'Información' 'No confirma ausencia de protección.'
            }
        }
        Safe-TRead 'Actualizaciones' {
            $svc=Get-Service -Name wuauserv -ErrorAction Stop
            Add-TInfo 'Actualizaciones' 'Windows Update' ([string]$svc.Status+' | Inicio: '+[string]$svc.StartType) 'Informativo' 'Este dato no indica si hay parches pendientes.'
        }
        Safe-TRead 'Inicio' {
            $entries=@(Get-CimInstance Win32_StartupCommand -ErrorAction Stop)
            Add-TInfo 'Inicio' 'Entradas configuradas' ([string]$entries.Count) 'Informativo' 'No todas están activas ni son necesariamente lentas.'
        }
        $alerts=@($script:TRows.Rows | Where-Object { [string]$_['Estado'] -eq 'Revisar' }).Count
        $script:TStatus.Text=('{0} datos · {1} observaciones para revisar · {2} lecturas parciales.' -f $script:TRows.Rows.Count,$alerts,$script:TWarnings.Count)
        Write-TAudit ('Inventario técnico: '+$script:TRows.Rows.Count+' datos; '+$alerts+' revisar.')
    }finally{$script:TScan.Enabled=$true}
}
function Build-TReportHtml {
    param([object[]]$Rows,[string]$Client,[string]$Ticket,[string]$Computer,[datetime]$Date)
    # HTML sin recursos de Internet; todas las cadenas externas se codifican.
    $lines=New-Object 'System.Collections.Generic.List[string]'
    [void]$lines.Add('<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">')
    [void]$lines.Add('<title>Informe técnico | WinCare DevPoderSEO</title>')
    [void]$lines.Add('<style>body{margin:0;background:#101827;color:#e9eff8;font:14px Segoe UI,Arial,sans-serif}main{max-width:1090px;margin:28px auto;padding:26px}.head{display:flex;justify-content:space-between;gap:20px;align-items:start}.brand{color:#47aaff}.meta{margin:22px 0;background:#23344b;border-radius:14px;padding:17px;line-height:1.9}.lead{color:#b6c6d9}table{border-collapse:collapse;width:100%;background:#1b293b;border-radius:12px;overflow:hidden;font-size:12px}th,td{text-align:left;border-bottom:1px solid #35485e;padding:10px 8px;vertical-align:top;overflow-wrap:anywhere}th{background:#283b55}.warn{color:#ffd59b;font-weight:bold}.ok{color:#abdccf}h1{margin:0;font-size:27px}footer{margin-top:24px;color:#b2c0d0;font-size:12px}.print{background:#2987df;color:white;padding:10px 16px;border:0;border-radius:8px;cursor:pointer}@media print{body{background:white;color:#17263b}main{margin:0;padding:8px}.meta,table{background:white!important}th{background:#eceff5!important;color:#16253a}td{border-color:#ccd5df}.warn{color:#8c440d}.ok{color:#326b54}.print{display:none}}</style></head><body><main>')
    [void]$lines.Add('<div class="head"><div><h1>Informe técnico del equipo</h1><p class="lead">Diagnóstico orientativo · WinCare Portable</p></div><div><b class="brand">Diseñado por DevPoderSEO</b><p><button class="print" onclick="window.print()">Imprimir / Guardar PDF</button></p></div></div>')
    [void]$lines.Add('<section class="meta"><strong>Cliente:</strong> '+(Encode-THtml $Client)+'<br><strong>Orden / ticket:</strong> '+(Encode-THtml $Ticket)+'<br><strong>Equipo:</strong> '+(Encode-THtml $Computer)+'<br><strong>Fecha:</strong> '+(Encode-THtml $Date.ToString('yyyy-MM-dd HH:mm'))+'</section>')
    [void]$lines.Add('<table><thead><tr><th>Área</th><th>Componente</th><th>Dato observado</th><th>Estado</th><th>Nota técnica</th></tr></thead><tbody>')
    foreach($r in @($Rows)){
        $status=[string]$r.Estado
        $class=if($status -eq 'Revisar'){'warn'}else{'ok'}
        [void]$lines.Add('<tr><td>'+(Encode-THtml $r.Area)+'</td><td>'+(Encode-THtml $r.Componente)+'</td><td>'+(Encode-THtml $r.Dato)+'</td><td class="'+$class+'">'+(Encode-THtml $status)+'</td><td>'+(Encode-THtml $r.Observacion)+'</td></tr>')
    }
    [void]$lines.Add('</tbody></table><footer>Este informe refleja consultas del equipo en la fecha indicada. No certifica ausencia de malware ni garantiza el estado del hardware. No sustituye pruebas del fabricante. Evita compartir IP, identificadores o datos de clientes sin autorización.</footer></main></body></html>')
    return ($lines -join [Environment]::NewLine)
}
function Export-TReport {
    if($script:TRows.Rows.Count -eq 0){
        [void][Windows.Forms.MessageBox]::Show('Pulsa Analizar equipo antes de exportar.','Informe técnico','OK','Information')
        return
    }
    try{
        $records=@(foreach($r in $script:TRows.Rows){
            [pscustomobject]@{Area=[string]$r['Área'];Componente=[string]$r['Componente'];Dato=[string]$r['Dato'];Estado=[string]$r['Estado'];Observacion=[string]$r['Observación']}
        })
        $client=[string]$script:TClient.Text
        $ticket=[string]$script:TTicket.Text
        $html=Build-TReportHtml -Rows $records -Client $client -Ticket $ticket -Computer $(if($script:TIdentifiers.Checked){$env:COMPUTERNAME}else{'Identificadores omitidos'}) -Date (Get-Date)
        $directory=Join-Path (Get-TReportsFolder) ('taller-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
        [void](New-Item -Path $directory -ItemType Directory -Force)
        $file=Join-Path $directory 'informe-tecnico.html'
        [IO.File]::WriteAllText($file,$html,(New-Object Text.UTF8Encoding($true)))
        $records | Export-Csv -LiteralPath (Join-Path $directory 'datos-tecnicos.csv') -NoTypeInformation -Encoding UTF8
        $script:TLastReport=$file
        Write-TAudit ('Informe HTML y CSV exportados en '+$directory)
        [void][Windows.Forms.MessageBox]::Show(('Informe guardado en '+$file+[Environment]::NewLine+'Abre el HTML en un navegador y pulsa Imprimir / Guardar PDF. No se envía nada a Internet.'),'Informe listo','OK','Information')
        [void](Start-Process -FilePath $file -ErrorAction Stop)
    }catch{
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'No fue posible exportar','OK','Error')
    }
}
function Backup-TDrivers {
    if(-not (Test-TAdmin)){
        [void][Windows.Forms.MessageBox]::Show('Para exportar controladores con pnputil, reinicia WinCare como administrador usando Solicitar permisos. No se modificó el equipo.','Requiere administrador','OK','Information')
        return
    }
    $browse=New-Object Windows.Forms.FolderBrowserDialog
    $browse.Description='Elige una carpeta de respaldo con espacio suficiente; se recomienda unidad externa.'
    $browse.ShowNewFolderButton=$true
    if($browse.ShowDialog($script:TForm) -ne [Windows.Forms.DialogResult]::OK){return}
    $folder=[string]$browse.SelectedPath
    try{
        if(-not (Test-Path -LiteralPath $folder -PathType Container)){throw 'Carpeta no disponible.'}
        $full=[IO.Path]::GetFullPath($folder).TrimEnd('\')
        $win=[IO.Path]::GetFullPath($env:WINDIR).TrimEnd('\')
        if($full.StartsWith(($win+'\'),[StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($full,$win,[StringComparison]::OrdinalIgnoreCase)){
            throw 'No se permiten respaldos dentro de la carpeta Windows.'
        }
        $item=Get-Item -LiteralPath $full -Force -ErrorAction Stop
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'La carpeta seleccionada es un enlace; elige otra.'}
        $destination=Join-Path $full ('WinCare-Drivers-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
        $prompt='Se exportarán a '+$destination+' los paquetes de controladores de terceros disponibles en el almacén de Windows.'+
            [Environment]::NewLine+'Puede utilizar varios GB. No guarda licencias, programas, datos personales ni una imagen completa.'+
            [Environment]::NewLine+'¿Confirmas iniciar la copia?'
        if([Windows.Forms.MessageBox]::Show($prompt,'Respaldo de controladores','YesNo','Warning','Button2') -ne [Windows.Forms.DialogResult]::Yes){return}
        [void](New-Item -Path $destination -ItemType Directory -Force -ErrorAction Stop)
        $pnputil=Join-Path $env:WINDIR 'System32\pnputil.exe'
        if(-not (Test-Path -LiteralPath $pnputil -PathType Leaf)){throw 'pnputil no está disponible.'}
        $arguments='/export-driver * "'+$destination+'"'
        $script:TStatus.Text='Exportando controladores. La ventana puede permanecer ocupada.'
        [Windows.Forms.Application]::DoEvents()
        $process=Start-Process -FilePath $pnputil -ArgumentList $arguments -Wait -PassThru -ErrorAction Stop
        $code=[int]$process.ExitCode
        Write-TAudit ('Drivers: destino='+$destination+'; ExitCode='+$code)
        if($code -ne 0){throw ('pnputil terminó con código '+$code+'. Revisa el contenido parcial y el espacio libre.')}
        [void][Windows.Forms.MessageBox]::Show(('Windows terminó la exportación a '+$destination+'. Guarda una copia externa y comprueba las carpetas INF.','Resultado'),'','Information')
        $script:TStatus.Text='Exportación de drivers completada.'
    }catch{
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'No se completó respaldo de drivers','OK','Warning')
        $script:TStatus.Text='Respaldo sin confirmar. Revisa el informe.'
    }
}
function Run-TCommand([string]$Action) {
    $commands=@{
        'SFC (verificar)'=@('sfc.exe /verifyonly',$false,'Verifica archivos protegidos sin reparar.')
        'DISM (analizar)'=@('dism.exe /Online /Cleanup-Image /ScanHealth',$false,'Analiza el almacén de componentes sin repararlo.')
        'CHKDSK (analizar)'=@(('chkdsk.exe '+[string]$env:SystemDrive+' /scan'),$false,'Escaneo en línea; no ejecuta /f ni /r.')
        'SFC (reparar)'=@('sfc.exe /scannow',$true,'Puede reparar archivos protegidos y cambiar componentes de Windows.')
        'DISM (reparar)'=@('dism.exe /Online /Cleanup-Image /RestoreHealth',$true,'Puede descargar componentes desde Windows Update y modificar el almacén de componentes.')
    }
    if(-not $commands.ContainsKey($Action)){return}
    $entry=$commands[$Action]
    $mutating=[bool]$entry[1]
    $text=[string]$entry[2]+[Environment]::NewLine+'Se ejecutará en una consola con UAC y puede requerir tiempo, CPU, disco o reinicio.'+
        [Environment]::NewLine+'No se ejecuta ningún comando automáticamente.'
    if($mutating){$text+=[Environment]::NewLine+'REPARACIÓN: haz respaldo completo de datos importantes. No hay reversión garantizada.'}
    if([Windows.Forms.MessageBox]::Show(($text+[Environment]::NewLine+'¿Ejecutar?'),('Confirmar '+$Action),'YesNo','Warning','Button2') -ne [Windows.Forms.DialogResult]::Yes){return}
    if($mutating){
        if([Windows.Forms.MessageBox]::Show('Confirmación adicional: esta acción puede cambiar archivos de Windows. ¿Has guardado tus datos y comprendido el riesgo?','Reparación del sistema','YesNo','Warning','Button2') -ne [Windows.Forms.DialogResult]::Yes){return}
    }
    try{
        if($Action -eq 'CHKDSK (analizar)' -and $env:SystemDrive -notmatch '^[A-Za-z]:$'){throw 'Unidad del sistema no identificada de forma segura.'}
        $exe=Join-Path $env:WINDIR 'System32\cmd.exe'
        if(-not (Test-Path -LiteralPath $exe -PathType Leaf)){throw 'Consola de Windows no disponible.'}
        [void](Start-Process -FilePath $exe -ArgumentList ('/k '+[string]$entry[0]) -Verb RunAs -ErrorAction Stop)
        Write-TAudit ('Comando de diagnóstico/reparación lanzado con consentimiento: '+$Action)
        [void][Windows.Forms.MessageBox]::Show('Se abrió la consola. Revisa el resultado allí; WinCare no asume que la operación terminó correctamente.','Acción iniciada','OK','Information')
    }catch{
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'No se pudo iniciar','OK','Warning')
    }
}
function Update-TRepairGuide {
    $action=[string]$script:TRepairChoice.SelectedItem
    $notes=@{
        'SFC (verificar)'='Paso 1 recomendado: verifica archivos protegidos. No repara.'
        'DISM (analizar)'='Paso 2: analiza salud del almacén de componentes. No repara.'
        'CHKDSK (analizar)'='Paso 3: revisa el sistema de archivos en línea. Sin /f ni /r.'
        'SFC (reparar)'='RIESGO MEDIO: puede modificar archivos protegidos. Respaldar antes.'
        'DISM (reparar)'='RIESGO MEDIO: puede reparar Windows y descargar componentes. Respaldar antes.'
    }
    $script:TRepairDetail.Text=[string]$notes[$action]
}

$script:TForm=New-Object Windows.Forms.Form
$script:TForm.Text='WinCare Portable | Taller técnico | Diseñado por DevPoderSEO'
$script:TForm.StartPosition='CenterParent'
$script:TForm.Size=New-Object Drawing.Size(1200,800)
$script:TForm.MinimumSize=New-Object Drawing.Size(1000,700)
$script:TForm.BackColor=$script:TColors.Bg
$script:TForm.ForeColor=$script:TColors.Text
$script:TForm.Font=New-Object Drawing.Font('Segoe UI',9)
$head=New-Object Windows.Forms.Label
$head.Text='Taller técnico  /  diagnóstico y soporte'
$head.Location=New-Object Drawing.Point(20,17)
$head.Size=New-Object Drawing.Size(840,38)
$head.Font=New-Object Drawing.Font('Segoe UI Semibold',18,[Drawing.FontStyle]::Bold)
$script:TForm.Controls.Add($head)
$brand=New-Object Windows.Forms.Label
$brand.Text='Diseñado por DevPoderSEO'
$brand.Location=New-Object Drawing.Point(875,24)
$brand.Size=New-Object Drawing.Size(285,28)
$brand.Anchor='Top,Right'
$brand.TextAlign='MiddleRight'
$brand.ForeColor=$script:TColors.Accent
$script:TForm.Controls.Add($brand)
$subtitle=New-Object Windows.Forms.Label
$subtitle.Text='Informe para el cliente, copia de controladores y reparación paso a paso. Sin acciones automáticas.'
$subtitle.Location=New-Object Drawing.Point(22,61)
$subtitle.Size=New-Object Drawing.Size(1120,28)
$subtitle.ForeColor=$script:TColors.Muted
$script:TForm.Controls.Add($subtitle)

$tabs=New-Object Windows.Forms.TabControl
$tabs.Location=New-Object Drawing.Point(19,103)
$tabs.Size=New-Object Drawing.Size(1140,596)
$tabs.Anchor='Top,Bottom,Left,Right'
$script:TForm.Controls.Add($tabs)
$reportTab=New-Object Windows.Forms.TabPage
$reportTab.Text='Informe técnico'
$reportTab.BackColor=$script:TColors.Surface
$backupTab=New-Object Windows.Forms.TabPage
$backupTab.Text='Respaldo drivers'
$backupTab.BackColor=$script:TColors.Surface
$repairTab=New-Object Windows.Forms.TabPage
$repairTab.Text='Reparación guiada'
$repairTab.BackColor=$script:TColors.Surface
[void]$tabs.TabPages.AddRange([Windows.Forms.TabPage[]]@($reportTab,$backupTab,$repairTab))

$script:TClient=New-Object Windows.Forms.TextBox
$script:TClient.Location=New-Object Drawing.Point(17,17)
$script:TClient.Size=New-Object Drawing.Size(260,28)
$script:TClient.Text='Cliente / empresa'
$reportTab.Controls.Add($script:TClient)
$script:TTicket=New-Object Windows.Forms.TextBox
$script:TTicket.Location=New-Object Drawing.Point(288,17)
$script:TTicket.Size=New-Object Drawing.Size(220,28)
$script:TTicket.Text='Orden de trabajo'
$reportTab.Controls.Add($script:TTicket)
$script:TIdentifiers=New-Object Windows.Forms.CheckBox
$script:TIdentifiers.Text='Incluir nombre del equipo e IP'
$script:TIdentifiers.Location=New-Object Drawing.Point(522,17)
$script:TIdentifiers.Size=New-Object Drawing.Size(225,28)
$script:TIdentifiers.Checked=$false
$script:TIdentifiers.ForeColor=$script:TColors.Muted
$reportTab.Controls.Add($script:TIdentifiers)
$script:TScan=New-Object Windows.Forms.Button
$script:TScan.Text='Analizar equipo'
$script:TScan.Location=New-Object Drawing.Point(760,13)
$script:TScan.Size=New-Object Drawing.Size(160,34)
$script:TScan.BackColor=$script:TColors.Accent
$script:TScan.ForeColor=[Drawing.Color]::White
$script:TScan.FlatStyle='Flat'
$script:TScan.Add_Click({ Read-TInventory })
$reportTab.Controls.Add($script:TScan)
$export=New-Object Windows.Forms.Button
$export.Text='Exportar HTML / CSV'
$export.Location=New-Object Drawing.Point(932,13)
$export.Size=New-Object Drawing.Size(178,34)
$export.Anchor='Top,Right'
$export.Add_Click({ Export-TReport })
$reportTab.Controls.Add($export)
$script:TGrid=New-Object Windows.Forms.DataGridView
$script:TGrid.Location=New-Object Drawing.Point(16,63)
$script:TGrid.Size=New-Object Drawing.Size(1097,473)
$script:TGrid.Anchor='Top,Bottom,Left,Right'
$script:TGrid.ReadOnly=$true
$script:TGrid.AllowUserToAddRows=$false
$script:TGrid.AllowUserToDeleteRows=$false
$script:TGrid.AutoGenerateColumns=$false
$script:TGrid.RowHeadersVisible=$false
$script:TGrid.SelectionMode='FullRowSelect'
$script:TGrid.AutoSizeColumnsMode='Fill'
$script:TGrid.BackgroundColor=$script:TColors.Surface
$script:TGrid.EnableHeadersVisualStyles=$false
$script:TGrid.ColumnHeadersDefaultCellStyle.BackColor=[Drawing.Color]::FromArgb(44,60,82)
$script:TGrid.ColumnHeadersDefaultCellStyle.ForeColor=$script:TColors.Text
$script:TGrid.DefaultCellStyle.BackColor=$script:TColors.Surface
$script:TGrid.DefaultCellStyle.ForeColor=$script:TColors.Text
$script:TGrid.DefaultCellStyle.SelectionBackColor=[Drawing.Color]::FromArgb(39,108,173)
$script:TGrid.DefaultCellStyle.SelectionForeColor=[Drawing.Color]::White
foreach($name in @('Área','Componente','Dato','Estado','Observación')){
    $col=New-Object Windows.Forms.DataGridViewTextBoxColumn
    $col.Name=$name;$col.DataPropertyName=$name;$col.HeaderText=$name
    $col.FillWeight=[single](switch($name){'Área'{80}'Componente'{155}'Dato'{210}'Estado'{80}'Observación'{265}})
    [void]$script:TGrid.Columns.Add($col)
}
$script:TGrid.DataSource=$script:TRows.DefaultView
$reportTab.Controls.Add($script:TGrid)

$backupHeader=New-Object Windows.Forms.Label
$backupHeader.Text='Respaldo de controladores de terceros'
$backupHeader.Location=New-Object Drawing.Point(32,32)
$backupHeader.Size=New-Object Drawing.Size(1000,36)
$backupHeader.Font=New-Object Drawing.Font('Segoe UI Semibold',17,[Drawing.FontStyle]::Bold)
$backupTab.Controls.Add($backupHeader)
$backupDescription=New-Object Windows.Forms.Label
$backupDescription.Text='Utiliza pnputil /export-driver para copiar paquetes del almacén de drivers. No es una copia de Windows ni incluye programas, licencias o documentos.'+
    [Environment]::NewLine+'Se recomienda seleccionar una unidad USB externa y verificar que haya espacio suficiente. Requiere administrador.'
$backupDescription.Location=New-Object Drawing.Point(34,85)
$backupDescription.Size=New-Object Drawing.Size(1050,94)
$backupDescription.ForeColor=$script:TColors.Muted
$backupTab.Controls.Add($backupDescription)
$backupButton=New-Object Windows.Forms.Button
$backupButton.Text='Elegir carpeta y exportar drivers'
$backupButton.Location=New-Object Drawing.Point(35,190)
$backupButton.Size=New-Object Drawing.Size(355,46)
$backupButton.BackColor=$script:TColors.Accent
$backupButton.ForeColor=[Drawing.Color]::White
$backupButton.FlatStyle='Flat'
$backupButton.Add_Click({ Backup-TDrivers })
$backupTab.Controls.Add($backupButton)
$backupWarn=New-Object Windows.Forms.Label
$backupWarn.Text='Atención: recuperar un equipo puede requerir instaladores y firmware del fabricante. Verifica el respaldo antes de formatear.'
$backupWarn.Location=New-Object Drawing.Point(34,258)
$backupWarn.Size=New-Object Drawing.Size(1050,60)
$backupWarn.ForeColor=[Drawing.Color]::FromArgb(244,189,113)
$backupTab.Controls.Add($backupWarn)

$repairHeader=New-Object Windows.Forms.Label
$repairHeader.Text='Diagnosticar primero · reparar solo cuando corresponda'
$repairHeader.Location=New-Object Drawing.Point(32,33)
$repairHeader.Size=New-Object Drawing.Size(1060,35)
$repairHeader.Font=New-Object Drawing.Font('Segoe UI Semibold',16,[Drawing.FontStyle]::Bold)
$repairTab.Controls.Add($repairHeader)
$repairHelp=New-Object Windows.Forms.Label
$repairHelp.Text='Secuencia recomendada: 1. Respaldo · 2. Verificación no destructiva · 3. Revisar resultados · 4. Reparación opcional.'+
    [Environment]::NewLine+'No se modifica el sistema sin autorización. Reparaciones como SFC /scannow o DISM /RestoreHealth no garantizan reversión.'
$repairHelp.Location=New-Object Drawing.Point(32,85)
$repairHelp.Size=New-Object Drawing.Size(1050,90)
$repairHelp.ForeColor=$script:TColors.Muted
$repairTab.Controls.Add($repairHelp)
$script:TRepairChoice=New-Object Windows.Forms.ComboBox
$script:TRepairChoice.DropDownStyle='DropDownList'
$script:TRepairChoice.Location=New-Object Drawing.Point(33,182)
$script:TRepairChoice.Size=New-Object Drawing.Size(370,31)
$script:TRepairChoice.Items.AddRange([object[]]@('SFC (verificar)','DISM (analizar)','CHKDSK (analizar)','SFC (reparar)','DISM (reparar)'))
$repairTab.Controls.Add($script:TRepairChoice)
$repairAction=New-Object Windows.Forms.Button
$repairAction.Text='Revisar advertencia y ejecutar'
$repairAction.Location=New-Object Drawing.Point(419,180)
$repairAction.Size=New-Object Drawing.Size(300,38)
$repairAction.Add_Click({ Run-TCommand ([string]$script:TRepairChoice.SelectedItem) })
$repairTab.Controls.Add($repairAction)
$script:TRepairDetail=New-Object Windows.Forms.Label
$script:TRepairDetail.Location=New-Object Drawing.Point(33,247)
$script:TRepairDetail.Size=New-Object Drawing.Size(1010,90)
$script:TRepairDetail.ForeColor=[Drawing.Color]::FromArgb(246,187,114)
$repairTab.Controls.Add($script:TRepairDetail)
$script:TRepairChoice.Add_SelectedIndexChanged({ Update-TRepairGuide })
$script:TRepairChoice.SelectedIndex=0

$script:TStatus=New-Object Windows.Forms.Label
$script:TStatus.Text='Solo lectura. Ningún diagnóstico, respaldo o reparación iniciado.'
$script:TStatus.Location=New-Object Drawing.Point(24,718)
$script:TStatus.Size=New-Object Drawing.Size(1120,28)
$script:TStatus.Anchor='Bottom,Left,Right'
$script:TStatus.ForeColor=$script:TColors.Muted
$script:TForm.Controls.Add($script:TStatus)
if($SmokeTest){
    if($tabs.TabPages.Count -ne 3){throw 'Faltan secciones de Taller técnico.'}
    if($script:TGrid.Columns.Count -ne 5){throw 'Faltan columnas de informe.'}
    if($script:TRepairChoice.SelectedIndex -ne 0){throw 'Las acciones de reparación deben comenzar en solo verificar.'}
    if($script:TIdentifiers.Checked){throw 'Los identificadores no deben incluirse por defecto.'}
    Write-Host 'OK: Taller técnico construido, 3 pestañas, reportes y reparación conservadora.'
    $script:TForm.Dispose()
    return
}
if($SafetyTest){
    $testRows=@([pscustomobject]@{Area='A';Componente='<script>alert(1)</script>';Dato='& prueba';Estado='Informativo';Observacion='"cita"'})
    $html=Build-TReportHtml -Rows $testRows -Client '<b>Cliente</b>' -Ticket 'T-1' -Computer 'No incluido' -Date (Get-Date)
    if($html -match '<script>alert' -or $html -match '<b>Cliente</b>'){throw 'Inyección HTML en informe.'}
    if($html -notmatch '&lt;script&gt;' -or $html -notmatch '&lt;b&gt;Cliente&lt;/b&gt;'){throw 'La salida no codificó HTML.'}
    Write-Host 'OK: informe HTML escapa valores externos; ninguna reparación ni respaldo ejecutados.'
    $script:TForm.Dispose()
    return
}
try{
    if($Owner -is [Windows.Forms.IWin32Window]){[void]$script:TForm.ShowDialog($Owner)}
    else{[void]$script:TForm.ShowDialog()}
}finally{$script:TForm.Dispose()}
