# WinCare Portable - v1.5
# Diseñado por DevPoderSEO
# Desarrollo y diseño: DevPoderSEO
# Windows PowerShell 5.1 / Windows 10-11 (ejecutar dentro del Windows instalado)
# Uso: inventario, auditoria y desinstalacion selectiva conservadora.
# Nunca deshabilita Windows Update, Defender, servicios ni controladores.
#requires -Version 5.1
param([switch]$SmokeTest)

# Guardar la ruta exacta para reiniciar esta misma copia desde Ventoy o Descargas.
$script:WinCareScriptPath = $PSCommandPath
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Este programa solamente funciona en Windows.' }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'AppRules.ps1')

$script:Palette = @{
    Bg = [System.Drawing.Color]::FromArgb(17, 24, 35)
    Panel = [System.Drawing.Color]::FromArgb(28, 38, 52)
    Text = [System.Drawing.Color]::FromArgb(238, 243, 249)
    Muted = [System.Drawing.Color]::FromArgb(172, 184, 201)
    Accent = [System.Drawing.Color]::FromArgb(37, 132, 221)
    Border = [System.Drawing.Color]::FromArgb(52, 65, 84)
}

# Solamente estos nombres exactos Appx pueden quitarse por este programa.
# El resto se consulta o se desinstala manualmente desde Configuracion de Windows.
$script:OptionalApps = @{
    'Microsoft.BingNews' = @('Bajo', 'Se pierde la aplicación de noticias.')
    'Microsoft.BingWeather' = @('Bajo', 'Se pierde la aplicación del tiempo.')
    'Microsoft.MicrosoftSolitaireCollection' = @('Bajo', 'Se eliminan juegos; podrían perderse datos locales.')
    'Clipchamp.Clipchamp' = @('Bajo', 'Se elimina el editor de video Clipchamp.')
    'Microsoft.Clipchamp' = @('Bajo', 'Se elimina el editor de video Clipchamp.')
    'Microsoft.Getstarted' = @('Bajo', 'Se elimina la aplicación de introducción.')
    'Microsoft.WindowsFeedbackHub' = @('Bajo', 'No podrás enviar comentarios desde Feedback Hub.')
    'Microsoft.GetHelp' = @('Medio', 'Se elimina la aplicación de ayuda de Microsoft.')
    'Microsoft.GamingApp' = @('Medio', 'Se afectan funciones y servicios de juegos Xbox.')
    'Microsoft.XboxGamingOverlay' = @('Medio', 'Se pierde la superposición Xbox Game Bar.')
    'Microsoft.XboxGameOverlay' = @('Medio', 'Se pierden algunas funciones de Xbox.')
    'Microsoft.Xbox.TCUI' = @('Medio', 'Algunas funciones de inicio de sesión Xbox podrían fallar.')
    'Microsoft.XboxIdentityProvider' = @('Medio', 'Algunos juegos y servicios Xbox podrían dejar de iniciar sesión.')
    'Microsoft.XboxSpeechToTextOverlay' = @('Medio', 'Se pierde una función de accesibilidad de Xbox.')
    'Microsoft.YourPhone' = @('Medio', 'Se pierde la vinculación de teléfono con Windows.')
    'MSTeams' = @('Medio', 'Se elimina la aplicación de Teams, si corresponde a esta versión.')
    'MicrosoftTeams' = @('Medio', 'Se elimina la aplicación de Teams, si corresponde a esta versión.')
    'Microsoft.WindowsMaps' = @('Bajo', 'Se elimina la aplicación Mapas.')
    'Microsoft.People' = @('Medio', 'Se elimina la aplicación Contactos.')
    'Microsoft.OutlookForWindows' = @('Medio', 'Se elimina el nuevo Outlook; sus datos en la nube no se borran.')
    'Microsoft.Copilot' = @('Medio', 'Se elimina la aplicación Copilot, si esta edición la incluye.')
    'Microsoft.ZuneMusic' = @('Medio', 'Se elimina una aplicación de reproducción multimedia.')
    'Microsoft.ZuneVideo' = @('Medio', 'Se elimina una aplicación de reproducción multimedia.')
}

$script:CoreAppPattern = '(?i)(Store|StorePurchase|DesktopAppInstaller|SecHealth|Defender|ShellExperienceHost|StartMenuExperienceHost|AAD\.BrokerPlugin|CloudExperienceHost|OOBENetwork|Windows\.Search|MicrosoftWindows\.Client\.|VCLibs|\.NET\.Native|WindowsAppRuntime|UI\.Xaml|Edge|WebView|WindowsTerminal|WindowsCalculator|WindowsNotepad|Windows\.Notepad|Windows\.Photos|WindowsCamera|LockApp|Credential|AccountsControl)'
$script:CoreProgramPattern = '(?i)(\bWindows\b|Defender|Security|Antivirus|Firewall|\bUpdate\b|WebView|\.NET|Visual C\+\+|Redistributable|\bRuntime\b|\bDriver\b|Firmware|Chipset|\bBIOS\b|\bTPM\b|BitLocker|Realtek|NVIDIA|\bIntel\b|\bAMD\b|Qualcomm|\bVPN\b|Endpoint|Backup Agent|Recovery Agent|\bAgent\b|Bluetooth|\bWi-Fi\b|\bWLAN\b|PowerShell|SQL Server|Windows Installer|Device Management)'
$script:Categories = @('Apps Store', 'Provisionadas', 'Programas', 'Características', 'Capacidades', 'Servicios', 'Controladores')
$script:Tables = @{}
$script:Grids = @{}
$script:PolicyRules = @()
$script:PolicyLoadOK = $true
$script:Warnings = New-Object 'System.Collections.Generic.List[string]'

