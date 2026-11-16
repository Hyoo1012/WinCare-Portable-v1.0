# WinCare Portable - Auditoria de red e IP v1.6
# Diagnóstico inteligente integrado · Diseñado por DevPoderSEO
# Diseñado por DevPoderSEO
# Modulo para Windows PowerShell 5.1 y Windows 10/11.
# Solo lectura: no mata procesos, no bloquea IP y no escanea otros hosts.
# Una conexion desconocida NO demuestra una intrusion.
#requires -Version 5.1
param([System.Windows.Forms.Form]$Owner, [switch]$SmokeTest)

$script:NColors = @{
    Bg=[Drawing.Color]::FromArgb(17,24,35)
    Panel=[Drawing.Color]::FromArgb(28,38,52)
    Text=[Drawing.Color]::FromArgb(238,243,249)
    Muted=[Drawing.Color]::FromArgb(172,184,201)
    Accent=[Drawing.Color]::FromArgb(37,132,221)
}
$script:NCategories = @('Conexiones TCP','Puertos UDP','Equipos LAN','Configuración IP','Firewall')
$script:NColumns = @{
    'Conexiones TCP' = @('Proceso','PID','IP local','Puerto local','IP remota','Puerto remoto','Estado','Alcance','Firma','Riesgo','Ruta')
    'Puertos UDP' = @('Proceso','PID','IP local','Puerto local','Firma','Riesgo','Ruta')
    'Equipos LAN' = @('IP','MAC','Interfaz','Estado','Identificación','Observación')
    'Configuración IP' = @('Interfaz','Estado','IPv4','IPv6','Gateway','DNS')
    'Firewall' = @('Perfil','Activado','Entrantes','Salientes','Observación')
}
$script:NTables = @{}
$script:NGrids = @{}
$script:NWarnings = New-Object System.Collections.Generic.List[string]
$script:NKnown = @()
$script:NKnownPath = Join-Path $PSScriptRoot 'Red-Confiables.json'

function Get-NIPScope([string]$Value) {
    $ip = $null
    if (-not [Net.IPAddress]::TryParse($Value,[ref]$ip)) { return 'No válida' }
    if ([Net.IPAddress]::IsLoopback($ip)) { return 'Local (loopback)' }
    if ($ip.IsIPv4MappedToIPv6) { return Get-NIPScope ($ip.MapToIPv4().ToString()) }
    $b = $ip.GetAddressBytes()
    if ($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) {
        if ($b[0] -eq 10 -or ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or ($b[0] -eq 192 -and $b[1] -eq 168)) { return 'Privada / LAN' }
        if ($b[0] -eq 100 -and $b[1] -ge 64 -and $b[1] -le 127) { return 'CGNAT' }
        if ($b[0] -eq 0 -or $b[0] -eq 127 -or ($b[0] -eq 169 -and $b[1] -eq 254) -or $b[0] -ge 224) { return 'Especial / reservada' }
        if (($b[0] -eq 192 -and $b[1] -eq 0 -and $b[2] -eq 2) -or ($b[0] -eq 198 -and $b[1] -eq 51 -and $b[2] -eq 100) -or ($b[0] -eq 203 -and $b[1] -eq 0 -and $b[2] -eq 113)) { return 'Documentación' }
        return 'Pública'
    }
    if ($ip.Equals([Net.IPAddress]::IPv6Any) -or $ip.IsIPv6LinkLocal) { return 'Especial / enlace' }
    if ($b[0] -eq 255) { return 'Multicast' }
    if (($b[0] -band 254) -eq 252) { return 'Privada / LAN' }
    return 'Pública'
}

