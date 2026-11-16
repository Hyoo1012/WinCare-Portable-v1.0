# WinCare Portable - Inventario de hardware y diagnóstico
# Diseñado por DevPoderSEO
# Windows PowerShell 5.1 (Windows 10/11)
# Solo lectura: no modifica firmware, discos, controladores ni configuración.
#requires -Version 5.1
param([System.Windows.Forms.Form]$Owner, [switch]$SmokeTest)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:HColors = @{
    Bg = [Drawing.Color]::FromArgb(17,24,35)
    Panel = [Drawing.Color]::FromArgb(28,38,52)
    Text = [Drawing.Color]::FromArgb(238,243,249)
    Muted = [Drawing.Color]::FromArgb(172,184,201)
    Accent = [Drawing.Color]::FromArgb(37,132,221)
}
$script:HCategories = @('Resumen','Procesador','Memoria RAM','Placa y BIOS','Discos','Unidades','Gráficos','Red','Batería','Dispositivos','Incidencias')
$script:HTables = @{}
$script:HWarnings = New-Object System.Collections.Generic.List[string]
$script:HDataColumns = @('Componente','Valor','Estado','Detalle')

function Format-HSize($Value) {
    if ($null -eq $Value -or [string]$Value -eq '') { return 'No disponible' }
    try {
        $number = [double]$Value
        if ($number -lt 0) { return 'No disponible' }
        if ($number -ge 1TB) { return ('{0:N2} TB' -f ($number / 1TB)) }
        if ($number -ge 1GB) { return ('{0:N2} GB' -f ($number / 1GB)) }
        if ($number -ge 1MB) { return ('{0:N1} MB' -f ($number / 1MB)) }
        return ('{0:N0} bytes' -f $number)
    } catch { return 'No disponible' }
}
function Format-HValue($Value) {
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return 'No disponible' }
    return [string]$Value
}
function New-HTable {
    $table = New-Object System.Data.DataTable
    foreach ($column in $script:HDataColumns) { [void]$table.Columns.Add($column,[string]) }
    return ,$table
}
function Add-HRow([string]$Category,[string]$Name,[string]$Value,[string]$State = 'Informativo',[string]$Detail = '') {
    [void]$script:HTables[$Category].Rows.Add([object[]]@($Name,$Value,$State,$Detail))
}
function Invoke-HRead([string]$Category,[scriptblock]$Action) {
    $script:HStatus.Text = 'Consultando: ' + $Category
    [Windows.Forms.Application]::DoEvents()
    try { & $Action } catch {
        $message = $_.Exception.Message
        [void]$script:HWarnings.Add(($Category + ': ' + $message))
        Add-HRow $Category 'Consulta parcial' 'No disponible' 'Información' ('Windows no permitió obtener todos los datos: ' + $message)
    }
}
function Read-HSummary {
    $pc = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    Add-HRow 'Resumen' 'Sistema operativo' ([string]$os.Caption)
    Add-HRow 'Resumen' 'Versión de Windows' ([string]$os.Version)
    Add-HRow 'Resumen' 'Compilación' ([string]$os.BuildNumber)
    Add-HRow 'Resumen' 'Arquitectura' ([string]$os.OSArchitecture)
    Add-HRow 'Resumen' 'Fabricante del equipo' (Format-HValue $pc.Manufacturer)
    Add-HRow 'Resumen' 'Modelo del equipo' (Format-HValue $pc.Model)
    Add-HRow 'Resumen' 'Memoria RAM instalada' (Format-HSize $pc.TotalPhysicalMemory)
    Add-HRow 'Resumen' 'RAM libre según Windows' (Format-HSize ([double]$os.FreePhysicalMemory * 1KB)) 'Informativo' 'Valor instantáneo aproximado; varía con los procesos.'
    Add-HRow 'Resumen' 'Nombre del equipo' (Format-HValue $env:COMPUTERNAME)
    if ($os.LastBootUpTime) {
        $boot = [datetime]$os.LastBootUpTime
        $uptime = (Get-Date) - $boot
        Add-HRow 'Resumen' 'Último arranque' ($boot.ToString('yyyy-MM-dd HH:mm'))
        Add-HRow 'Resumen' 'Tiempo desde arranque' ('{0} días {1} h {2} min' -f [math]::Floor($uptime.TotalDays),$uptime.Hours,$uptime.Minutes) 'Informativo' 'No constituye un diagnóstico de rendimiento.'
    }
}
function Read-HProcessor {
    foreach ($cpu in @(Get-CimInstance Win32_Processor -ErrorAction Stop)) {
        $name = Format-HValue $cpu.Name
        Add-HRow 'Procesador' 'Modelo' $name
        Add-HRow 'Procesador' 'Fabricante' (Format-HValue $cpu.Manufacturer)
        Add-HRow 'Procesador' 'Núcleos físicos' ([string]$cpu.NumberOfCores)
        Add-HRow 'Procesador' 'Procesadores lógicos' ([string]$cpu.NumberOfLogicalProcessors)
        Add-HRow 'Procesador' 'Frecuencia máxima reportada' (([string]$cpu.MaxClockSpeed) + ' MHz') 'Informativo' 'Velocidad reportada por firmware, no una medición en tiempo real.'
        Add-HRow 'Procesador' 'Caché L2' (([string]$cpu.L2CacheSize) + ' KB')
        Add-HRow 'Procesador' 'Caché L3' (([string]$cpu.L3CacheSize) + ' KB')
        Add-HRow 'Procesador' 'Socket' (Format-HValue $cpu.SocketDesignation)
    }
}
function Read-HMemory {
    $sticks = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop)
    if ($sticks.Count -eq 0) {
        Add-HRow 'Memoria RAM' 'Módulos RAM' 'No reportados' 'Información' 'Algunos equipos no exponen datos SMBIOS de los módulos.'
    }
    $installed = [double]0
    $index = 0
    foreach ($stick in $sticks) {
        $index++
        $installed += [double]$stick.Capacity
        $slot = Format-HValue $stick.DeviceLocator
        Add-HRow 'Memoria RAM' ('Módulo '+$index) ((Format-HSize $stick.Capacity)+' | '+$slot) 'Informativo' ('Fabricante: '+(Format-HValue $stick.Manufacturer)+'; Parte: '+(Format-HValue $stick.PartNumber)+'; Velocidad: '+(Format-HValue $stick.Speed)+' MHz')
    }
    if ($sticks.Count -gt 0) { Add-HRow 'Memoria RAM' 'Total calculado por módulos' (Format-HSize $installed) }
    $arrays = @(Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue)
    foreach ($arr in $arrays) {
        if ([int]$arr.MemoryDevices -gt 0) {
            Add-HRow 'Memoria RAM' 'Ranuras indicadas por firmware' ([string]$arr.MemoryDevices) 'Informativo' 'El firmware puede informar un valor impreciso. Verifica físicamente antes de comprar RAM.'
        }
    }
}
function Read-HBoard {
    foreach ($board in @(Get-CimInstance Win32_BaseBoard -ErrorAction Stop)) {
        Add-HRow 'Placa y BIOS' 'Placa madre' (Format-HValue $board.Product) 'Informativo' ('Fabricante: '+(Format-HValue $board.Manufacturer))
    }
    foreach ($bios in @(Get-CimInstance Win32_BIOS -ErrorAction Stop)) {
        Add-HRow 'Placa y BIOS' 'Fabricante BIOS' (Format-HValue $bios.Manufacturer)
        Add-HRow 'Placa y BIOS' 'Versión BIOS' (Format-HValue $bios.SMBIOSBIOSVersion)
        if ($bios.ReleaseDate) {
            $release = try { ([datetime]$bios.ReleaseDate).ToString('yyyy-MM-dd') } catch { [string]$bios.ReleaseDate }
            Add-HRow 'Placa y BIOS' 'Fecha BIOS' $release
        }
    }
    try {
        $isSecure = Confirm-SecureBootUEFI -ErrorAction Stop
        Add-HRow 'Placa y BIOS' 'Secure Boot' $(if($isSecure){'Activado'}else{'Desactivado'}) $(if($isSecure){'Informativo'}else{'Revisar'}) 'La configuración depende del firmware y las políticas del equipo.'
    } catch {
        Add-HRow 'Placa y BIOS' 'Secure Boot' 'No verificable' 'Información' 'Puede requerir permisos, firmware compatible o arranque UEFI.'
    }
    try {
        $tpm = Get-Tpm -ErrorAction Stop
        Add-HRow 'Placa y BIOS' 'TPM presente' ([string]$tpm.TpmPresent)
        Add-HRow 'Placa y BIOS' 'TPM listo' ([string]$tpm.TpmReady) 'Informativo' 'Puede ser administrado por el sistema o por políticas corporativas.'
    } catch {
        Add-HRow 'Placa y BIOS' 'TPM' 'No verificable' 'Información' 'No implica ausencia de TPM.'
    }
}
function Read-HDisks {
    $disks = @(Get-PhysicalDisk -ErrorAction Stop)
    if ($disks.Count -eq 0) { Add-HRow 'Discos' 'Discos físicos' 'No disponibles' 'Información' 'No se encontraron discos en el proveedor de almacenamiento.' }
    foreach ($disk in $disks) {
        $name = Format-HValue $disk.FriendlyName
        $health = [string]$disk.HealthStatus
        $state = if ($health -eq 'Healthy') { 'Informativo' } elseif ($health -eq 'Unknown') { 'Información' } else { 'Revisar' }
        Add-HRow 'Discos' $name (Format-HSize $disk.Size) $state ('Tipo: '+$disk.MediaType+'; Bus: '+$disk.BusType+'; Salud informada: '+$health+'; Operativo: '+$disk.OperationalStatus)
        try {
            $counter = Get-StorageReliabilityCounter -PhysicalDisk $disk -ErrorAction Stop
            if ($null -ne $counter) {
                if ($null -ne $counter.Temperature -and [string]$counter.Temperature -ne '') {
                    Add-HRow 'Discos' ($name+' · Temperatura') ([string]$counter.Temperature+' °C') 'Informativo' 'Lectura del dispositivo/controlador. Puede ser imprecisa.'
                }
                if ($null -ne $counter.Wear -and [string]$counter.Wear -ne '') {
                    Add-HRow 'Discos' ($name+' · Desgaste reportado') ([string]$counter.Wear) 'Informativo' 'Valor bruto del proveedor; la interpretación depende del dispositivo.'
                }
                if ($null -ne $counter.PowerOnHours -and [string]$counter.PowerOnHours -ne '') {
                    Add-HRow 'Discos' ($name+' · Horas de uso') ([string]$counter.PowerOnHours)
                }
                if ($null -ne $counter.ReadErrorsUncorrected -and [long]$counter.ReadErrorsUncorrected -gt 0) {
                    Add-HRow 'Discos' ($name+' · Errores lectura no corregidos') ([string]$counter.ReadErrorsUncorrected) 'Revisar' 'Haz respaldo y consulta diagnóstico del fabricante antes de intervenir.'
                }
                if ($null -ne $counter.WriteErrorsUncorrected -and [long]$counter.WriteErrorsUncorrected -gt 0) {
                    Add-HRow 'Discos' ($name+' · Errores escritura no corregidos') ([string]$counter.WriteErrorsUncorrected) 'Revisar' 'Haz respaldo y consulta diagnóstico del fabricante antes de intervenir.'
                }
            }
        } catch {
            Add-HRow 'Discos' ($name+' · Contadores') 'No disponibles' 'Información' 'No todos los discos/controladores exponen SMART o contadores de fiabilidad.'
        }
    }
}
function Read-HVolumes {
    $volumes = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 3' -ErrorAction Stop)
    foreach ($volume in $volumes) {
        $total = [double]$volume.Size
        $free = [double]$volume.FreeSpace
        $percent = if ($total -gt 0) { [math]::Round($free*100/$total,1) } else { 0 }
        $status = if ($total -gt 0 -and $percent -lt 10) {'Revisar'} else {'Informativo'}
        Add-HRow 'Unidades' ([string]$volume.DeviceID) ((Format-HSize $free)+' libres de '+(Format-HSize $total)) $status ('Sistema de archivos: '+$volume.FileSystem+'; Etiqueta: '+$volume.VolumeName+'; Libre: '+$percent+'%. Un poco de espacio libre evita fallos de mantenimiento.')
    }
}
function Read-HGraphics {
    foreach ($gpu in @(Get-CimInstance Win32_VideoController -ErrorAction Stop)) {
        $name = Format-HValue $gpu.Name
        Add-HRow 'Gráficos' 'Adaptador de video' $name 'Informativo' ('Fabricante: '+(Format-HValue $gpu.AdapterCompatibility))
        Add-HRow 'Gráficos' ($name+' · Driver') (Format-HValue $gpu.DriverVersion)
        if ($gpu.CurrentHorizontalResolution -and $gpu.CurrentVerticalResolution) {
            Add-HRow 'Gráficos' ($name+' · Resolución') ([string]$gpu.CurrentHorizontalResolution+' × '+[string]$gpu.CurrentVerticalResolution)
        }
        if ([double]$gpu.AdapterRAM -gt 0) {
            Add-HRow 'Gráficos' ($name+' · VRAM reportada') (Format-HSize $gpu.AdapterRAM) 'Información' 'Win32_VideoController puede reportar incorrectamente la VRAM moderna.'
        }
    }
}
function Read-HNetAdapters {
    $adapters = @(Get-NetAdapter -ErrorAction Stop)
    foreach ($adapter in $adapters) {
        Add-HRow 'Red' (Format-HValue $adapter.Name) (Format-HValue $adapter.InterfaceDescription) 'Informativo' ('Estado: '+$adapter.Status+'; Velocidad: '+$adapter.LinkSpeed+'; MAC: '+$adapter.MacAddress)
    }
}
function Read-HBattery {
    $batteries = @(Get-CimInstance Win32_Battery -ErrorAction Stop)
    if ($batteries.Count -eq 0) {
        Add-HRow 'Batería' 'Batería detectada' 'No' 'Informativo' 'Normal en equipos de escritorio. No permite afirmar que la batería esté ausente de otros dispositivos.'
        return
    }
    foreach ($battery in $batteries) {
        Add-HRow 'Batería' 'Batería' (Format-HValue $battery.Name) 'Informativo' ('Fabricante: '+(Format-HValue $battery.Manufacturer))
        if ($null -ne $battery.EstimatedChargeRemaining) {
            Add-HRow 'Batería' 'Carga estimada' ([string]$battery.EstimatedChargeRemaining+'%')
        }
        Add-HRow 'Batería' 'Estado reportado' ([string]$battery.BatteryStatus) 'Información' 'Código del proveedor WMI. No equivale a porcentaje de desgaste.'
    }
}
function Read-HDevices {
    $devices = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop)
    foreach ($device in $devices) {
        $name = Format-HValue $device.Name
        $code = [int]$device.ConfigManagerErrorCode
        $status = if ($code -eq 0) { 'Informativo' } else { 'Revisar' }
        Add-HRow 'Dispositivos' $name (Format-HValue $device.PNPClass) $status ('Fabricante: '+(Format-HValue $device.Manufacturer)+'; Código del administrador de dispositivos: '+$code+'. Un código no cero no demuestra fallo crítico ni intrusión.')
    }
}
function Read-HIssues {
    foreach ($dev in @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object { $_.ConfigManagerErrorCode -ne 0 })) {
        Add-HRow 'Incidencias' ('Dispositivo: '+(Format-HValue $dev.Name)) ('Código '+[string]$dev.ConfigManagerErrorCode) 'Revisar' 'Consulta el Administrador de dispositivos. No borres el controlador sin verificar el origen del problema.'
    }
    try {
        $filter = @{ LogName='System'; Level=@(1,2); StartTime=(Get-Date).AddDays(-7) }
        foreach ($eventItem in @(Get-WinEvent -FilterHashtable $filter -MaxEvents 20 -ErrorAction Stop)) {
            $message = (([string]$eventItem.Message) -replace '\s+',' ')
            if ($message.Length -gt 260) { $message = $message.Substring(0,260)+'...' }
            Add-HRow 'Incidencias' ('Evento '+$eventItem.Id+' · '+[string]$eventItem.ProviderName) ([datetime]$eventItem.TimeCreated).ToString('yyyy-MM-dd HH:mm') 'Revisar' ('Registro del sistema (7 días); histórico, no necesariamente vigente. '+$message)
        }
    } catch {
        Add-HRow 'Incidencias' 'Eventos recientes' 'No disponibles' 'Información' 'No hay eventos coincidentes o Windows no permite consultar el registro.'
    }
    if ($script:HTables['Incidencias'].Rows.Count -eq 0) {
        Add-HRow 'Incidencias' 'Avisos' 'No se detectaron eventos en estas consultas' 'Informativo' 'No constituye una certificación de salud del equipo.'
    }
}
function Set-HFilter {
    if (-not $script:HCategoryList.SelectedItem) { return }
    $category = [string]$script:HCategoryList.SelectedItem
    $view = $script:HTables[$category].DefaultView
    $value = ([string]$script:HSearch.Text).Replace("'","''").Replace('[','[[]').Replace(']','[]]').Replace('%','[%]').Replace('*','[*]')
    if (-not $value) { $view.RowFilter = ''; return }
    try {
        $view.RowFilter = "[Componente] LIKE '%$value%' OR [Valor] LIKE '%$value%' OR [Estado] LIKE '%$value%' OR [Detalle] LIKE '%$value%'"
    } catch { $view.RowFilter = '' }
}
function Select-HCategory {
    if (-not $script:HCategoryList.SelectedItem) { return }
    $category = [string]$script:HCategoryList.SelectedItem
    $script:HGrid.DataSource = $script:HTables[$category].DefaultView
    $script:HSectionLabel.Text = $category
    $script:HDetail.Text = 'Selecciona un componente para ver sus observaciones.'
    Set-HFilter
}
function Inspect-HDetail {
    if (-not $script:HGrid -or $script:HGrid.SelectedRows.Count -eq 0) { return }
    $row = $script:HGrid.SelectedRows[0]
    if ($row.IsNewRow) { return }
    $script:HDetail.Text = ([string]$row.Cells['Componente'].Value)+' · '+([string]$row.Cells['Estado'].Value)+': '+([string]$row.Cells['Detalle'].Value)
}
function Refresh-Hardware {
    $script:HRefresh.Enabled = $false
    $script:HWarnings.Clear()
    foreach ($category in $script:HCategories) { $script:HTables[$category].Clear() }
    $tasks = @(
        @('Resumen',{ Read-HSummary }),
        @('Procesador',{ Read-HProcessor }),
        @('Memoria RAM',{ Read-HMemory }),
        @('Placa y BIOS',{ Read-HBoard }),
        @('Discos',{ Read-HDisks }),
        @('Unidades',{ Read-HVolumes }),
        @('Gráficos',{ Read-HGraphics }),
        @('Red',{ Read-HNetAdapters }),
        @('Batería',{ Read-HBattery }),
        @('Dispositivos',{ Read-HDevices }),
        @('Incidencias',{ Read-HIssues })
    )
    try {
        foreach ($task in $tasks) { Invoke-HRead ([string]$task[0]) $task[1] }
        Select-HCategory
        $count=0
        $alerts=0
        foreach ($table in $script:HTables.Values) {
            $count += $table.Rows.Count
            foreach ($row in $table.Rows) {
                if ([string]$row['Estado'] -eq 'Revisar') { $alerts++ }
            }
        }
        $script:HStatus.Text = ('{0} registros · {1} observaciones para revisar · {2} consultas parciales · {3}' -f $count,$alerts,$script:HWarnings.Count,(Get-Date -Format 'HH:mm'))
        if (Get-Command Write-Audit -ErrorAction SilentlyContinue) { Write-Audit ('HARDWARE: '+$count+' registros; '+$alerts+' observaciones.') }
        if ($script:HWarnings.Count -gt 0) {
            [void][Windows.Forms.MessageBox]::Show(($script:HWarnings -join [Environment]::NewLine),'Información parcial de hardware','OK','Information')
        }
    } finally { $script:HRefresh.Enabled = $true }
}
function Export-Hardware {
    try {
        $folderRoot = if (Get-Command Resolve-OutputDirectory -ErrorAction SilentlyContinue) { Resolve-OutputDirectory } else { Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WinCarePortable\Reportes' }
        if (-not (Test-Path -LiteralPath $folderRoot)) { [void](New-Item -ItemType Directory -Path $folderRoot -Force) }
        $folder = Join-Path $folderRoot ('hardware-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
        [void](New-Item -Path $folder -ItemType Directory -Force)
        $fileNames = @{
            'Resumen'='resumen';'Procesador'='procesador';'Memoria RAM'='ram';'Placa y BIOS'='placa-bios';'Discos'='discos';'Unidades'='unidades';'Gráficos'='graficos';'Red'='red';'Batería'='bateria';'Dispositivos'='dispositivos';'Incidencias'='incidencias'
        }
        foreach ($cat in $script:HCategories) {
            $rows = foreach ($r in $script:HTables[$cat].Rows) {
                [pscustomobject]@{ Componente=[string]$r['Componente']; Valor=[string]$r['Valor']; Estado=[string]$r['Estado']; Detalle=[string]$r['Detalle'] }
            }
            if (@($rows).Count -gt 0) {
                $rows | Export-Csv -LiteralPath (Join-Path $folder ($fileNames[$cat]+'.csv')) -Encoding UTF8 -NoTypeInformation
            }
        }
        ('WinCare Portable - Diseñado por DevPoderSEO'+[Environment]::NewLine+'Equipo: '+$env:COMPUTERNAME+[Environment]::NewLine+'Fecha: '+(Get-Date)+[Environment]::NewLine+'Los valores WMI/SMART pueden faltar o ser aproximados.'+[Environment]::NewLine+($script:HWarnings -join [Environment]::NewLine)) | Set-Content -LiteralPath (Join-Path $folder 'INFORME.txt') -Encoding UTF8
        [void][Windows.Forms.MessageBox]::Show(('Reportes guardados en '+$folder),'Exportación completada','OK','Information')
        Start-Process -FilePath 'explorer.exe' -ArgumentList ('"'+$folder+'"')
    } catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Error al exportar','OK','Error') }
}
function Open-HUtility {
    $selected = [string]$script:HUtilities.SelectedItem
    if (-not $selected) { return }
    $actions = @{
        'Información del sistema (msinfo32)' = @('msinfo32.exe','')
        'Diagnóstico DirectX (dxdiag)' = @('dxdiag.exe','')
        'Administrador de dispositivos' = @('mmc.exe','devmgmt.msc')
        'Monitor de recursos' = @('resmon.exe','')
        'Monitor de rendimiento' = @('perfmon.exe','')
        'Visor de eventos' = @('mmc.exe','eventvwr.msc')
        'Monitor de confiabilidad' = @('perfmon.exe','/rel')
        'Administrador de tareas' = @('taskmgr.exe','')
        'Administración de discos' = @('mmc.exe','diskmgmt.msc')
    }
    if (-not $actions.ContainsKey($selected)) { return }
    if ($selected -eq 'Administración de discos') {
        $warning = 'Administración de discos permite cambiar particiones y formatear. WinCare solo abrirá la herramienta; no realices modificaciones sin respaldo. ¿Continuar?'
        if ([Windows.Forms.MessageBox]::Show($warning,'Herramienta con funciones destructivas','YesNo','Warning','Button2') -ne [Windows.Forms.DialogResult]::Yes) { return }
    }
    try {
        $exe = Join-Path $env:WINDIR ('System32\'+[string]$actions[$selected][0])
        if (-not (Test-Path -LiteralPath $exe)) { throw ('No se encuentra '+$exe) }
        $arguments = [string]$actions[$selected][1]
        if ($arguments) { [void](Start-Process -FilePath $exe -ArgumentList $arguments -ErrorAction Stop) }
        else { [void](Start-Process -FilePath $exe -ErrorAction Stop) }
    } catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'No fue posible abrir la herramienta','OK','Error') }
}

$script:HForm = New-Object Windows.Forms.Form
$script:HForm.Text = 'WinCare Portable | Hardware, salud y herramientas | DevPoderSEO'
$script:HForm.StartPosition = 'CenterParent'
$script:HForm.Size = New-Object Drawing.Size(1240,775)
$script:HForm.MinimumSize = New-Object Drawing.Size(1080,700)
$script:HForm.BackColor = $script:HColors.Bg
$script:HForm.ForeColor = $script:HColors.Text
$script:HForm.Font = New-Object Drawing.Font('Segoe UI',9)

$header = New-Object Windows.Forms.Label
$header.Text = 'Información y salud del equipo'
$header.Location = New-Object Drawing.Point(20,15)
$header.Size = New-Object Drawing.Size(800,34)
$header.Font = New-Object Drawing.Font('Segoe UI Semibold',18,[Drawing.FontStyle]::Bold)
$script:HForm.Controls.Add($header)
$brand = New-Object Windows.Forms.Label
$brand.Text = 'Diseñado por DevPoderSEO'
$brand.Location = New-Object Drawing.Point(898,23)
$brand.Size = New-Object Drawing.Size(300,28)
$brand.Anchor = 'Top,Right'
$brand.TextAlign = 'MiddleRight'
$brand.ForeColor = $script:HColors.Accent
$script:HForm.Controls.Add($brand)

$notice = New-Object Windows.Forms.Label
$notice.Text = 'Inventario local y orientativo. No cambia BIOS, controladores, discos ni Windows. Valores no disponibles se indican sin inventarlos.'
$notice.Location = New-Object Drawing.Point(22,58)
$notice.Size = New-Object Drawing.Size(1160,26)
$notice.ForeColor = $script:HColors.Muted
$notice.Anchor = 'Top,Left,Right'
$script:HForm.Controls.Add($notice)

$script:HSearch = New-Object Windows.Forms.TextBox
$script:HSearch.Location = New-Object Drawing.Point(20,97)
$script:HSearch.Size = New-Object Drawing.Size(225,28)
$script:HSearch.BackColor = $script:HColors.Panel
$script:HSearch.ForeColor = $script:HColors.Text
$script:HForm.Controls.Add($script:HSearch)
$script:HSearch.Add_TextChanged({ Set-HFilter })

$script:HRefresh = New-Object Windows.Forms.Button
$script:HRefresh.Text = 'Actualizar hardware'
$script:HRefresh.Location = New-Object Drawing.Point(255,94)
$script:HRefresh.Size = New-Object Drawing.Size(155,32)
$script:HRefresh.BackColor = $script:HColors.Accent
$script:HRefresh.ForeColor = [Drawing.Color]::White
$script:HRefresh.FlatStyle = 'Flat'
$script:HRefresh.Add_Click({ Refresh-Hardware })
$script:HForm.Controls.Add($script:HRefresh)

$script:HUtilities = New-Object Windows.Forms.ComboBox
$script:HUtilities.DropDownStyle = 'DropDownList'
$script:HUtilities.Location = New-Object Drawing.Point(420,98)
$script:HUtilities.Size = New-Object Drawing.Size(350,30)
$script:HUtilities.BackColor = $script:HColors.Panel
$script:HUtilities.ForeColor = $script:HColors.Text
$script:HUtilities.Items.AddRange([object[]]@('Información del sistema (msinfo32)','Diagnóstico DirectX (dxdiag)','Administrador de dispositivos','Monitor de recursos','Monitor de rendimiento','Visor de eventos','Monitor de confiabilidad','Administrador de tareas','Administración de discos'))
$script:HUtilities.SelectedIndex = 0
$script:HForm.Controls.Add($script:HUtilities)

$openTool = New-Object Windows.Forms.Button
$openTool.Text = 'Abrir herramienta'
$openTool.Location = New-Object Drawing.Point(782,94)
$openTool.Size = New-Object Drawing.Size(140,32)
$openTool.Add_Click({ Open-HUtility })
$script:HForm.Controls.Add($openTool)

$exportButton = New-Object Windows.Forms.Button
$exportButton.Text = 'Exportar informe'
$exportButton.Location = New-Object Drawing.Point(932,94)
$exportButton.Size = New-Object Drawing.Size(165,32)
$exportButton.Add_Click({ Export-Hardware })
$script:HForm.Controls.Add($exportButton)

$script:HCategoryList = New-Object Windows.Forms.ListBox
$script:HCategoryList.Location = New-Object Drawing.Point(20,146)
$script:HCategoryList.Size = New-Object Drawing.Size(185,500)
$script:HCategoryList.Anchor = 'Top,Bottom,Left'
$script:HCategoryList.BackColor = $script:HColors.Panel
$script:HCategoryList.ForeColor = $script:HColors.Text
$script:HCategoryList.BorderStyle = 'None'
$script:HCategoryList.Font = New-Object Drawing.Font('Segoe UI',11)
$script:HCategoryList.ItemHeight = 29
$script:HCategoryList.Items.AddRange([object[]]$script:HCategories)
$script:HForm.Controls.Add($script:HCategoryList)

$script:HSectionLabel = New-Object Windows.Forms.Label
$script:HSectionLabel.Location = New-Object Drawing.Point(222,143)
$script:HSectionLabel.Size = New-Object Drawing.Size(960,29)
$script:HSectionLabel.Anchor = 'Top,Left,Right'
$script:HSectionLabel.Text = 'Resumen'
$script:HSectionLabel.Font = New-Object Drawing.Font('Segoe UI Semibold',12,[Drawing.FontStyle]::Bold)
$script:HForm.Controls.Add($script:HSectionLabel)

$script:HGrid = New-Object Windows.Forms.DataGridView
$script:HGrid.Location = New-Object Drawing.Point(219,178)
$script:HGrid.Size = New-Object Drawing.Size(985,470)
$script:HGrid.Anchor = 'Top,Bottom,Left,Right'
$script:HGrid.ReadOnly = $true
$script:HGrid.AllowUserToAddRows = $false
$script:HGrid.AllowUserToDeleteRows = $false
$script:HGrid.SelectionMode = 'FullRowSelect'
$script:HGrid.MultiSelect = $false
$script:HGrid.RowHeadersVisible = $false
$script:HGrid.AutoGenerateColumns = $false
$script:HGrid.AutoSizeColumnsMode = 'Fill'
$script:HGrid.BackgroundColor = $script:HColors.Panel
$script:HGrid.GridColor = [Drawing.Color]::FromArgb(52,65,84)
$script:HGrid.EnableHeadersVisualStyles = $false
$script:HGrid.ColumnHeadersDefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(39,53,72)
$script:HGrid.ColumnHeadersDefaultCellStyle.ForeColor = $script:HColors.Text
$script:HGrid.DefaultCellStyle.BackColor = $script:HColors.Panel
$script:HGrid.DefaultCellStyle.ForeColor = $script:HColors.Text
$script:HGrid.DefaultCellStyle.SelectionBackColor = [Drawing.Color]::FromArgb(39,104,169)
$script:HGrid.DefaultCellStyle.SelectionForeColor = [Drawing.Color]::White
$script:HGrid.AlternatingRowsDefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(33,45,61)
foreach ($name in $script:HDataColumns) {
    $column = New-Object Windows.Forms.DataGridViewTextBoxColumn
    $column.Name = $name
    $column.DataPropertyName = $name
    $column.HeaderText = $name
    $column.FillWeight = switch ($name) {
        'Componente' { 185 }
        'Valor' { 190 }
        'Estado' { 83 }
        'Detalle' { 260 }
        default { 100 }
    }
    [void]$script:HGrid.Columns.Add($column)
}
$script:HForm.Controls.Add($script:HGrid)
$script:HGrid.Add_SelectionChanged({ Inspect-HDetail })

$script:HDetail = New-Object Windows.Forms.Label
$script:HDetail.Location = New-Object Drawing.Point(220,663)
$script:HDetail.Size = New-Object Drawing.Size(980,40)
$script:HDetail.Anchor = 'Bottom,Left,Right'
$script:HDetail.ForeColor = $script:HColors.Muted
$script:HDetail.Text = 'Selecciona un componente para conocer detalles.'
$script:HForm.Controls.Add($script:HDetail)

$script:HStatus = New-Object Windows.Forms.Label
$script:HStatus.Location = New-Object Drawing.Point(22,716)
$script:HStatus.Size = New-Object Drawing.Size(1180,24)
$script:HStatus.Anchor = 'Bottom,Left,Right'
$script:HStatus.ForeColor = $script:HColors.Muted
$script:HStatus.Text = 'Listo para analizar el hardware del equipo.'
$script:HForm.Controls.Add($script:HStatus)

foreach ($category in $script:HCategories) { $script:HTables[$category] = New-HTable }
$script:HCategoryList.Add_SelectedIndexChanged({ Select-HCategory })
$script:HCategoryList.SelectedIndex = 0
if ($SmokeTest) {
    if ($script:HGrid.Columns.Count -ne $script:HDataColumns.Count) { throw 'Las columnas de hardware no se generaron.' }
    foreach ($name in $script:HDataColumns) {
        if ($null -eq $script:HGrid.Columns[$name]) { throw ('Columna de hardware inexistente: '+$name) }
    }
    foreach ($cat in $script:HCategories) {
        if ($null -eq $script:HTables[$cat] -or $script:HTables[$cat].Columns.Count -ne $script:HDataColumns.Count) {
            throw ('Tabla de hardware no inicializada: '+$cat)
        }
    }
    Write-Host 'OK: interfaz de hardware, 11 categorías y 4 columnas construidas; cero acciones de mantenimiento.'
    $script:HForm.Dispose()
    return
}
$script:HForm.Add_Shown({ [Windows.Forms.Application]::DoEvents(); Refresh-Hardware })
try {
    if ($Owner) { [void]$script:HForm.ShowDialog($Owner) }
    else { [void]$script:HForm.ShowDialog() }
} finally { $script:HForm.Dispose() }