function Test-Administrator {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-AdministratorAccess {
    # Windows exige un aviso UAC; jamás se eluden los permisos del sistema.
    if (Test-Administrator) { return $true }
    if ([string]::IsNullOrWhiteSpace($script:WinCareScriptPath) -or -not (Test-Path -LiteralPath $script:WinCareScriptPath -PathType Leaf)) {
        [void][System.Windows.Forms.MessageBox]::Show('No se pudo identificar la ruta del script. Abre INICIAR_WINCARE.bat como administrador.','Ruta no disponible','OK','Warning')
        return $false
    }
    try {
        # -Verb RunAs abre el aviso UAC normal de Windows. Nunca modifica la política
        # global de PowerShell. No se pasan argumentos editables por el usuario.
        $powerShellExe = Join-Path $PSHOME 'powershell.exe'
        $quotedFile = '"' + $script:WinCareScriptPath + '"'
        $arguments = @('-NoLogo', '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $quotedFile)
        [void](Start-Process -FilePath $powerShellExe -ArgumentList $arguments -WorkingDirectory $PSScriptRoot -Verb RunAs -PassThru -ErrorAction Stop)
        Write-Audit 'PERMISOS: solicitud de reinicio elevado aceptada por Windows.'
        $form.Close()
        return $true
    } catch {
        # Al pulsar No en UAC, el usuario sigue con un inventario parcial, sin fallar.
        Write-Audit ('PERMISOS: reinicio elevado no autorizado o no disponible. ' + $_.Exception.Message)
        if ($script:StatusLabel) {
            $script:StatusLabel.Text = 'Sin permisos elevados: análisis limitado. Pulsa Solicitar permisos cuando quieras.'
        }
        return $false
    }
}

function Resolve-OutputDirectory {
    $candidates = @((Join-Path $PSScriptRoot 'Reportes'), (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WinCarePortable\Reportes'))
    foreach ($candidate in $candidates) {
        try {
            if (-not (Test-Path -LiteralPath $candidate)) { New-Item -ItemType Directory -Path $candidate -Force | Out-Null }
            $probe = Join-Path $candidate ('.escritura-' + [guid]::NewGuid().ToString('N'))
            [IO.File]::WriteAllText($probe, 'ok')
            Remove-Item -LiteralPath $probe -Force
            return $candidate
        } catch { }
    }
    throw 'No se pudo encontrar una carpeta donde guardar el inventario.'
}

function Write-Audit([string]$Message) {
    try {
        $root = Resolve-OutputDirectory
        $path = Join-Path $root 'auditoria.txt'
        Add-Content -LiteralPath $path -Encoding UTF8 -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
    } catch { }
}

function New-InventoryTable {
    $table = New-Object System.Data.DataTable
    foreach ($column in @('Tipo','Nombre','Versión','Fabricante','Estado','Riesgo','Acción','Detalle','Clave','DatoExtra','Recomendación')) {
        [void]$table.Columns.Add($column, [string])
    }
    return ,$table
}

function Reset-Inventory {
    foreach ($name in $script:Categories) {
        if ($script:Tables.ContainsKey($name)) { $script:Tables[$name].Clear() }
    }
    $script:Warnings.Clear()
}

function Add-InventoryRecord(
    [string]$Category, [string]$Type, [string]$Name, [string]$Version,
    [string]$Publisher, [string]$State, [string]$Risk, [string]$Action,
    [string]$Detail, [string]$Key, [string]$Extra = ''
) {
    $values = [object[]]@($Type,$Name,$Version,$Publisher,$State,$Risk,$Action,$Detail,$Key,$Extra,'Sin clasificar')
    [void]$script:Tables[$Category].Rows.Add($values)
}

function Get-AppxDisposition($App) {
    $name = [string]$App.Name
    $protected = ($name -match $script:CoreAppPattern)
    if ($App.PSObject.Properties.Match('NonRemovable').Count -and $App.NonRemovable) { $protected = $true }
    if ($App.PSObject.Properties.Match('IsFramework').Count -and $App.IsFramework) { $protected = $true }
    if ($App.PSObject.Properties.Match('IsResourcePackage').Count -and $App.IsResourcePackage) { $protected = $true }
    if ($protected) { return @('Protegido', 'Bloqueada', 'Componente protegido o dependencia de Windows. No se permite eliminar.') }
    if ($script:OptionalApps.ContainsKey($name)) {
        $entry = $script:OptionalApps[$name]
        return @([string]$entry[0], 'Appx', [string]$entry[1])
    }
    return @('Revisar', 'Windows', 'Aplicación no incluida en la lista segura: desinstalar manualmente desde Configuración si corresponde.')
}

function Read-AppxInventory {
    $packages = @(Get-AppxPackage -ErrorAction Stop | Sort-Object Name)
    foreach ($pkg in $packages) {
        $info = Get-AppxDisposition $pkg
        Add-InventoryRecord 'Apps Store' 'Appx/MSIX' ([string]$pkg.Name) ([string]$pkg.Version) ([string]$pkg.Publisher) 'Instalada (usuario actual)' $info[0] $info[1] $info[2] ([string]$pkg.PackageFullName)
    }
}

function Read-ProvisionedInventory {
    foreach ($pkg in @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Sort-Object DisplayName)) {
        $state = 'Preparada para usuarios nuevos'
        $detail = 'Inventario informativo. No se modifica el aprovisionamiento de Windows.'
        Add-InventoryRecord 'Provisionadas' 'Provisionada' ([string]$pkg.DisplayName) ([string]$pkg.Version) 'No especificado' $state 'Protegido' 'Consulta' $detail ([string]$pkg.PackageName)
    }
}

function Read-ProgramInventory {
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $seen = @{}
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($item in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            try {
                $p = Get-ItemProperty -LiteralPath $item.PSPath -ErrorAction Stop
                $name = [string]$p.DisplayName
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                if ($p.PSObject.Properties.Match('SystemComponent').Count -and [string]$p.SystemComponent -eq '1') { continue }
                $key = [string]$item.PSChildName
                $id = $name + '|' + [string]$p.DisplayVersion + '|' + [string]$p.Publisher
                if ($seen.ContainsKey($id)) { continue }
                $seen[$id] = $true
                $publisher = [string]$p.Publisher
                $msi = [string]$p.WindowsInstaller -eq '1' -and $key -match '^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$'
                $essential = ($name -match $script:CoreProgramPattern) -or ($publisher -match '(?i)^(Microsoft Corporation|Microsoft|Intel Corporation|NVIDIA Corporation|Advanced Micro Devices|Realtek)\s*$')
                $risk = 'Revisar'
                $action = 'Windows'
                $detail = 'Usa la opción Desinstalar de Windows. No se ejecutan comandos de desinstalación desconocidos.'
                if ($essential) {
                    $risk = 'Protegido'
                    $action = 'Windows'
                    $detail = 'Posible dependencia, controlador o software esencial. La herramienta no permite su eliminación automática.'
                } elseif ($msi) {
                    $risk = 'Medio'
                    $action = 'MSI'
                    $detail = 'MSI identificado. Puede borrar configuraciones y afectar programas que dependan de él.'
                }
                Add-InventoryRecord 'Programas' 'Win32' $name ([string]$p.DisplayVersion) $publisher 'Registrado' $risk $action $detail $key ([string]$item.PSPath)
            } catch {
                # Un elemento de registro ilegible no debe detener el inventario.
            }
        }
    }
}

function Read-FeatureInventory {
    foreach ($feature in @(Get-WindowsOptionalFeature -Online -ErrorAction Stop | Sort-Object FeatureName)) {
        Add-InventoryRecord 'Características' 'Característica Windows' ([string]$feature.FeatureName) '' 'Microsoft' ([string]$feature.State) 'Protegido' 'Consulta' 'Solo lectura: desactivar componentes Windows puede romper funciones del sistema.' ([string]$feature.FeatureName)
    }
}

function Read-CapabilityInventory {
    foreach ($cap in @(Get-WindowsCapability -Online -ErrorAction Stop | Sort-Object Name)) {
        Add-InventoryRecord 'Capacidades' 'Capability/FOD' ([string]$cap.Name) '' 'Microsoft' ([string]$cap.State) 'Protegido' 'Consulta' 'Solo lectura: capacidades de Windows y paquetes de idioma pueden ser dependencias.' ([string]$cap.Name)
    }
}

function Read-ServiceInventory {
    foreach ($svc in @(Get-CimInstance Win32_Service -ErrorAction Stop | Sort-Object DisplayName)) {
        Add-InventoryRecord 'Servicios' 'Servicio' ([string]$svc.DisplayName) '' ([string]$svc.Name) ([string]$svc.State + ' / ' + [string]$svc.StartMode) 'Protegido' 'Consulta' 'Solo lectura: nunca se detienen, modifican o eliminan servicios desde esta herramienta.' ([string]$svc.Name)
    }
}

function Read-DriverInventory {
    foreach ($drv in @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop | Sort-Object DeviceName)) {
        $display = [string]$drv.DeviceName
        if ([string]::IsNullOrWhiteSpace($display)) { continue }
        Add-InventoryRecord 'Controladores' 'Controlador PnP' $display ([string]$drv.DriverVersion) ([string]$drv.Manufacturer) ([string]$drv.InfName) 'Protegido' 'Consulta' 'Solo lectura: quitar un controlador puede dejar dispositivos sin funcionar.' ([string]$drv.DeviceID)
    }
}

function Read-WinCareRules {
    try {
        $script:PolicyRules=@(Get-WCPolicyRules)
        $script:PolicyLoadOK=$true
    } catch {
        $script:PolicyRules=@()
        $script:PolicyLoadOK=$false
        [void]$script:Warnings.Add('Archivo de reglas no legible: '+$_.Exception.Message+'. Para proteger el equipo se bloquearon las desinstalaciones.')
        Write-Audit ('REGLAS: error de lectura; operaciones bloqueadas: '+$_.Exception.Message)
    }
}
function Apply-WinCareRules {
    foreach($category in @('Apps Store','Programas')) {
        $type=if($category -eq 'Apps Store'){'Appx'}else{'Win32'}
        foreach($row in $script:Tables[$category].Rows) {
            $name=[string]$row['Nombre']; $publisher=[string]$row['Fabricante']
            $protected=[string]$row['Riesgo'] -eq 'Protegido'
            if(-not $script:PolicyLoadOK){
                $row['Recomendación']='Error de configuración'
                $row['Riesgo']='Protegido';$row['Acción']='Bloqueada'
                $row['Detalle']='Corrige el archivo Configuracion\recomendaciones.json antes de realizar cambios.'
                continue
            }
            if($protected) {
                $row['Recomendación']='Conservar · Sistema'
                continue
            }
            $rule=Get-WCPolicyMatch -Rules $script:PolicyRules -Type $type -Name $name -Publisher $publisher
            if($rule){
                if($rule.Recomendacion -eq 'Conservar'){
                    $row['Recomendación']='Conservar · Técnico'
                    $row['Riesgo']='Protegido';$row['Acción']='Bloqueada'
                    $row['Detalle']='Marcada para conservar. Motivo: '+[string]$rule.Motivo
                } else {
                    $row['Recomendación']='Opcional · Técnico'
                    $row['Detalle']=([string]$row['Detalle']+' | Nota: '+[string]$rule.Motivo)
                }
            }elseif($type -eq 'Appx' -and $script:OptionalApps.ContainsKey($name)){
                $row['Recomendación']='Opcional · WinCare'
            }
        }
    }
}
function Open-WinCareRecommendations {
    $path=Join-Path $PSScriptRoot 'AppRecommendations.ps1'
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){
        [void][Windows.Forms.MessageBox]::Show('Falta AppRecommendations.ps1. Descarga todos los archivos del repositorio.','Módulo no encontrado','OK','Warning')
        return
    }
    $type='Appx';$name='';$publisher=''
    if($script:TabControl -and $script:TabControl.SelectedTab){
        $category=[string]$script:TabControl.SelectedTab.Text
        if($category -in @('Apps Store','Programas')){
            $type=if($category -eq 'Programas'){'Win32'}else{'Appx'}
            $grid=$script:Grids[$category]
            if($grid.SelectedRows.Count -eq 1 -and -not $grid.SelectedRows[0].IsNewRow){
                $name=[string]$grid.SelectedRows[0].Cells['Nombre'].Value
                if($type -eq 'Win32'){$publisher=[string]$grid.SelectedRows[0].Cells['Fabricante'].Value}
            }
        }
    }
    try {
        & $path -Owner $form -SuggestedType $type -SuggestedName $name -SuggestedPublisher $publisher
        Refresh-Inventory
    } catch {
        Write-Audit ('EDITOR RECOMENDACIONES: '+$_.Exception.Message)
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'No se pudo abrir el catálogo','OK','Error')
    }
}