function Read-NKnown {
    $alternative = Join-Path (Resolve-OutputDirectory) 'Red-Confiables.json'
    if (-not (Test-Path -LiteralPath $script:NKnownPath) -and (Test-Path -LiteralPath $alternative)) { $script:NKnownPath = $alternative }
    $script:NKnown = @()
    if (Test-Path -LiteralPath $script:NKnownPath) {
        try {
            $value = Get-Content -LiteralPath $script:NKnownPath -Encoding UTF8 -Raw | ConvertFrom-Json
            $script:NKnown = @($value | Where-Object { $_ -and $_.IP })
        } catch { [void]$script:NWarnings.Add('Lista local dañada: ' + $_.Exception.Message) }
    }
}
function Save-NKnown {
    $json = ConvertTo-Json -InputObject @($script:NKnown) -Depth 4
    try { Set-Content -LiteralPath $script:NKnownPath -Value $json -Encoding UTF8 -ErrorAction Stop }
    catch {
        $script:NKnownPath = Join-Path (Resolve-OutputDirectory) 'Red-Confiables.json'
        Set-Content -LiteralPath $script:NKnownPath -Value $json -Encoding UTF8 -ErrorAction Stop
    }
    Write-Audit ('RED: lista de dispositivos registrados actualizada. Total: ' + $script:NKnown.Count)
}
function New-NTable([string[]]$Columns) {
    $table = New-Object System.Data.DataTable
    foreach ($col in $Columns) { [void]$table.Columns.Add($col,[string]) }
    return ,$table
}
function Add-NRow([string]$Category,[object[]]$Values) {
    [void]$script:NTables[$Category].Rows.Add($Values)
}
function Get-NProcessInfo([int]$ProcessId,[hashtable]$Map,[hashtable]$Cache) {
    if ($Cache.ContainsKey($ProcessId)) { return $Cache[$ProcessId] }
    $result = [pscustomobject]@{ Name='No identificado'; Path=''; Signature='No verificable' }
    if ($ProcessId -eq 0 -or $ProcessId -eq 4) {
        $result = [pscustomobject]@{ Name='Sistema'; Path=''; Signature='Windows' }
    } elseif ($Map.ContainsKey($ProcessId)) {
        $proc = $Map[$ProcessId]
        $path = [string]$proc.ExecutablePath
        $signature = 'No verificable'
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path -PathType Leaf)) {
            try {
                $sig = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop
                if ($sig.Status -eq 'Valid') { $signature = 'Válida' }
                elseif ($sig.Status -eq 'NotSigned') { $signature = 'Sin firma' }
                else { $signature = 'No válida' }
            } catch { $signature = 'No verificable' }
        }
        $result = [pscustomobject]@{ Name=[string]$proc.Name; Path=$path; Signature=$signature }
    }
    $Cache[$ProcessId] = $result
    return $result
}
function Read-NConnections {
    $map = @{}
    foreach ($process in @(Get-CimInstance Win32_Process -ErrorAction Stop)) { $map[[int]$process.ProcessId] = $process }
    $cache = @{}
    foreach ($item in @(Get-NetTCPConnection -ErrorAction Stop)) {
        $pidNum = [int]$item.OwningProcess
        $proc = Get-NProcessInfo $pidNum $map $cache
        $scope = Get-NIPScope ([string]$item.RemoteAddress)
        $state = [string]$item.State
        $risk = 'Informativo'
        if ($state -eq 'Established' -and $scope -eq 'Pública' -and $proc.Signature -in @('Sin firma','No válida','No verificable')) { $risk = 'Revisar' }
        if ($state -eq 'Established' -and $scope -eq 'Pública' -and $proc.Path -match '(?i)\\(Temp|Downloads)\\') { $risk = 'Revisar' }
        Add-NRow 'Conexiones TCP' @([string]$proc.Name,[string]$pidNum,[string]$item.LocalAddress,[string]$item.LocalPort,[string]$item.RemoteAddress,[string]$item.RemotePort,$state,$scope,[string]$proc.Signature,$risk,[string]$proc.Path)
    }
    foreach ($item in @(Get-NetUDPEndpoint -ErrorAction Stop)) {
        $pidNum = [int]$item.OwningProcess
        $proc = Get-NProcessInfo $pidNum $map $cache
        $risk = if ($proc.Path -match '(?i)\\(Temp|Downloads)\\' -and $proc.Signature -in @('Sin firma','No válida')) { 'Revisar' } else { 'Informativo' }
        Add-NRow 'Puertos UDP' @([string]$proc.Name,[string]$pidNum,[string]$item.LocalAddress,[string]$item.LocalPort,[string]$proc.Signature,$risk,[string]$proc.Path)
    }
}
function Read-NNeighbors {
    $gateways = @()
    foreach ($cfg in @(Get-NetIPConfiguration -ErrorAction SilentlyContinue)) {
        if ($cfg.IPv4DefaultGateway) { $gateways += @($cfg.IPv4DefaultGateway | ForEach-Object { [string]$_.NextHop }) }
        if ($cfg.IPv6DefaultGateway) { $gateways += @($cfg.IPv6DefaultGateway | ForEach-Object { [string]$_.NextHop }) }
    }
    foreach ($entry in @(Get-NetNeighbor -ErrorAction Stop | Sort-Object IPAddress,InterfaceIndex -Unique)) {
        $ip = [string]$entry.IPAddress
        $mac = [string]$entry.LinkLayerAddress
        $label = 'Por verificar'
        $message = 'Vecino ARP/ND observado. No significa intrusión. Consulta tu router para identificarlo.'
        if ($gateways -contains $ip) {
            $label='Puerta de enlace'
            $message='Dirección informada como puerta de enlace de este equipo.'
        } else {
            foreach ($known in $script:NKnown) {
                $matchMAC = $mac -and $mac -notmatch '^00[-:]00' -and $known.MAC -eq $mac
                $matchIP = $known.IP -eq $ip -and (-not $mac -or -not $known.MAC)
                if ($matchMAC -or $matchIP) {
                    $label = 'Registrado: ' + [string]$known.Nombre
                    $message = 'Coincide con un registro local. Una MAC puede cambiar o suplantarse.'
                    break
                }
            }
        }
        Add-NRow 'Equipos LAN' @($ip,$mac,[string]$entry.InterfaceAlias,[string]$entry.State,$label,$message)
    }
}
function Read-NConfiguration {
    foreach ($cfg in @(Get-NetIPConfiguration -ErrorAction Stop)) {
        $v4 = @($cfg.IPv4Address | ForEach-Object { [string]$_.IPAddress }) -join ', '
        $v6 = @($cfg.IPv6Address | ForEach-Object { [string]$_.IPAddress }) -join ', '
        $gateway = @($cfg.IPv4DefaultGateway | ForEach-Object { [string]$_.NextHop }) -join ', '
        $dns = @($cfg.DNSServer.ServerAddresses) -join ', '
        $state = if ($cfg.NetAdapter) { [string]$cfg.NetAdapter.Status } else { 'Sin datos' }
        Add-NRow 'Configuración IP' @([string]$cfg.InterfaceAlias,$state,$v4,$v6,$gateway,$dns)
    }
}
function Read-NFirewall {
    foreach ($profile in @(Get-NetFirewallProfile -ErrorAction Stop)) {
        $note = if ($profile.Enabled) { 'Firewall declarado activo; revisa también sus reglas.' } else { 'ATENCIÓN: firewall desactivado en este perfil.' }
        Add-NRow 'Firewall' @([string]$profile.Name,[string]$profile.Enabled,[string]$profile.DefaultInboundAction,[string]$profile.DefaultOutboundAction,$note)
    }
}
function Set-NFilter {
    if (-not $script:NTab.SelectedTab) { return }
    $view = $script:NTables[$script:NTab.SelectedTab.Text].DefaultView
    $value = ([string]$script:NSearch.Text).Replace("'","''").Replace('[','[[]').Replace(']','[]]').Replace('%','[%]').Replace('*','[*]')
    if (-not $value) { $view.RowFilter = ''; return }
    $parts = @()
    foreach ($col in $script:NTables[$script:NTab.SelectedTab.Text].Columns) {
        $parts += ('[{0}] LIKE ''%{1}%''' -f $col.ColumnName,$value)
    }
    try { $view.RowFilter = $parts -join ' OR ' } catch { $view.RowFilter = '' }
}
function Refresh-NInventory([string]$Category='') {
    if($Category -and $Category -notin $script:NCategories){throw 'Pestaña de red inválida.'}
    $script:NRefresh.Enabled = $false
    try {
        $script:NWarnings.Clear()
        if($Category){$script:NTables[$Category].Clear()}
        else{foreach ($kind in $script:NCategories) { $script:NTables[$kind].Clear() }}
        Read-NKnown
        $tasks = @(
            @('Conexiones TCP y UDP', { Read-NConnections }),
            @('Equipos LAN', { Read-NNeighbors }),
            @('Configuración IP', { Read-NConfiguration }),
            @('Firewall', { Read-NFirewall })
        )
        foreach ($task in $tasks) {
            if($Category -and [string]$task[0] -ne $Category){continue}
            $script:NStatus.Text = 'Consultando ' + [string]$task[0]
            [Windows.Forms.Application]::DoEvents()
            try { & $task[1] } catch { [void]$script:NWarnings.Add(([string]$task[0] + ': ' + $_.Exception.Message)) }
        }
        $count = 0
        foreach ($table in $script:NTables.Values) { $count += $table.Rows.Count }
        $script:NStatus.Text = ('{0} registros - {1} advertencias - {2}' -f $count,$script:NWarnings.Count,(Get-Date -Format 'HH:mm:ss'))
        Set-NFilter
        Write-Audit ('RED: inspección pasiva de ' + $count + ' registros.')
        if ($script:NWarnings.Count -gt 0) {
            [void][Windows.Forms.MessageBox]::Show(($script:NWarnings -join [Environment]::NewLine),'Datos parciales','OK','Warning')
        }
    } finally { $script:NRefresh.Enabled = $true }
}
function Get-NSelection {
    if (-not $script:NTab.SelectedTab) { return $null }
    $grid = $script:NGrids[$script:NTab.SelectedTab.Text]
    if (-not $grid -or $grid.SelectedRows.Count -ne 1) { return $null }
    return $grid.SelectedRows[0]
}
function Inspect-NProcess {
    $row = Get-NSelection
    if (-not $row) { return }
    if ($script:NTab.SelectedTab.Text -notin @('Conexiones TCP','Puertos UDP')) {
        [void][Windows.Forms.MessageBox]::Show('Selecciona Conexiones TCP o Puertos UDP.','Inspección','OK','Information')
        return
    }
    $path = [string]$row.Cells['Ruta'].Value
    $lines = @(
        ('Proceso: ' + [string]$row.Cells['Proceso'].Value),
        ('PID: ' + [string]$row.Cells['PID'].Value),
        ('Firma: ' + [string]$row.Cells['Firma'].Value),
        ('Ruta: ' + $path)
    )
    if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) {
        try { $lines += ('SHA-256: ' + (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash) }
        catch { $lines += 'No se pudo calcular el hash: ' + $_.Exception.Message }
    }
    $lines += 'Una firma válida NO garantiza seguridad. Un proceso sin firma NO demuestra malware.'
    [void][Windows.Forms.MessageBox]::Show(($lines -join [Environment]::NewLine),'Atribución de proceso - solo lectura','OK','Information')
}
function Register-NDevice {
    $row = Get-NSelection
    if (-not $row -or $script:NTab.SelectedTab.Text -ne 'Equipos LAN') {
        [void][Windows.Forms.MessageBox]::Show('Selecciona un dispositivo en Equipos LAN.','Registro','OK','Information')
        return
    }
    $ip = [string]$row.Cells['IP'].Value
    $mac = [string]$row.Cells['MAC'].Value
    $message = ('¿Confirmaste este dispositivo desde tu router?' + [Environment]::NewLine + 'IP: ' + $ip + [Environment]::NewLine + 'MAC: ' + $mac + [Environment]::NewLine + 'Registrar NO demuestra que esté libre de malware.')
    if ([Windows.Forms.MessageBox]::Show($message,'Registrar equipo','YesNo','Warning','Button2') -ne [Windows.Forms.DialogResult]::Yes) { return }
    Add-Type -AssemblyName Microsoft.VisualBasic
    $name = [string][Microsoft.VisualBasic.Interaction]::InputBox('Nombre para identificar el equipo autorizado.','Equipo reconocido','Equipo verificado')
    if ([string]::IsNullOrWhiteSpace($name)) { return }
    $name = $name.Trim()
    if ($name.Length -gt 80) { $name = $name.Substring(0,80) }
    $script:NKnown = @($script:NKnown | Where-Object { $_.IP -ne $ip -and (-not $mac -or $_.MAC -ne $mac) })
    $script:NKnown += [pscustomobject]@{ IP=$ip; MAC=$mac; Nombre=$name; Fecha=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
    try { Save-NKnown; Refresh-NInventory 'Equipos LAN' } catch {
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'No se pudo guardar','OK','Error')
    }
}
function Verify-NIP {
    Add-Type -AssemblyName Microsoft.VisualBasic
    $raw = [string][Microsoft.VisualBasic.Interaction]::InputBox('Dirección IPv4 o IPv6 (sin puerto). Se clasificará localmente.','Verificar IP','192.168.1.1')
    if (-not $raw.Trim()) { return }
    $ip = $null
    if (-not [Net.IPAddress]::TryParse($raw.Trim(),[ref]$ip)) {
        [void][Windows.Forms.MessageBox]::Show('La IP no es válida. Introduce solo una dirección IPv4 o IPv6.','IP inválida','OK','Warning')
        return
    }
    $knownIPs = @(Get-NetIPAddress -ErrorAction SilentlyContinue | ForEach-Object { [string]$_.IPAddress })
    $result = @(
        ('IP: ' + $ip.ToString()),
        ('Clase: ' + (Get-NIPScope $ip.ToString())),
        ('Pertenece a este equipo: ' + ($knownIPs -contains $ip.ToString())),
        'Una IP pública no es maliciosa por sí sola.'
    )
    $prompt = ($result -join [Environment]::NewLine) + [Environment]::NewLine + [Environment]::NewLine + '¿Enviar UN ping ICMP a esa IP? El destinatario podrá detectar la prueba.'
    if ([Windows.Forms.MessageBox]::Show($prompt,'Análisis IP - DevPoderSEO','YesNo','Question','Button2') -eq [Windows.Forms.DialogResult]::Yes) {
        try {
            $ping = New-Object Net.NetworkInformation.Ping
            try {
                $reply = $ping.Send($ip,1500)
                $result += ('Ping: ' + $reply.Status.ToString())
                if ($reply.Status -eq 'Success') { $result += ('Latencia: ' + $reply.RoundtripTime + ' ms') }
            } finally { $ping.Dispose() }
        } catch { $result += 'Error ping: ' + $_.Exception.Message }
        $result += 'Un ping fallido NO significa que el equipo esté apagado.'
    }
    [void][Windows.Forms.MessageBox]::Show(($result -join [Environment]::NewLine),'Verificación de IP','OK','Information')
}
function Check-NPublicIP {
    $text = 'La consulta realiza una petición HTTPS a api.ipify.org. Ese proveedor verá tu IP de salida. Nunca se consulta automáticamente. ¿Continuar?'
    if ([Windows.Forms.MessageBox]::Show($text,'Consulta externa voluntaria','YesNo','Warning','Button2') -ne [Windows.Forms.DialogResult]::Yes) { return }
    try {
        $previous = [Net.ServicePointManager]::SecurityProtocol
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $result = Invoke-RestMethod -Method Get -Uri 'https://api.ipify.org?format=json' -TimeoutSec 8 -ErrorAction Stop
        } finally { [Net.ServicePointManager]::SecurityProtocol = $previous }
        $ip = $null
        if (-not [Net.IPAddress]::TryParse([string]$result.ip,[ref]$ip)) { throw 'La respuesta no contiene una dirección IP válida.' }
        [void][Windows.Forms.MessageBox]::Show(('IP pública de salida: ' + $ip.ToString() + [Environment]::NewLine + 'Puede ser de tu router, VPN o proxy.'),'IP pública','OK','Information')
        Write-Audit 'RED: consulta voluntaria de IP pública ejecutada.'
    } catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Error de consulta','OK','Error') }
}
function Export-NReports {
    try {
        $folder = Join-Path (Resolve-OutputDirectory) ('red-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        [void](New-Item -ItemType Directory -Path $folder -Force)
        foreach ($category in $script:NCategories) {
            $table = $script:NTables[$category]
            $records = foreach ($row in $table.Rows) {
                $values = [ordered]@{}
                foreach ($col in $table.Columns) { $values[$col.ColumnName] = [string]$row[$col.ColumnName] }
                [pscustomobject]$values
            }
            if (@($records).Count -eq 0) { continue }
            $file = switch ($category) {
                'Conexiones TCP' { 'conexiones-tcp.csv' }
                'Puertos UDP' { 'puertos-udp.csv' }
                'Equipos LAN' { 'equipos-lan.csv' }
                'Configuración IP' { 'configuracion-ip.csv' }
                'Firewall' { 'firewall.csv' }
            }
            $records | Export-Csv -LiteralPath (Join-Path $folder $file) -Encoding UTF8 -NoTypeInformation
        }
        ('WinCare Portable | Diseñado por DevPoderSEO' + [Environment]::NewLine + 'Diagnóstico orientativo, NO certifica intrusiones.' + [Environment]::NewLine + ($script:NWarnings -join [Environment]::NewLine)) | Set-Content -LiteralPath (Join-Path $folder 'ADVERTENCIAS.txt') -Encoding UTF8
        Write-Audit ('RED: exportación completada en ' + $folder)
        [void][Windows.Forms.MessageBox]::Show(('Exportado a ' + $folder),'Reporte de red','OK','Information')
        Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $folder + '"')
    } catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Error al exportar','OK','Error') }
}