function Update-Detail {
    # Evita eventos de seleccion prematuros durante el montaje de la interfaz.
    if ($null -eq $script:DetailLabel -or $null -eq $script:RemoveButton -or $null -eq $script:TabControl) { return }
    $script:DetailLabel.Text = 'Selecciona un elemento para ver sus consecuencias y el método disponible.'
    $script:RemoveButton.Enabled = $false
    if (-not $script:TabControl.SelectedTab) { return }
    $selectedCategory = [string]$script:TabControl.SelectedTab.Text
    if (-not (Test-Administrator) -and $selectedCategory -in @('Provisionadas','Características','Capacidades')) {
        $script:DetailLabel.Text = 'Esta categoría requiere elevación. Pulsa Solicitar permisos y autoriza UAC para verla. El análisis limitado no provoca cambios.'
        return
    }
    $grid = $script:Grids[$script:TabControl.SelectedTab.Text]
    if (-not $grid -or $grid.SelectedRows.Count -eq 0) { return }
    $row = $grid.SelectedRows[0]
    if ($row.IsNewRow) { return }
    $name = [string]$row.Cells['Nombre'].Value
    $risk = [string]$row.Cells['Riesgo'].Value
    $action = [string]$row.Cells['Acción'].Value
    $detail = [string]$row.Cells['Detalle'].Value
    $recommendation = [string]$row.Cells['Recomendación'].Value
    $script:DetailLabel.Text = ('{0} | Riesgo: {1} | Método: {2} | Guía: {3}' + [Environment]::NewLine + '{4}') -f $name, $risk, $action, $recommendation, $detail
    $script:RemoveButton.Enabled = $script:ChangeCheck.Checked -and $script:PolicyLoadOK -and ($action -in @('Appx','MSI'))
}

function Update-Search {
    if (-not $script:TabControl.SelectedTab) { return }
    $view = $script:Tables[$script:TabControl.SelectedTab.Text].DefaultView
    $search = [string]$script:SearchBox.Text
    $search = $search.Replace("'", "''").Replace('[','[[]').Replace(']','[]]').Replace('%','[%]').Replace('*','[*]')
    if ($search.Length -eq 0) { $view.RowFilter = ''; return }
    try {
        $view.RowFilter = "[Nombre] LIKE '%$search%' OR [Fabricante] LIKE '%$search%' OR [Riesgo] LIKE '%$search%' OR [Recomendación] LIKE '%$search%'"
    } catch { $view.RowFilter = '' }
}

function Refresh-Inventory {
    $script:ScanButton.Enabled = $false
    $script:StatusLabel.Text = 'Analizando Windows... Algunas categorías requieren permisos de administrador.'
    [System.Windows.Forms.Application]::DoEvents()
    Reset-Inventory
    Read-WinCareRules
    $tasks = @(
        @('Apps Store', { Read-AppxInventory }),
        @('Provisionadas', { Read-ProvisionedInventory }),
        @('Programas', { Read-ProgramInventory }),
        @('Características', { Read-FeatureInventory }),
        @('Capacidades', { Read-CapabilityInventory }),
        @('Servicios', { Read-ServiceInventory }),
        @('Controladores', { Read-DriverInventory })
    )
    $hasAdminRights = Test-Administrator
    $requiresAdmin = @('Provisionadas','Características','Capacidades')
    foreach ($task in $tasks) {
        if (-not $hasAdminRights -and [string]$task[0] -in $requiresAdmin) {
            # No lanzar cmdlets DISM que necesariamente darían ERROR_ELEVATION_REQUIRED.
            # Las pestañas quedan vacías, no con mensajes alarmantes de error.
            continue
        }
        $script:StatusLabel.Text = 'Analizando: ' + [string]$task[0] + ' ...'
        [System.Windows.Forms.Application]::DoEvents()
        try { & $task[1] }
        catch { [void]$script:Warnings.Add(([string]$task[0] + ': ' + $_.Exception.Message)) }
    }
    Apply-WinCareRules
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $script:SubtitleLabel.Text = ('{0} | Compilación {1} | Usuario {2} | Administración: {3}' -f $os.Caption,$os.BuildNumber,$env:USERNAME,(Test-Administrator))
    } catch { }
    $total = 0
    foreach ($t in $script:Tables.Values) { $total += $t.Rows.Count }
    $script:StatusLabel.Text = ('{0} elementos detectados. Advertencias: {1}. Modo de cambios: {2}.' -f $total,$script:Warnings.Count,$script:ChangeCheck.Checked)
    if (-not $hasAdminRights) {
        $script:StatusLabel.Text += ' Inventario limitado: para completar 3 categorías, pulsa Solicitar permisos.'
    }
    $script:ScanButton.Enabled = $true
    Update-Search
    Update-Detail
    Write-Audit ('ESCANEO: {0} elementos; {1} advertencias' -f $total,$script:Warnings.Count)
    if ($script:Warnings.Count -gt 0) {
        [void][System.Windows.Forms.MessageBox]::Show(($script:Warnings -join [Environment]::NewLine), 'Inventario parcial', 'OK', 'Warning')
    }
}