$script:NForm = New-Object Windows.Forms.Form
$script:NForm.Text = 'WinCare Portable | Seguridad de red | DevPoderSEO'
$script:NForm.StartPosition = 'CenterParent'
$script:NForm.Size = New-Object Drawing.Size(1240,750)
$script:NForm.MinimumSize = New-Object Drawing.Size(1080,670)
$script:NForm.BackColor = $script:NColors.Bg
$script:NForm.ForeColor = $script:NColors.Text
$script:NForm.Font = New-Object Drawing.Font('Segoe UI',9)

$h = New-Object Windows.Forms.Label
$h.Text = 'Seguridad de red - WinCare Portable'
$h.Location = New-Object Drawing.Point(20,14)
$h.Size = New-Object Drawing.Size(820,36)
$h.Font = New-Object Drawing.Font('Segoe UI Semibold',18,[Drawing.FontStyle]::Bold)
$script:NForm.Controls.Add($h)
$brand = New-Object Windows.Forms.Label
$brand.Text = 'Diseñado por DevPoderSEO'
$brand.Location = New-Object Drawing.Point(905,24)
$brand.Size = New-Object Drawing.Size(285,26)
$brand.Anchor = 'Top,Right'
$brand.TextAlign = 'MiddleRight'
$brand.ForeColor = $script:NColors.Accent
$script:NForm.Controls.Add($brand)
$disclaimer = New-Object Windows.Forms.Label
$disclaimer.Text = 'Las conexiones y equipos desconocidos se marcan para revisar: NO son pruebas de intrusión. Sin bloqueos automáticos.'
$disclaimer.Location = New-Object Drawing.Point(22,56)
$disclaimer.Size = New-Object Drawing.Size(1165,27)
$disclaimer.Anchor = 'Top,Left,Right'
$disclaimer.ForeColor = $script:NColors.Muted
$script:NForm.Controls.Add($disclaimer)