function Export-Inventory {
    try {
        $base = Resolve-OutputDirectory
        $folder = Join-Path $base (Get-Date -Format 'yyyyMMdd-HHmmss')
        [void](New-Item -ItemType Directory -Path $folder -Force)
        foreach ($name in $script:Categories) {
            $records = foreach ($r in $script:Tables[$name].Rows) {
                [pscustomobject]@{
                    Tipo = [string]$r['Tipo']; Nombre = [string]$r['Nombre']; Version = [string]$r['Versión']
                    Fabricante = [string]$r['Fabricante']; Estado = [string]$r['Estado']
                    Riesgo = [string]$r['Riesgo']; Recomendacion = [string]$r['Recomendación']; Accion = [string]$r['Acción']; Detalle = [string]$r['Detalle']
                }
            }
            if ($null -ne $records -and @($records).Count -gt 0) {
                $filename = switch ($name) {
                    'Apps Store' { 'apps-store.csv' }
                    'Provisionadas' { 'apps-provisionadas.csv' }
                    'Programas' { 'programas.csv' }
                    'Características' { 'caracteristicas.csv' }
                    'Capacidades' { 'capacidades.csv' }
                    'Servicios' { 'servicios.csv' }
                    'Controladores' { 'controladores.csv' }
                }
                $records | Export-Csv -LiteralPath (Join-Path $folder $filename) -NoTypeInformation -Encoding UTF8
            }
        }
        ('WinCare Portable v1.5 | Diseñado por DevPoderSEO' + [Environment]::NewLine + $script:SubtitleLabel.Text + [Environment]::NewLine + 'Advertencias:' + [Environment]::NewLine + ($script:Warnings -join [Environment]::NewLine)) | Set-Content -LiteralPath (Join-Path $folder 'resumen.txt') -Encoding UTF8
        Write-Audit ('EXPORTACION: ' + $folder)
        [void][System.Windows.Forms.MessageBox]::Show(('Inventario exportado en:' + [Environment]::NewLine + $folder),'Exportación completada','OK','Information')
        Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $folder + '"')
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Error de exportación','OK','Error')
    }
}

function Open-WindowsUninstall {
    try { Start-Process 'ms-settings:appsfeatures' }
    catch { Start-Process 'appwiz.cpl' }
}

function Uninstall-Selected {
    if (-not $script:ChangeCheck.Checked) { return }
    $tab = $script:TabControl.SelectedTab
    if (-not $tab) { return }
    $grid = $script:Grids[$tab.Text]
    if ($grid.SelectedRows.Count -ne 1) {
        [void][System.Windows.Forms.MessageBox]::Show('Selecciona solo una aplicación o programa por operación.','Selección','OK','Information')
        return
    }
    $row = $grid.SelectedRows[0]
    $name = [string]$row.Cells['Nombre'].Value
    $action = [string]$row.Cells['Acción'].Value
    $risk = [string]$row.Cells['Riesgo'].Value
    $detail = [string]$row.Cells['Detalle'].Value
    $key = [string]$row.Cells['Clave'].Value
    $extra = [string]$row.Cells['DatoExtra'].Value
    if ($action -notin @('Appx','MSI') -or $risk -eq 'Protegido') { return }
    # Revalidar configuración antes de cada desinstalación; un fallo cancela.
    try {
        $type=if($tab.Text -eq 'Apps Store'){'Appx'}elseif($tab.Text -eq 'Programas'){'Win32'}else{'Otro'}
        if($type -eq 'Otro'){throw 'Categoría no permitida.'}
        $rule=Get-WCPolicyMatch -Rules @(Get-WCPolicyRules) -Type $type -Name $name -Publisher ([string]$row.Cells['Fabricante'].Value)
        if($rule -and $rule.Recomendacion -eq 'Conservar'){
            [void][Windows.Forms.MessageBox]::Show(('Este programa está marcado como Conservar: '+$name+'. Modifica la regla en Recomendaciones si corresponde.'),'Protegido por el técnico','OK','Warning')
            return
        }
    }catch{
        [void][Windows.Forms.MessageBox]::Show(('No fue posible verificar las reglas: '+$_.Exception.Message+'. Desinstalación cancelada.'),'Protección de programas','OK','Warning')
        return
    }

    $message = "¿Confirmas la desinstalación?`r`n`r`nPrograma: $name`r`nRiesgo: $risk`r`nConsecuencia: $detail`r`n`r`nADVERTENCIA: podrías perder configuraciones, archivos propios de la aplicación o funciones dependientes. Esta herramienta NO garantiza reversión. Haz una copia de seguridad antes de continuar.`r`n`r`n¿Continuar?"
    $answer = [System.Windows.Forms.MessageBox]::Show($message,'Confirmar eliminación: posible pérdida de funciones','YesNo','Warning','Button2')
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $script:RemoveButton.Enabled = $false
    $script:StatusLabel.Text = 'Desinstalando: ' + $name
    [System.Windows.Forms.Application]::DoEvents()
    try {
        if ($action -eq 'Appx') {
            $pkg = @(Get-AppxPackage -ErrorAction Stop | Where-Object { $_.PackageFullName -eq $key })
            if ($pkg.Count -ne 1) { throw 'El paquete ya no existe o no puede identificarse sin ambigüedad.' }
            $disposition = Get-AppxDisposition $pkg[0]
            if ($disposition[1] -ne 'Appx' -or $pkg[0].Name -ne $name) { throw 'El paquete no está autorizado para desinstalación.' }
            Remove-AppxPackage -Package $pkg[0].PackageFullName -ErrorAction Stop
            Write-Audit ('APPX QUITADA (usuario actual): ' + $name + ' / ' + $key)
            [void][System.Windows.Forms.MessageBox]::Show('Aplicación eliminada del usuario actual. No se modificó el aprovisionamiento para otros usuarios.','Operación completada','OK','Information')
        } else {
            # MSI: únicamente código GUID, validado de nuevo contra el registro.
            if ($key -notmatch '^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$') { throw 'Identificador MSI no válido.' }
            if (-not (Test-Path -LiteralPath $extra)) { throw 'El registro del desinstalador ya no existe.' }
            $reg = Get-ItemProperty -LiteralPath $extra -ErrorAction Stop
            if ([string]$reg.WindowsInstaller -ne '1' -or [string]$reg.DisplayName -ne $name) { throw 'La identidad del programa cambió: operación cancelada.' }
            if ($name -match $script:CoreProgramPattern -or ([string]$reg.Publisher) -match '(?i)^(Microsoft Corporation|Microsoft|Intel Corporation|NVIDIA Corporation|Advanced Micro Devices|Realtek)\s*$') {
                throw 'Programa protegido; utiliza el asistente de Windows si sabes exactamente qué estás quitando.'
            }
            $msi = Join-Path $env:WINDIR 'System32\msiexec.exe'
            Write-Audit ('MSI SOLICITADO: ' + $name + ' / ' + $key)
            $result = Start-Process -FilePath $msi -ArgumentList @('/x',$key) -PassThru -Wait -ErrorAction Stop
            Write-Audit ('MSI FINALIZADO: ' + $name + ' / Código=' + $result.ExitCode)
            if ($result.ExitCode -eq 3010) {
                [void][System.Windows.Forms.MessageBox]::Show('El desinstalador solicita reiniciar Windows. Guarda tu trabajo antes.','Reinicio requerido','OK','Information')
            } elseif ($result.ExitCode -eq 1602) {
                [void][System.Windows.Forms.MessageBox]::Show('Desinstalación cancelada por el usuario.','Cancelada','OK','Information')
            } elseif ($result.ExitCode -ne 0) {
                throw ('El instalador devolvió el código ' + $result.ExitCode + '. Consulta el historial para diagnosticarlo.')
            } else {
                [void][System.Windows.Forms.MessageBox]::Show('El desinstalador terminó. Se actualizará el inventario.','Finalizado','OK','Information')
            }
        }
        Refresh-Inventory
    } catch {
        Write-Audit ('ERROR DESINSTALACION: ' + $name + ' / ' + $_.Exception.Message)
        [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'No se pudo desinstalar','OK','Error')
    } finally {
        $script:StatusLabel.Text = 'Listo. Revisa el historial y vuelve a escanear para confirmar.'
        Update-Detail
    }
}