$script:NSearch = New-Object Windows.Forms.TextBox
$script:NSearch.Location = New-Object Drawing.Point(20,96)
$script:NSearch.Size = New-Object Drawing.Size(245,27)
$script:NSearch.BackColor = $script:NColors.Panel
$script:NSearch.ForeColor = $script:NColors.Text
$script:NSearch.Add_TextChanged({ Set-NFilter })
$script:NForm.Controls.Add($script:NSearch)

$script:NRefresh = New-Object Windows.Forms.Button
$script:NRefresh.Text = 'Analizar pestaña'
$script:NRefresh.Location = New-Object Drawing.Point(275,94)
$script:NRefresh.Size = New-Object Drawing.Size(120,31)
$script:NRefresh.BackColor = $script:NColors.Accent
$script:NRefresh.ForeColor = [Drawing.Color]::White
$script:NRefresh.FlatStyle = 'Flat'
$script:NRefresh.Add_Click({ if($script:NTab.SelectedTab){Refresh-NInventory ([string]$script:NTab.SelectedTab.Text)} })
$script:NForm.Controls.Add($script:NRefresh)

$actions = @(
    @('Verificar IP',405,115,{ Verify-NIP }),
    @('Ver proceso',530,125,{ Inspect-NProcess }),
    @('Registrar equipo',665,145,{ Register-NDevice }),
    @('IP pública',820,125,{ Check-NPublicIP }),
    @('Exportar CSV',955,145,{ Export-NReports })
)
foreach ($a in $actions) {
    $btn = New-Object Windows.Forms.Button
    $btn.Text = [string]$a[0]
    $btn.Location = New-Object Drawing.Point([int]$a[1],94)
    $btn.Size = New-Object Drawing.Size([int]$a[2],31)
    $btn.Add_Click($a[3])
    $script:NForm.Controls.Add($btn)
}
$script:NTab = New-Object Windows.Forms.TabControl
$script:NTab.Location = New-Object Drawing.Point(20,185)
$script:NTab.Size = New-Object Drawing.Size(1188,468)
$script:NTab.Anchor = 'Top,Bottom,Left,Right'
$script:NForm.Controls.Add($script:NTab)