function Request-RestorePoint {
    if (-not (Test-Administrator)) {
        [void][System.Windows.Forms.MessageBox]::Show('Se necesita autorización de Windows para crear un punto de restauración. WinCare se reiniciará con privilegios si aceptas el aviso UAC. Después, pulsa nuevamente Punto restauración.','Permiso necesario','OK','Information')
        [void](Request-AdministratorAccess)
        return
    }
    $response = [System.Windows.Forms.MessageBox]::Show('Se intentará crear un punto de restauración. Windows debe tener Protección del sistema habilitada y normalmente limita la frecuencia a uno por día. No sustituye una copia de seguridad.','Crear punto de restauración','YesNo','Question','Button2')
    if ($response -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    try {
        $script:StatusLabel.Text = 'Solicitando punto de restauración a Windows...'
        [System.Windows.Forms.Application]::DoEvents()
        Checkpoint-Computer -Description ('WinCare Portable ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')) -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Audit 'PUNTO DE RESTAURACION: solicitado sin errores'
        [void][System.Windows.Forms.MessageBox]::Show('Windows confirmó la creación del punto de restauración.','Correcto','OK','Information')
    } catch {
        Write-Audit ('ERROR RESTAURACION: ' + $_.Exception.Message)
        [void][System.Windows.Forms.MessageBox]::Show(('No se pudo crear el punto de restauración: ' + $_.Exception.Message + [Environment]::NewLine + 'Comprueba la Protección del sistema.'),'No disponible','OK','Warning')
    } finally { $script:StatusLabel.Text = 'Listo.' }
}

# ---- Interfaz portátil WinForms ----
$form = New-Object System.Windows.Forms.Form
$form.Text = 'WinCare Portable | Diagnóstico, limpieza y seguridad de red | DevPoderSEO'
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.Size = New-Object System.Drawing.Size(1340, 885)
$form.MinimumSize = New-Object System.Drawing.Size(1185, 790)
$form.BackColor = $script:Palette.Bg
$form.ForeColor = $script:Palette.Text
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$header = New-Object System.Windows.Forms.Label
$header.Location = New-Object System.Drawing.Point(20, 15)
$header.Size = New-Object System.Drawing.Size(800, 32)
$header.Text = 'WinCare Portable  |  Centro técnico'
$header.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 19, [System.Drawing.FontStyle]::Bold)
$header.ForeColor = $script:Palette.Text
$form.Controls.Add($header)

$brandLabel = New-Object System.Windows.Forms.Label
$brandLabel.Text = 'Diseñado por DevPoderSEO'
$brandLabel.Location = New-Object System.Drawing.Point(982, 19)
$brandLabel.Size = New-Object System.Drawing.Size(285, 27)
$brandLabel.Anchor = 'Top,Right'
$brandLabel.TextAlign = 'MiddleRight'
$brandLabel.ForeColor = $script:Palette.Accent
$form.Controls.Add($brandLabel)

$script:SubtitleLabel = New-Object System.Windows.Forms.Label
$script:SubtitleLabel.Location = New-Object System.Drawing.Point(22, 55)
$script:SubtitleLabel.Size = New-Object System.Drawing.Size(1190, 25)
$script:SubtitleLabel.Text = 'Inventario, protección de aplicaciones y mantenimiento. Los módulos empiezan en modo solo lectura.'
$script:SubtitleLabel.ForeColor = $script:Palette.Muted
$script:SubtitleLabel.Anchor = 'Top,Left,Right'
$form.Controls.Add($script:SubtitleLabel)

$script:SearchBox = New-Object System.Windows.Forms.TextBox
$script:SearchBox.Location = New-Object System.Drawing.Point(20, 104)
$script:SearchBox.Size = New-Object System.Drawing.Size(350, 30)
$script:SearchBox.BackColor = $script:Palette.Panel
$script:SearchBox.ForeColor = $script:Palette.Text
$script:SearchBox.BorderStyle = 'FixedSingle'
$form.Controls.Add($script:SearchBox)
$script:SearchBox.Add_TextChanged({ Update-Search })

$script:ScanButton = New-Object System.Windows.Forms.Button
$script:ScanButton.Text = 'Analizar PC'
$script:ScanButton.Location = New-Object System.Drawing.Point(384, 102)
$script:ScanButton.Size = New-Object System.Drawing.Size(146, 33)
$script:ScanButton.BackColor = $script:Palette.Accent
$script:ScanButton.ForeColor = [System.Drawing.Color]::White
$script:ScanButton.FlatStyle = 'Flat'
$form.Controls.Add($script:ScanButton)
$script:ScanButton.Add_Click({ Refresh-Inventory })

$script:AdminButton = New-Object System.Windows.Forms.Button
$script:AdminButton.Text = 'Solicitar permisos'
$script:AdminButton.Location = New-Object System.Drawing.Point(1122, 102)
$script:AdminButton.Size = New-Object System.Drawing.Size(175, 33)
$script:AdminButton.FlatStyle = 'Flat'
$script:AdminButton.BackColor = [System.Drawing.Color]::FromArgb(87, 105, 130)
$script:AdminButton.ForeColor = [System.Drawing.Color]::White
$script:AdminButton.Enabled = -not (Test-Administrator)
if (-not $script:AdminButton.Enabled) {
    $script:AdminButton.Text = 'Admin activo'
    $script:AdminButton.BackColor = [System.Drawing.Color]::FromArgb(45, 109, 82)
}
$form.Controls.Add($script:AdminButton)
$script:AdminButton.Add_Click({
    [void](Request-AdministratorAccess)
})