$script:NDiagnosticButton=New-Object Windows.Forms.Button
$script:NDiagnosticButton.Text='Abrir diagnóstico inteligente (v1.6)'
$script:NDiagnosticButton.Location=New-Object Drawing.Point(20,141)
$script:NDiagnosticButton.Size=New-Object Drawing.Size(298,33)
$script:NDiagnosticButton.BackColor=$script:NColors.Accent
$script:NDiagnosticButton.ForeColor=[Drawing.Color]::White
$script:NDiagnosticButton.FlatStyle='Flat'
$script:NForm.Controls.Add($script:NDiagnosticButton)
$script:NDiagnosticButton.Add_Click({
    $path=Join-Path $PSScriptRoot 'NetworkDiagnostics.ps1'
    $core=Join-Path $PSScriptRoot 'NetworkDiagnosticsCore.ps1'
    if(-not (Test-Path -LiteralPath $path -PathType Leaf) -or -not (Test-Path -LiteralPath $core -PathType Leaf)){
        [void][Windows.Forms.MessageBox]::Show('No están todos los archivos de diagnóstico. Descarga el ZIP completo desde GitHub para ejecutar la versión 1.6.','Faltan componentes','OK','Warning')
        return
    }
    try{ & $path -Owner $script:NForm }
    catch{
        Write-Audit ('DIAGNÓSTICO DE RED: '+$_.Exception.Message)
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'No se pudo iniciar diagnóstico de red','OK','Error')
    }
})