$networkBtn = New-Object System.Windows.Forms.Button
$networkBtn.Text = 'Seguridad de red e IP'
$networkBtn.Location = New-Object System.Drawing.Point(968, 96)
$networkBtn.Size = New-Object System.Drawing.Size(220, 31)
$networkBtn.BackColor = $script:Palette.Accent
$networkBtn.ForeColor = [System.Drawing.Color]::White
$networkBtn.FlatStyle = 'Flat'
$form.Controls.Add($networkBtn)
$networkBtn.Add_Click({
    $module = Join-Path $PSScriptRoot 'NetworkAudit.ps1'
    if (-not (Test-Path -LiteralPath $module -PathType Leaf)) {
        [void][System.Windows.Forms.MessageBox]::Show('Falta NetworkAudit.ps1. Descarga todos los archivos del repositorio juntos.','Módulo no encontrado','OK','Warning')
        return
    }
    try { & $module -Owner $form }
    catch {
        Write-Audit ('ERROR RED: ' + $_.Exception.Message)
        [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'No se pudo abrir seguridad de red','OK','Error')
    }
})

$script:ChangeCheck = New-Object System.Windows.Forms.CheckBox
$script:ChangeCheck.Text = 'Habilitar desinstalación (precaución)'
$script:ChangeCheck.Location = New-Object System.Drawing.Point(552, 102)
$script:ChangeCheck.Size = New-Object System.Drawing.Size(350, 33)
$script:ChangeCheck.ForeColor = [System.Drawing.Color]::FromArgb(255, 207, 105)
$script:ChangeCheck.Checked = $false
$form.Controls.Add($script:ChangeCheck)
$script:ChangeCheck.Add_CheckedChanged({ Update-Detail })

$script:TabControl = New-Object System.Windows.Forms.TabControl
$script:TabControl.Location = New-Object System.Drawing.Point(20, 234)
$script:TabControl.Size = New-Object System.Drawing.Size(1260, 458)
$script:TabControl.Anchor = 'Top,Bottom,Left,Right'
$script:TabControl.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.Controls.Add($script:TabControl)

foreach ($name in $script:Categories) {
    $script:Tables[$name] = New-InventoryTable
    $page = New-Object System.Windows.Forms.TabPage
    $page.Text = $name
    $page.BackColor = $script:Palette.Panel
    $page.ForeColor = $script:Palette.Text
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = 'Fill'
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.SelectionMode = 'FullRowSelect'
    $grid.MultiSelect = $false
    $grid.AutoGenerateColumns = $false
    $grid.AutoSizeColumnsMode = 'Fill'
    $grid.RowHeadersVisible = $false
    $grid.BackgroundColor = $script:Palette.Panel
    $grid.GridColor = $script:Palette.Border
    $grid.BorderStyle = 'None'
    $grid.EnableHeadersVisualStyles = $false
    $grid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(39, 53, 72)
    $grid.ColumnHeadersDefaultCellStyle.ForeColor = $script:Palette.Text
    $grid.DefaultCellStyle.BackColor = $script:Palette.Panel
    $grid.DefaultCellStyle.ForeColor = $script:Palette.Text
    $grid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(39, 104, 169)
    $grid.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
    $grid.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(33, 45, 61)
    # Definir columnas antes de asignar DataSource: WinForms puede postergar la autogeneración
    # hasta que el control tenga un BindingContext. Nunca asumir Columns[$name] existente.
    $weights = @{ 'Nombre'=238; 'Tipo'=80; 'Versión'=94; 'Fabricante'=150; 'Estado'=110; 'Riesgo'=89; 'Acción'=78; 'Recomendación'=170 }
    foreach ($dataColumn in $script:Tables[$name].Columns) {
        $columnName = [string]$dataColumn.ColumnName
        $column = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $column.Name = $columnName
        $column.DataPropertyName = $columnName
        $column.HeaderText = $columnName
        if ($columnName -in @('Detalle','Clave','DatoExtra')) {
            $column.Visible = $false
        } elseif ($weights.ContainsKey($columnName)) {
            $column.FillWeight = [single]$weights[$columnName]
        }
        [void]$grid.Columns.Add($column)
    }
    $grid.DataSource = $script:Tables[$name].DefaultView
    $grid.Add_SelectionChanged({ Update-Detail })
    $page.Controls.Add($grid)
    $script:Grids[$name] = $grid
    [void]$script:TabControl.TabPages.Add($page)
}
$script:TabControl.Add_SelectedIndexChanged({ Update-Search; Update-Detail })

$script:DetailLabel = New-Object System.Windows.Forms.Label
$script:DetailLabel.Location = New-Object System.Drawing.Point(23, 694)
$script:DetailLabel.Size = New-Object System.Drawing.Size(1260, 52)
$script:DetailLabel.Anchor = 'Bottom,Left,Right'
$script:DetailLabel.ForeColor = $script:Palette.Muted
$script:DetailLabel.Text = 'Selecciona un elemento para ver su riesgo y consecuencias.'
$form.Controls.Add($script:DetailLabel)

$script:RemoveButton = New-Object System.Windows.Forms.Button
$script:RemoveButton.Text = 'Desinstalar seleccionado'
$script:RemoveButton.Location = New-Object System.Drawing.Point(20, 673)
$script:RemoveButton.Size = New-Object System.Drawing.Size(180, 33)
$script:RemoveButton.Anchor = 'Bottom,Left'
$script:RemoveButton.BackColor = [System.Drawing.Color]::FromArgb(160, 67, 63)
$script:RemoveButton.ForeColor = [System.Drawing.Color]::White
$script:RemoveButton.FlatStyle = 'Flat'
$script:RemoveButton.Enabled = $false
$form.Controls.Add($script:RemoveButton)
$script:RemoveButton.Add_Click({ Uninstall-Selected })

$windowsBtn = New-Object System.Windows.Forms.Button
$windowsBtn.Text = 'Desinstalar desde Windows'
$windowsBtn.Location = New-Object System.Drawing.Point(208, 673)
$windowsBtn.Size = New-Object System.Drawing.Size(174, 33)
$windowsBtn.Anchor = 'Bottom,Left'
$form.Controls.Add($windowsBtn)
$windowsBtn.Add_Click({ Open-WindowsUninstall })

$restoreBtn = New-Object System.Windows.Forms.Button
$restoreBtn.Text = 'Punto restauración'
$restoreBtn.Location = New-Object System.Drawing.Point(390, 673)
$restoreBtn.Size = New-Object System.Drawing.Size(142, 33)
$restoreBtn.Anchor = 'Bottom,Left'
$form.Controls.Add($restoreBtn)
$restoreBtn.Add_Click({ Request-RestorePoint })

$exportBtn = New-Object System.Windows.Forms.Button
$exportBtn.Text = 'Exportar inventario'
$exportBtn.Location = New-Object System.Drawing.Point(540, 673)
$exportBtn.Size = New-Object System.Drawing.Size(150, 33)
$exportBtn.Anchor = 'Bottom,Left'
$form.Controls.Add($exportBtn)
$exportBtn.Add_Click({ Export-Inventory })

$folderBtn = New-Object System.Windows.Forms.Button
$folderBtn.Text = 'Ver reportes'
$folderBtn.Location = New-Object System.Drawing.Point(698, 673)
$folderBtn.Size = New-Object System.Drawing.Size(118, 33)
$folderBtn.Anchor = 'Bottom,Left'
$form.Controls.Add($folderBtn)
$folderBtn.Add_Click({
    try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + (Resolve-OutputDirectory) + '"') }
    catch { [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Error','OK','Error') }
})