$advancedBtn=New-Object Windows.Forms.Button
$advancedBtn.Text='Centro avanzado de redes (v2.1)'
$advancedBtn.Location=New-Object Drawing.Point(330,141)
$advancedBtn.Size=New-Object Drawing.Size(300,33)
$advancedBtn.BackColor=[Drawing.Color]::FromArgb(35,114,180)
$advancedBtn.ForeColor=[Drawing.Color]::White
$advancedBtn.FlatStyle='Flat'
$script:NForm.Controls.Add($advancedBtn)
$advancedBtn.Add_Click({
    $path=Join-Path $PSScriptRoot 'AdvancedNetwork.ps1'
    $core=Join-Path $PSScriptRoot 'AdvancedNetworkCore.ps1'
    if(-not (Test-Path -LiteralPath $path -PathType Leaf) -or -not (Test-Path -LiteralPath $core -PathType Leaf)){
        [void][Windows.Forms.MessageBox]::Show('Faltan archivos del centro avanzado. Descarga WinCare completo desde GitHub.','Módulo no disponible','OK','Warning')
        return
    }
    try{& $path -Owner $script:NForm}
    catch{
        Write-Audit ('CENTRO AVANZADO RED: '+$_.Exception.Message)
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Redes avanzadas no disponible','OK','Error')
    }
})
$diagNote=New-Object Windows.Forms.Label
$diagNote.Text='Análisis por demanda · topología lógica · métricas'
$diagNote.Location=New-Object Drawing.Point(643,148)
$diagNote.Size=New-Object Drawing.Size(540,25)
$diagNote.ForeColor=$script:NColors.Muted
$script:NForm.Controls.Add($diagNote)
foreach ($kind in $script:NCategories) {
    $script:NTables[$kind] = New-NTable $script:NColumns[$kind]
    $tab = New-Object Windows.Forms.TabPage
    $tab.Text = $kind
    $tab.BackColor = $script:NColors.Panel
    $grid = New-Object Windows.Forms.DataGridView
    $grid.Dock = 'Fill'
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.RowHeadersVisible = $false
    $grid.SelectionMode = 'FullRowSelect'
    $grid.MultiSelect = $false
    $grid.AutoGenerateColumns = $false
    $grid.AutoSizeColumnsMode = 'DisplayedCells'
    $grid.BackgroundColor = $script:NColors.Panel
    $grid.GridColor = [Drawing.Color]::FromArgb(52,65,84)
    $grid.EnableHeadersVisualStyles = $false
    $grid.ColumnHeadersDefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(39,53,72)
    $grid.ColumnHeadersDefaultCellStyle.ForeColor = $script:NColors.Text
    $grid.DefaultCellStyle.BackColor = $script:NColors.Panel
    $grid.DefaultCellStyle.ForeColor = $script:NColors.Text
    $grid.DefaultCellStyle.SelectionBackColor = [Drawing.Color]::FromArgb(39,104,169)
    $grid.DefaultCellStyle.SelectionForeColor = [Drawing.Color]::White
    $grid.AlternatingRowsDefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(33,45,61)
    # Crear las columnas primero; la generación automática puede ser diferida.
    foreach ($dataColumn in $script:NTables[$kind].Columns) {
        $columnName = [string]$dataColumn.ColumnName
        $column = New-Object Windows.Forms.DataGridViewTextBoxColumn
        $column.Name = $columnName
        $column.DataPropertyName = $columnName
        $column.HeaderText = $columnName
        [void]$grid.Columns.Add($column)
    }
    $grid.DataSource = $script:NTables[$kind].DefaultView
    $tab.Controls.Add($grid)
    $script:NGrids[$kind] = $grid
    [void]$script:NTab.TabPages.Add($tab)
}
$script:NTab.Add_SelectedIndexChanged({ Set-NFilter })