$helpBtn = New-Object System.Windows.Forms.Button
$helpBtn.Text = 'Ayuda y seguridad'
$helpBtn.Location = New-Object System.Drawing.Point(823, 673)
$helpBtn.Size = New-Object System.Drawing.Size(132, 33)
$helpBtn.Anchor = 'Bottom,Left'
$form.Controls.Add($helpBtn)
$helpBtn.Add_Click({
    $message = @'
WinCare Portable v1.5 - Diseñado por DevPoderSEO

- Escanea el Windows en ejecución, NO imágenes ISO ni discos sin arrancar.
- Solo permite quitar Appx expresamente aprobadas y MSI verificados.
- No desinstala servicios, controladores, características ni capacidades Windows.
- Los programas no compatibles se gestionan desde Configuración de Windows.
- Riesgo bajo NO significa riesgo cero: podrías perder datos de una aplicación.
- Un punto de restauración no reemplaza una copia de seguridad de tus archivos.
- No elimina aplicaciones de otros usuarios ni aprovisionadas para cuentas nuevas.
- Si se ha usado Ejecutar como otro usuario, Appx se detecta para ese usuario.
- El inventario puede ser parcial sin permisos elevados y no detecta todos los programas portátiles.
- Centro de mantenimiento: antivirus, Windows Update, inicio, almacenamiento, firewall e integridad.
- Limpieza por categoría: temporales de usuario, Windows, volcados, informes de fallos y miniaturas.
- La limpieza requiere selección, autorización y confirmación. No borra carpetas ni archivos del usuario.
- No se eliminan Prefetch, Descargas, perfiles de navegador ni cachés críticas.
- Papelera opcional: doble confirmación, sin restauración garantizada.
- Accesos técnicos: Liberador de espacio, Servicios, Tareas programadas, Visor de eventos, msconfig y Monitor de recursos.
- Hardware y salud consulta CPU, RAM, placa madre, BIOS, discos, GPU, red, batería y dispositivos.
- Incluye msinfo32, dxdiag, Monitor de recursos y otras herramientas de Windows.
- Salud de disco/SMART y eventos son orientativos; no reemplazan diagnóstico del fabricante.
- Seguridad de red e IP consulta conexiones TCP/UDP, procesos, dispositivos en caché ARP/ND y firewall.
- Una conexión o IP desconocida NO confirma intrusión. Contrasta con router, antivirus y registros.
- No se bloquean conexiones, no se matan procesos ni se realiza escaneo masivo de equipos.
- El ping manual y la IP pública externa requieren consentimiento.
- Para consultar categorías restringidas, pulsa Solicitar permisos y autoriza el aviso UAC de Windows.
- Si rechazas UAC, el inventario continúa limitado y nunca cambia la seguridad de Windows.

Consulta el README incluido para obtener instrucciones.
'@
    [void][System.Windows.Forms.MessageBox]::Show($message,'Ayuda y límites de seguridad','OK','Information')
})

$hardwareBtn = New-Object System.Windows.Forms.Button
$hardwareBtn.Text = 'Hardware y salud'
$hardwareBtn.Location = New-Object System.Drawing.Point(963, 673)
$hardwareBtn.Size = New-Object System.Drawing.Size(148, 33)
$hardwareBtn.Anchor = 'Bottom,Left'
$hardwareBtn.BackColor = $script:Palette.Accent
$hardwareBtn.ForeColor = [System.Drawing.Color]::White
$hardwareBtn.FlatStyle = 'Flat'
$form.Controls.Add($hardwareBtn)
$hardwareBtn.Add_Click({
    $module = Join-Path $PSScriptRoot 'HardwareAudit.ps1'
    if (-not (Test-Path -LiteralPath $module -PathType Leaf)) {
        [void][System.Windows.Forms.MessageBox]::Show('No se encuentra HardwareAudit.ps1. Descarga el proyecto completo desde GitHub.','Módulo de hardware ausente','OK','Warning')
        return
    }
    try { & $module -Owner $form }
    catch {
        Write-Audit ('ERROR HARDWARE: '+$_.Exception.Message)
        [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'No se pudo abrir hardware y salud','OK','Error')
    }
})

$maintenanceBtn = New-Object System.Windows.Forms.Button
$maintenanceBtn.Text = 'Mantenimiento'
$maintenanceBtn.Size = New-Object System.Drawing.Size(148, 33)
$maintenanceBtn.BackColor = $script:Palette.Accent
$maintenanceBtn.ForeColor = [System.Drawing.Color]::White
$maintenanceBtn.FlatStyle = 'Flat'
$form.Controls.Add($maintenanceBtn)
$maintenanceBtn.Add_Click({
    $module = Join-Path $PSScriptRoot 'MaintenanceAudit.ps1'
    if (-not (Test-Path -LiteralPath $module -PathType Leaf)) {
        [void][System.Windows.Forms.MessageBox]::Show('No se encuentra MaintenanceAudit.ps1. Descarga el proyecto completo desde GitHub.','Módulo de mantenimiento ausente','OK','Warning')
        return
    }
    try { & $module -Owner $form }
    catch {
        Write-Audit ('ERROR MANTENIMIENTO: '+$_.Exception.Message)
        [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'No se pudo abrir el centro de mantenimiento','OK','Error')
    }
})

# Navegación principal: cinco módulos organizados por función y no por acciones peligrosas.
$technicianBtn = New-Object System.Windows.Forms.Button
$technicianBtn.Text = '04  Taller técnico'
$technicianBtn.BackColor = $script:Palette.Accent
$technicianBtn.ForeColor = [Drawing.Color]::White
$technicianBtn.FlatStyle = 'Flat'
$form.Controls.Add($technicianBtn)
$technicianBtn.Add_Click({
    $module=Join-Path $PSScriptRoot 'TechToolkit.ps1'
    if(-not (Test-Path -LiteralPath $module -PathType Leaf)){
        [void][Windows.Forms.MessageBox]::Show('Falta TechToolkit.ps1. Descarga el proyecto completo.','Taller técnico','OK','Warning')
        return
    }
    try{ & $module -Owner $form }
    catch{
        Write-Audit ('TALLER: '+$_.Exception.Message)
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'No se pudo abrir Taller técnico','OK','Error')
    }
})
$policyBtn = New-Object System.Windows.Forms.Button
$policyBtn.Text = '05  Recomendaciones'
$policyBtn.BackColor = $script:Palette.Accent
$policyBtn.ForeColor = [Drawing.Color]::White
$policyBtn.FlatStyle = 'Flat'
$form.Controls.Add($policyBtn)
$policyBtn.Add_Click({ Open-WinCareRecommendations })

$navBar=New-Object System.Windows.Forms.TableLayoutPanel
$navBar.Location=New-Object Drawing.Point(20,154)
$navBar.Size=New-Object Drawing.Size(1260,64)
$navBar.Anchor='Top,Left,Right'
$navBar.RowCount=1
$navBar.ColumnCount=5
$navBar.BackColor=$script:Palette.Bg
for($n=0;$n -lt 5;$n++){
    [void]$navBar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,[single]20)))
}
$hardwareBtn.Text='01  Hardware y salud'
$networkBtn.Text='02  Red e IP'
$maintenanceBtn.Text='03  Mantenimiento'
$navButtons=@($hardwareBtn,$networkBtn,$maintenanceBtn,$technicianBtn,$policyBtn)
for($n=0;$n -lt $navButtons.Count;$n++){
    $button=$navButtons[$n]
    $form.Controls.Remove($button)
    $button.Dock='Fill'
    $button.Font=New-Object Drawing.Font('Segoe UI Semibold',10,[Drawing.FontStyle]::Bold)
    $button.Margin=New-Object System.Windows.Forms.Padding(4,6,4,6)
    $button.Cursor=[Windows.Forms.Cursors]::Hand
    $button.FlatStyle='Flat'
    $button.FlatAppearance.BorderSize=0
    $button.BackColor=[Drawing.Color]::FromArgb(34,70,106)
    $button.ForeColor=$script:Palette.Text
    $navBar.Controls.Add($button,$n,0)
}
$form.Controls.Add($navBar)
$quickTips=New-Object System.Windows.Forms.ToolTip
$quickTips.SetToolTip($hardwareBtn,'CPU, RAM, BIOS, discos, dispositivos y salud del equipo.')
$quickTips.SetToolTip($networkBtn,'Conexiones TCP/UDP, procesos, IP y equipos observados.')
$quickTips.SetToolTip($maintenanceBtn,'Limpieza controlada, integridad, inicio y actualizaciones.')
$quickTips.SetToolTip($technicianBtn,'Informe HTML para clientes, respaldo de controladores y reparación guiada.')
$quickTips.SetToolTip($policyBtn,'Clasificar programas como Conservar u Opcional sin desbloquear componentes del sistema.')
$quickTips.SetToolTip($script:SearchBox,'Buscar aplicaciones, fabricantes, riesgos y recomendaciones.')
$quickTips.SetToolTip($script:ChangeCheck,'No habilites desinstalaciones hasta revisar el componente y tener respaldo.')

# Acciones secundarias de inventario en un pie flexible y separado de los módulos.
$actionBar=New-Object System.Windows.Forms.TableLayoutPanel
$actionBar.Location=New-Object Drawing.Point(20,752)
$actionBar.Size=New-Object Drawing.Size(1260,42)
$actionBar.Anchor='Bottom,Left,Right'
$actionBar.RowCount=1
$actionBar.ColumnCount=6
for($n=0;$n -lt 6;$n++){
    [void]$actionBar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,[single](100/6))))
}
$script:RemoveButton.Text='Desinstalar seleccionado'
$windowsBtn.Text='Aplicaciones Windows'
$restoreBtn.Text='Punto restauración'
$exportBtn.Text='Exportar inventario'
$folderBtn.Text='Ver reportes'
$helpBtn.Text='Ayuda y seguridad'
$actionButtons=@($script:RemoveButton,$windowsBtn,$restoreBtn,$exportBtn,$folderBtn,$helpBtn)
for($n=0;$n -lt $actionButtons.Count;$n++){
    $button=$actionButtons[$n]
    $form.Controls.Remove($button)
    $button.Dock='Fill'
    $button.Margin=New-Object Windows.Forms.Padding(4,3,4,3)
    $button.Font=New-Object Drawing.Font('Segoe UI',9,[Drawing.FontStyle]::Regular)
    $button.FlatStyle='Flat'
    $button.FlatAppearance.BorderSize=1
    $button.FlatAppearance.BorderColor=$script:Palette.Border
    $actionBar.Controls.Add($button,$n,0)
}
$form.Controls.Add($actionBar)

# Encabezado tipo tarjeta, sin bordes rígidos ni menús saturados.
$headerBar=New-Object System.Windows.Forms.Panel
$headerBar.Location=New-Object Drawing.Point(0,0)
$headerBar.Size=New-Object Drawing.Size(1320,90)
$headerBar.Anchor='Top,Left,Right'
$headerBar.BackColor=[Drawing.Color]::FromArgb(24,36,52)
foreach($control in @($header,$brandLabel,$script:SubtitleLabel)){
    $form.Controls.Remove($control)
    $headerBar.Controls.Add($control)
}
$headerBar.Controls.SetChildIndex($header,0)
$form.Controls.Add($headerBar)
$form.Controls.SetChildIndex($headerBar,0)

$detailPanel=New-Object System.Windows.Forms.Panel
$detailPanel.Location=New-Object Drawing.Point(20,699)
$detailPanel.Size=New-Object Drawing.Size(1260,44)
$detailPanel.Anchor='Bottom,Left,Right'
$detailPanel.BackColor=$script:Palette.Panel
$form.Controls.Remove($script:DetailLabel)
$script:DetailLabel.Location=New-Object Drawing.Point(11,4)
$script:DetailLabel.Size=New-Object Drawing.Size(1230,39)
$script:DetailLabel.Anchor='Top,Left,Right'
$detailPanel.Controls.Add($script:DetailLabel)
$form.Controls.Add($detailPanel)

$script:StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel.Location = New-Object System.Drawing.Point(22, 815)
$script:StatusLabel.Size = New-Object System.Drawing.Size(1260, 28)
$script:StatusLabel.ForeColor = $script:Palette.Muted
$script:StatusLabel.Anchor = 'Bottom,Left,Right'
$script:StatusLabel.Text = 'Listo. Modo de solo lectura activado.'
$form.Controls.Add($script:StatusLabel)

$form.Add_Shown({
    [System.Windows.Forms.Application]::DoEvents()
    if (-not (Test-Administrator)) {
        $message = 'Para consultar todas las aplicaciones aprovisionadas, características y capacidades de Windows, se necesitan permisos de administrador.' +
            [Environment]::NewLine + [Environment]::NewLine +
            '¿Quieres reiniciar WinCare con permisos? Windows te pedirá autorización (UAC).' +
            [Environment]::NewLine + [Environment]::NewLine +
            'Si eliges No, puedes continuar con el análisis parcial. La desinstalación seguirá desactivada.'
        $choice = [System.Windows.Forms.MessageBox]::Show($message,'WinCare | Permisos para inventario completo','YesNo','Question','Button2')
        if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
            if (Request-AdministratorAccess) { return }
        }
    }
    Refresh-Inventory
})
if ($SmokeTest) {
    # Prueba segura de inicialización: no muestra la ventana ni ejecuta inventario.
    foreach ($category in $script:Categories) {
        $table = $script:Tables[$category]
        $grid = $script:Grids[$category]
        if ($null -eq $grid -or $grid.Columns.Count -ne $table.Columns.Count) {
            throw ("Columnas no inicializadas en " + $category)
        }
        foreach ($dataColumn in $table.Columns) {
            $columnName = [string]$dataColumn.ColumnName
            if ($null -eq $grid.Columns[$columnName]) { throw ("Falta la columna " + $columnName + " en " + $category) }
            if ($columnName -in @('Detalle','Clave','DatoExtra') -and $grid.Columns[$columnName].Visible) {
                throw ("Columna interna visible por error: " + $columnName)
            }
        }
    }
    if (-not $script:AdminButton -or $script:AdminButton.Text -notin @('Admin activo','Solicitar permisos')) {
        throw 'Botón de elevación UAC no inicializado.'
    }
    if ($null -eq $hardwareBtn -or $hardwareBtn.Text -ne 'Hardware y salud') { throw 'Falta Hardware y salud.' }
    if ($null -eq $maintenanceBtn -or $maintenanceBtn.Text -ne 'Mantenimiento') { throw 'Falta Mantenimiento.' }
    if($navBar.ColumnCount -ne 5 -or $navBar.Controls.Count -ne 5){throw 'Navegación de módulos incompleta.'}
    if($actionBar.ColumnCount -ne 6 -or $actionBar.Controls.Count -ne 6){throw 'Barra de acciones incompleta.'}
    if(-not $technicianBtn -or -not $policyBtn){throw 'Faltan Taller técnico y Recomendaciones.'}
    Write-Host 'OK: 7 tablas, recomendaciones, 5 módulos y 6 acciones de inventario.'
    $form.Dispose()
    return
}
[void]$form.ShowDialog()