$script:NStatus = New-Object Windows.Forms.Label
$script:NStatus.Text = 'Sin analizar. No existe monitoreo continuo.'
$script:NStatus.Location = New-Object Drawing.Point(22,669)
$script:NStatus.Size = New-Object Drawing.Size(1160,28)
$script:NStatus.Anchor = 'Bottom,Left,Right'
$script:NStatus.ForeColor = $script:NColors.Muted
$script:NForm.Controls.Add($script:NStatus)
$script:NForm.Add_Shown({$script:NStatus.Text='Sin analizar. Selecciona la pestaña y pulsa Analizar pestaña; no se consulta red al abrir.'})
if ($SmokeTest) {
    # Prueba de construcción de UI, sin escaneo ni acceso a la red.
    foreach ($category in $script:NCategories) {
        $grid = $script:NGrids[$category]
        $table = $script:NTables[$category]
        if ($null -eq $grid -or $grid.Columns.Count -ne $table.Columns.Count) { throw ('Error en columnas de ' + $category) }
        foreach ($dataColumn in $table.Columns) {
            if ($null -eq $grid.Columns[[string]$dataColumn.ColumnName]) { throw ('Columna ausente en ' + $category) }
        }
    }
    if($script:NDiagnosticButton.Text -ne 'Abrir diagnóstico inteligente (v1.6)' -or $advancedBtn.Text -ne 'Centro avanzado de redes (v2.1)'){throw 'Faltan accesos a diagnóstico de redes.'}
    if($script:NRefresh.Text -ne 'Analizar pestaña'){throw 'Falta análisis de red bajo demanda.'}
    Write-Host 'OK: inventarios de red a demanda y acceso a diagnóstico; sin tráfico automático.'
    $script:NForm.Dispose()
    return
}
try {
    if ($Owner) { [void]$script:NForm.ShowDialog($Owner) }
    else { [void]$script:NForm.ShowDialog() }
} finally { $script:NForm.Dispose() }
