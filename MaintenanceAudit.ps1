# WinCare Portable - Centro de mantenimiento y limpieza segura v1.3
# Diseñado por DevPoderSEO
# Windows PowerShell 5.1 / Windows 10 y 11.
# Solo elimina archivos temporales elegibles, bajo selección y confirmación.
# No borra el registro, Prefetch, Windows Update, Defender, Descargas o perfiles de navegador.
#requires -Version 5.1
param([object]$Owner, [switch]$SmokeTest, [switch]$SafetyTest)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:MColors = @{
    Bg=[Drawing.Color]::FromArgb(17,24,35)
    Panel=[Drawing.Color]::FromArgb(28,38,52)
    Text=[Drawing.Color]::FromArgb(238,243,249)
    Muted=[Drawing.Color]::FromArgb(172,184,201)
    Accent=[Drawing.Color]::FromArgb(37,132,221)
    Warn=[Drawing.Color]::FromArgb(200,145,49)
}
$script:MAllowExtensions = @('.tmp','.temp','.cache','.bak','.old')
$script:MMaxFiles = 30000
$script:MMaxDepth = 12
$script:MAdmin = $false
$script:MFiles = @{}
$script:MRoots = @()
$script:MErrors = New-Object System.Collections.Generic.List[string]
$script:MScanFinished = $false
$script:MStopTests = $false

function Test-MAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-MOutput {
    if (Get-Command Resolve-OutputDirectory -ErrorAction SilentlyContinue) { return Resolve-OutputDirectory }
    $dir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WinCarePortable\Reportes'
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
    return $dir
}
function Write-MLog([string]$Message) {
    try {
        if (Get-Command Write-Audit -ErrorAction SilentlyContinue) { Write-Audit ('MANTENIMIENTO: '+$Message); return }
        $file = Join-Path (Get-MOutput) 'auditoria-mantenimiento.txt'
        Add-Content -LiteralPath $file -Encoding UTF8 -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Message)
    } catch { }
}
function Format-MSize([double]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes/1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes/1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N1} KB' -f ($Bytes/1KB)) }
    return ('{0:N0} bytes' -f $Bytes)
}
function Add-MDiagnostic([string]$Area,[string]$Name,[string]$Status,[string]$Detail,[string]$Advice) {
    [void]$script:MDiagnostics.Rows.Add([object[]]@($Area,$Name,$Status,$Detail,$Advice))
}
function Invoke-MSafeRead([string]$Area,[scriptblock]$Body) {
    try { & $Body }
    catch {
        Add-MDiagnostic $Area 'Consulta incompleta' 'Información' $_.Exception.Message 'No se realizaron modificaciones. Ejecuta como administrador para obtener más información cuando corresponda.'
        [void]$script:MErrors.Add(($Area+': '+$_.Exception.Message))
    }
}
function Read-MStatus {
    $script:MStatus.Text='Recopilando información del equipo...'
    $script:MDiagnosticButton.Enabled=$false
    $script:MDiagnostics.Clear()
    $script:MErrors.Clear()
    [Windows.Forms.Application]::DoEvents()
    try {
        Invoke-MSafeRead 'Antivirus' {
            $products=@(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue)
            if ($products.Count -gt 0) {
                foreach ($p in $products) { Add-MDiagnostic 'Antivirus' ([string]$p.displayName) 'Información' 'Producto informado por el Centro de seguridad.' 'Confirma su estado desde Seguridad de Windows.' }
            }
            $mp=Get-MpComputerStatus -ErrorAction Stop
            $status=if($mp.RealTimeProtectionEnabled){'Correcto'}else{'Revisar'}
            Add-MDiagnostic 'Antivirus' 'Microsoft Defender, protección en tiempo real' $status ([string]$mp.RealTimeProtectionEnabled) 'Si utilizas otro antivirus, Defender puede estar inactivo legítimamente. Verifica el centro de seguridad.'
            $date='No informada'
            if ($mp.AntivirusSignatureLastUpdated) { $date=([datetime]$mp.AntivirusSignatureLastUpdated).ToString('yyyy-MM-dd HH:mm') }
            Add-MDiagnostic 'Antivirus' 'Última actualización de firmas' 'Información' $date 'Las firmas se actualizan por Windows o el proveedor antivirus; revisa los avisos.'
        }
        Invoke-MSafeRead 'Windows Update' {
            $service=Get-Service -Name wuauserv -ErrorAction Stop
            $risk=if($service.StartType -eq 'Disabled'){'Revisar'}else{'Información'}
            Add-MDiagnostic 'Windows Update' 'Servicio Windows Update' $risk ('Estado: '+$service.Status+'; Inicio: '+$service.StartType) 'Que esté detenido no implica problema: Windows puede iniciarlo cuando lo necesita. Revisa Configuración > Windows Update.'
            $patch=Get-HotFix -ErrorAction SilentlyContinue | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 1
            if($patch){ Add-MDiagnostic 'Windows Update' 'Último hotfix registrado' 'Información' (([string]$patch.HotFixID)+' · '+([datetime]$patch.InstalledOn).ToString('yyyy-MM-dd')) 'Get-HotFix no muestra todas las actualizaciones, especialmente algunas de características.' }
            Add-MDiagnostic 'Windows Update' 'Actualizaciones pendientes' 'No verificadas' 'No se realiza una búsqueda automática de actualizaciones.' 'Abre Windows Update y ejecuta Buscar actualizaciones cuando quieras.'
        }
        Invoke-MSafeRead 'Almacenamiento' {
            foreach($disk in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop)) {
                $size=[double]$disk.Size;$free=[double]$disk.FreeSpace
                $percentage=if($size -gt 0){[math]::Round(100*$free/$size,1)}else{0}
                $state=if($size -gt 0 -and $percentage -lt 10){'Revisar'}else{'Información'}
                Add-MDiagnostic 'Almacenamiento' ('Unidad '+$disk.DeviceID) $state ((Format-MSize $free)+' libres de '+(Format-MSize $size)+' ('+$percentage+'% libre)') 'Si queda poco espacio, utiliza la limpieza con vista previa y revisa archivos propios manualmente.'
            }
        }
        Invoke-MSafeRead 'Inicio' {
            $items=@(Get-CimInstance Win32_StartupCommand -ErrorAction Stop)
            Add-MDiagnostic 'Inicio' 'Entradas de inicio detectadas' 'Información' ([string]$items.Count) 'Una entrada de inicio no significa que sea maliciosa o ralentice el equipo; deshabilita solo si sabes que no la necesitas.'
            foreach($item in $items) {
                $name=if([string]::IsNullOrWhiteSpace([string]$item.Name)){'Sin nombre'}else{[string]$item.Name}
                $where=[string]$item.Location
                $user=[string]$item.User
                Add-MDiagnostic 'Inicio' $name 'Revisar' ('Ubicación: '+$where+'; Cuenta: '+$user) 'Consulta el Administrador de tareas > Aplicaciones de inicio. WinCare no deshabilita nada.'
            }
        }
        Invoke-MSafeRead 'Integridad' {
            $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            Add-MDiagnostic 'Integridad' 'Windows' 'Información' (([string]$os.Caption)+' · Compilación '+[string]$os.BuildNumber) 'Las verificaciones SFC y DISM son opcionales y no reparan por sí solas.'
            Add-MDiagnostic 'Integridad' 'Comprobaciones del sistema' 'No ejecutadas' 'No hay diagnóstico previo implícito.' 'Puedes iniciar SFC /verifyonly o DISM /ScanHealth, tras confirmar.'
        }
        Invoke-MSafeRead 'Seguridad' {
            foreach($profile in @(Get-NetFirewallProfile -ErrorAction Stop)) {
                $state=if($profile.Enabled){'Correcto'}else{'Revisar'}
                Add-MDiagnostic 'Seguridad' ('Firewall '+[string]$profile.Name) $state ('Activado: '+[string]$profile.Enabled) 'Revisa las reglas; no se cambia el firewall desde Mantenimiento.'
            }
        }
        $count=$script:MDiagnostics.Rows.Count
        $alerts=@($script:MDiagnostics.Rows | Where-Object { [string]$_['Estado'] -eq 'Revisar' }).Count
        $script:MStatus.Text=('{0} observaciones; {1} para revisar. No se ha cambiado Windows.' -f $count,$alerts)
        Write-MLog ('Diagnóstico: '+$count+' observaciones; '+$alerts+' para revisar.')
    } finally { $script:MDiagnosticButton.Enabled=$true }
}
function Export-MStatus {
    try {
        if($script:MDiagnostics.Rows.Count -eq 0){ throw 'Primero ejecuta Analizar estado.' }
        $root=Get-MOutput
        $folder=Join-Path $root ('mantenimiento-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
        [void](New-Item -Path $folder -ItemType Directory -Force)
        $list=foreach($r in $script:MDiagnostics.Rows){
            [pscustomobject]@{Area=[string]$r['Área'];Componente=[string]$r['Componente'];Estado=[string]$r['Estado'];Detalle=[string]$r['Detalle'];Recomendacion=[string]$r['Recomendación']}
        }
        $list | Export-Csv -LiteralPath (Join-Path $folder 'diagnostico.csv') -NoTypeInformation -Encoding UTF8
        ('WinCare Portable | Diseñado por DevPoderSEO'+[Environment]::NewLine+'Las evaluaciones son orientativas. No confirman daños ni intrusiones.') | Set-Content -LiteralPath (Join-Path $folder 'LEER-PRIMERO.txt') -Encoding UTF8
        Write-MLog ('Informe de diagnóstico exportado: '+$folder)
        [void][Windows.Forms.MessageBox]::Show(('Informe guardado en: '+$folder),'Exportación','OK','Information')
    } catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'No se pudo exportar','OK','Warning') }
}
function Open-MSettings([string]$Page) {
    $allowed=@('ms-settings:windowsupdate','ms-settings:startupapps','ms-settings:storagesense','ms-settings:windowsdefender')
    if($Page -notin $allowed){ return }
    try { Start-Process -FilePath $Page -ErrorAction Stop }
    catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'No fue posible abrir Configuración','OK','Warning') }
}
function Open-MReports {
    try {
        $folder=Get-MOutput
        [void](Start-Process -FilePath 'explorer.exe' -ArgumentList ('"'+$folder+'"'))
    } catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Reportes','OK','Warning') }
}
function Start-MIntegrity([string]$Kind) {
    if ($Kind -notin @('SFC','DISM')) { return }
    $description=if($Kind -eq 'SFC'){'SFC /verifyonly: verifica archivos protegidos sin repararlos.'}else{'DISM /Online /Cleanup-Image /ScanHealth: analiza la imagen en uso sin reparar.'}
    $prompt=$description+[Environment]::NewLine+[Environment]::NewLine+'La verificación puede consumir CPU y disco y Windows solicitará autorización UAC. Se abrirá una consola para ver el resultado. ¿Continuar?'
    if([Windows.Forms.MessageBox]::Show($prompt,'Verificación voluntaria de Windows','YesNo','Question','Button2') -ne [Windows.Forms.DialogResult]::Yes){return}
    try {
        $cmd=Join-Path $env:WINDIR 'System32\cmd.exe'
        $command=if($Kind -eq 'SFC'){'/k sfc.exe /verifyonly'}else{'/k dism.exe /Online /Cleanup-Image /ScanHealth'}
        [void](Start-Process -FilePath $cmd -ArgumentList $command -Verb RunAs -ErrorAction Stop)
        Write-MLog ('Inicio voluntario de verificación: '+$Kind+'. No repara Windows.')
    } catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'No se pudo iniciar la verificación','OK','Warning') }
}

function Get-MRoots {
    $result=@()
    $userTemp=Join-Path $env:LOCALAPPDATA 'Temp'
    if(Test-Path -LiteralPath $userTemp -PathType Container) {
        $result+= [pscustomobject]@{ Code='Usuario'; Root=[IO.Path]::GetFullPath($userTemp).TrimEnd('\'); Days=7; Admin=$false }
    }
    $windowsTemp=Join-Path $env:WINDIR 'Temp'
    if(Test-Path -LiteralPath $windowsTemp -PathType Container) {
        $result+= [pscustomobject]@{ Code='Windows'; Root=[IO.Path]::GetFullPath($windowsTemp).TrimEnd('\'); Days=14; Admin=$true }
    }
    return $result
}
function Test-MWithinRoot([string]$Root,[string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Root) -or [string]::IsNullOrWhiteSpace($Path)) {return $false}
    try {
        $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd('\')
        $fileFull=[IO.Path]::GetFullPath($Path)
        if ([string]::Equals($rootFull,$fileFull,[StringComparison]::OrdinalIgnoreCase)) { return $false }
        return $fileFull.StartsWith(($rootFull+'\'),[StringComparison]::OrdinalIgnoreCase)
    } catch {return $false}
}
function Test-MSafePath([string]$Root,[string]$Path) {
    if (-not (Test-MWithinRoot $Root $Path)) {return $false}
    try {
        $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd('\')
        $full=[IO.Path]::GetFullPath($Path)
        $rootItem=Get-Item -LiteralPath $rootFull -Force -ErrorAction Stop
        if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {return $false}
        $current=$full
        while (-not [string]::Equals($current,$rootFull,[StringComparison]::OrdinalIgnoreCase)) {
            $item=Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $false}
            $parent=[IO.Directory]::GetParent($current)
            if ($null -eq $parent) {return $false}
            $current=$parent.FullName
            if (-not (Test-MWithinRoot $rootFull $current) -and -not [string]::Equals($current,$rootFull,[StringComparison]::OrdinalIgnoreCase)) {return $false}
        }
        return $true
    } catch {return $false}
}
function Test-MCandidate([IO.FileInfo]$File,[string]$Root,[datetime]$Cutoff) {
    if($null -eq $File -or -not $File.Exists){return $false}
    if (-not (Test-MWithinRoot $Root $File.FullName)) {return $false}
    if ($File.LastWriteTimeUtc -gt $Cutoff) {return $false}
    if ($File.Length -lt 0) {return $false}
    if ($File.Extension.ToLowerInvariant() -notin $script:MAllowExtensions) {return $false}
    if (($File.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {return $false}
    if (($File.Attributes -band [IO.FileAttributes]::System) -ne 0) {return $false}
    if (($File.Attributes -band [IO.FileAttributes]::ReadOnly) -ne 0) {return $false}
    if ($File.FullName -match '(?i)\\(Chrome|Chromium|Edge|Firefox|Mozilla|Opera|Brave|Profile|Profiles)\\') {return $false}
    return (Test-MSafePath $Root $File.FullName)
}
function Find-MCandidates([string]$Root,[int]$Days,[string]$Code) {
    $cutoff=(Get-Date).ToUniversalTime().AddDays(-$Days)
    $count=0
    $stack=New-Object 'System.Collections.Generic.Stack[object]'
    $stack.Push([pscustomobject]@{ Path=$Root; Depth=0 })
    while($stack.Count -gt 0 -and $count -lt $script:MMaxFiles) {
        $current=$stack.Pop()
        $path=[string]$current.Path
        if (-not [string]::Equals($path,$Root,[StringComparison]::OrdinalIgnoreCase) -and -not (Test-MSafePath $Root $path)) {continue}
        try { $children=@(Get-ChildItem -LiteralPath $path -Force -ErrorAction Stop) }
        catch { [void]$script:MErrors.Add(('No se pudo consultar: '+$path)); continue }
        foreach($item in $children) {
            $count++
            if($count -gt $script:MMaxFiles){break}
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){continue}
            if($item -is [IO.DirectoryInfo]) {
                if([int]$current.Depth -lt $script:MMaxDepth) {
                    $stack.Push([pscustomobject]@{Path=$item.FullName;Depth=([int]$current.Depth+1)})
                }
            } elseif($item -is [IO.FileInfo]) {
                if (Test-MCandidate $item $Root $cutoff) {
                    $id=[guid]::NewGuid().ToString('N')
                    $script:MFiles[$id]=[pscustomobject]@{
                        Id=$id;Root=$Root;Path=$item.FullName;Size=[long]$item.Length;
                        ModifiedTicks=[long]$item.LastWriteTimeUtc.Ticks;CreatedTicks=[long]$item.CreationTimeUtc.Ticks;
                        Code=$Code;Days=$Days
                    }
                    [void]$script:MCandidates.Rows.Add([object[]]@($false,$Code,$item.FullName,(Format-MSize $item.Length),$item.LastWriteTime.ToString('yyyy-MM-dd HH:mm'),$id))
                }
            }
            if(($count % 400) -eq 0) {
                $script:MStatus.Text=('Revisando '+$Code+': '+$count+' entradas...')
                [Windows.Forms.Application]::DoEvents()
            }
        }
    }
    if($count -ge $script:MMaxFiles){[void]$script:MErrors.Add('Se alcanzó el límite de '+$script:MMaxFiles+' entradas en '+$Code+'. Inventario parcial.')}
}
function Scan-MTemp {
    $script:MScan.Enabled=$false
    $script:MClean.Enabled=$false
    $script:MCandidates.Clear()
    $script:MFiles.Clear()
    $script:MErrors.Clear()
    $script:MScanFinished=$false
    try {
        $script:MRoots=@(Get-MRoots)
        $script:MAdmin=Test-MAdmin
        foreach($root in $script:MRoots) {
            if($root.Admin -and -not $script:MAdmin) {
                [void]$script:MErrors.Add('La carpeta Windows\Temp requiere permiso de administrador. No se ha escaneado.')
                continue
            }
            if (-not (Test-Path -LiteralPath $root.Root -PathType Container)) {continue}
            $r=Get-Item -LiteralPath $root.Root -Force -ErrorAction SilentlyContinue
            if($null -eq $r -or ($r.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                [void]$script:MErrors.Add('Se omitió una ruta que es enlace o no accesible: '+$root.Code)
                continue
            }
            Find-MCandidates $root.Root ([int]$root.Days) $root.Code
        }
        $script:MScanFinished=$true
        $total=[double]0
        foreach($item in $script:MFiles.Values) { $total += [double]$item.Size }
        $script:MStatus.Text=('{0} archivos temporales elegibles · {1} estimados · {2} advertencias · sin borrar nada' -f $script:MFiles.Count,(Format-MSize $total),$script:MErrors.Count)
        if($script:MErrors.Count -gt 0) {
            [void][Windows.Forms.MessageBox]::Show(($script:MErrors -join [Environment]::NewLine),'Análisis parcial de temporales','OK','Information')
        }
        Write-MLog ('Vista previa de limpieza: '+$script:MFiles.Count+' candidatos; '+(Format-MSize $total)+'.')
    } finally { $script:MScan.Enabled=$true }
}
function Mark-MCandidates([bool]$Checked) {
    foreach($row in $script:MCandidates.Rows) { $row['Seleccionar']=$Checked }
    $script:MClean.Enabled=$Checked -and $script:MFiles.Count -gt 0
}
function Update-MCleanEnabled {
    if(-not $script:MClean -or -not $script:MConfirm){return}
    $hasItems=$false
    if($script:MScanFinished){
        foreach($row in $script:MCandidates.Rows){ if([bool]$row['Seleccionar']) { $hasItems=$true; break } }
    }
    $script:MClean.Enabled=$hasItems -and $script:MConfirm.Checked
}
function Test-MRevalidate($Candidate) {
    if($null -eq $Candidate){return $false}
    $root=$null
    foreach($approved in $script:MRoots) {
        if([string]::Equals($approved.Root,[string]$Candidate.Root,[StringComparison]::OrdinalIgnoreCase) -and $approved.Code -eq $Candidate.Code) { $root=$approved; break }
    }
    if($null -eq $root){return $false}
    if($root.Admin -and -not (Test-MAdmin)){return $false}
    if(-not (Test-MSafePath $root.Root $Candidate.Path)){return $false}
    try {
        $f=Get-Item -LiteralPath $Candidate.Path -Force -ErrorAction Stop
        if($f -isnot [IO.FileInfo]){return $false}
        if(-not (Test-MCandidate $f $root.Root ((Get-Date).ToUniversalTime().AddDays(-[int]$root.Days)))){return $false}
        if([long]$f.Length -ne [long]$Candidate.Size){return $false}
        if([long]$f.LastWriteTimeUtc.Ticks -ne [long]$Candidate.ModifiedTicks){return $false}
        if([long]$f.CreationTimeUtc.Ticks -ne [long]$Candidate.CreatedTicks){return $false}
        return $true
    } catch{return $false}
}
function Clean-MSelected {
    if(-not $script:MConfirm.Checked -or -not $script:MScanFinished){return}
    $chosen=New-Object System.Collections.Generic.List[object]
    foreach($row in $script:MCandidates.Rows) {
        if(-not [bool]$row['Seleccionar']){continue}
        $id=[string]$row['Identificador']
        if($script:MFiles.ContainsKey($id)){ $chosen.Add($script:MFiles[$id]) }
    }
    if($chosen.Count -eq 0){return}
    $size=[double]0;$systemFiles=0
    foreach($item in $chosen){$size+=[double]$item.Size;if($item.Code -eq 'Windows'){$systemFiles++}}
    $text='Has seleccionado '+$chosen.Count+' archivos temporales, estimados en '+(Format-MSize $size)+'.'+[Environment]::NewLine+
        'Se eliminarán únicamente estos candidatos (.tmp/.temp/.cache/.bak/.old) antiguos. No se podrán restaurar de forma garantizada.'+
        [Environment]::NewLine+'Windows y las aplicaciones podrían necesitar reconstruir alguno. Los que cambiaron o están en uso se omitirán.'+
        [Environment]::NewLine+[Environment]::NewLine+'No se tocarán Descargas, documentos, navegador, registro, Defender ni Windows Update.'+
        [Environment]::NewLine+[Environment]::NewLine+'¿Confirmas esta limpieza?'
    if([Windows.Forms.MessageBox]::Show($text,'Confirmar eliminación irreversible','YesNo','Warning','Button2') -ne [Windows.Forms.DialogResult]::Yes){return}
    if($systemFiles -gt 0) {
        $warning='Incluiste '+$systemFiles+' archivos en Windows\Temp. Es una carpeta compartida con procesos y servicios.'+
           [Environment]::NewLine+'Se aplicará la misma validación de antigüedad, extensión y cambios desde la vista previa.'+
           [Environment]::NewLine+'¿Confirmas explícitamente la limpieza de esos archivos de Windows?'
        if([Windows.Forms.MessageBox]::Show($warning,'Confirmación adicional: archivos de Windows','YesNo','Warning','Button2') -ne [Windows.Forms.DialogResult]::Yes){return}
    }
    $script:MClean.Enabled=$false
    $script:MScan.Enabled=$false
    $deleted=0;$skipped=0;$errors=0;$bytes=[double]0
    try {
        foreach($item in $chosen) {
            if(-not (Test-MRevalidate $item)){$skipped++;continue}
            try {
                # Eliminar solo archivos, nunca -Recurse ni directorios.
                Remove-Item -LiteralPath $item.Path -Force -ErrorAction Stop
                $deleted++;$bytes+=[double]$item.Size
            } catch {
                # Archivos protegidos o en uso: ignorar; no forzar procesos a cerrar.
                $errors++
            }
        }
        Write-MLog ('Limpieza manual: eliminados='+$deleted+'; omitidos='+$skipped+'; no eliminables='+$errors+'; tamaño estimado='+[long]$bytes)
        $script:MStatus.Text=('Limpieza finalizada: '+$deleted+' archivos; '+(Format-MSize $bytes)+' estimados; omitidos '+$skipped+'; no eliminables '+$errors+'.')
        [void][Windows.Forms.MessageBox]::Show(($script:MStatus.Text+[Environment]::NewLine+'Se realizará un nuevo análisis de temporales al pulsar Escanear.'),'Resultado de limpieza','OK','Information')
    } finally {
        $script:MConfirm.Checked=$false
        $script:MScanFinished=$false
        $script:MCandidates.Clear()
        $script:MFiles.Clear()
        $script:MScan.Enabled=$true
        $script:MClean.Enabled=$false
    }
}
function Empty-MRecycleBin {
    $warning='Esta operación vaciará la Papelera de reciclaje del usuario en los volúmenes accesibles.'+
        [Environment]::NewLine+'No es una limpieza de temporales y no se puede ofrecer aquí una estimación fiable del contenido.'+
        [Environment]::NewLine+'Si tienes archivos que deseas restaurar, CANCELA y revísalos primero. ¿Continuar?'
    if([Windows.Forms.MessageBox]::Show($warning,'Papelera de reciclaje: advertencia','YesNo','Warning','Button2') -ne [Windows.Forms.DialogResult]::Yes){return}
    if([Windows.Forms.MessageBox]::Show('ÚLTIMA CONFIRMACIÓN: ¿vaciar permanentemente la Papelera de reciclaje?','Confirmar vaciado de papelera','YesNo','Warning','Button2') -ne [Windows.Forms.DialogResult]::Yes){return}
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-MLog 'Papelera vaciada mediante acción manual y doble confirmación.'
        [void][Windows.Forms.MessageBox]::Show('Windows informó que la Papelera fue vaciada.','Papelera','OK','Information')
    } catch {
        Write-MLog ('Papelera: error o cancelación: '+$_.Exception.Message)
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'No se pudo vaciar la Papelera','OK','Warning')
    }
}

$script:MForm=New-Object Windows.Forms.Form
$script:MForm.Text='WinCare Portable | Centro de mantenimiento y limpieza | DevPoderSEO'
$script:MForm.StartPosition='CenterParent'
$script:MForm.Size=New-Object Drawing.Size(1230,795)
$script:MForm.MinimumSize=New-Object Drawing.Size(1070,715)
$script:MForm.BackColor=$script:MColors.Bg
$script:MForm.ForeColor=$script:MColors.Text
$script:MForm.Font=New-Object Drawing.Font('Segoe UI',9)

$head=New-Object Windows.Forms.Label
$head.Text='Centro de mantenimiento'
$head.Location=New-Object Drawing.Point(22,13)
$head.Size=New-Object Drawing.Size(790,40)
$head.Font=New-Object Drawing.Font('Segoe UI Semibold',18,[Drawing.FontStyle]::Bold)
$script:MForm.Controls.Add($head)
$brand=New-Object Windows.Forms.Label
$brand.Text='Diseñado por DevPoderSEO'
$brand.Location=New-Object Drawing.Point(897,21)
$brand.Size=New-Object Drawing.Size(290,26)
$brand.Anchor='Top,Right'
$brand.TextAlign='MiddleRight'
$brand.ForeColor=$script:MColors.Accent
$script:MForm.Controls.Add($brand)
$disclaimer=New-Object Windows.Forms.Label
$disclaimer.Text='Análisis orientativo. Limpieza manual con vista previa; sin borrados automáticos ni reparaciones del sistema.'
$disclaimer.Location=New-Object Drawing.Point(23,58)
$disclaimer.Size=New-Object Drawing.Size(1160,30)
$disclaimer.Anchor='Top,Left,Right'
$disclaimer.ForeColor=$script:MColors.Muted
$script:MForm.Controls.Add($disclaimer)

$tabs=New-Object Windows.Forms.TabControl
$tabs.Location=New-Object Drawing.Point(18,93)
$tabs.Size=New-Object Drawing.Size(1180,600)
$tabs.Anchor='Top,Bottom,Left,Right'
$script:MForm.Controls.Add($tabs)
$diagTab=New-Object Windows.Forms.TabPage
$diagTab.Text='Diagnóstico'
$diagTab.BackColor=$script:MColors.Panel
$cleanTab=New-Object Windows.Forms.TabPage
$cleanTab.Text='Limpieza segura'
$cleanTab.BackColor=$script:MColors.Panel
$toolsTab=New-Object Windows.Forms.TabPage
$toolsTab.Text='Herramientas'
$toolsTab.BackColor=$script:MColors.Panel
[void]$tabs.TabPages.AddRange([Windows.Forms.TabPage[]]@($diagTab,$cleanTab,$toolsTab))

$script:MDiagnosticButton=New-Object Windows.Forms.Button
$script:MDiagnosticButton.Text='Analizar estado'
$script:MDiagnosticButton.Location=New-Object Drawing.Point(14,14)
$script:MDiagnosticButton.Size=New-Object Drawing.Size(145,33)
$script:MDiagnosticButton.BackColor=$script:MColors.Accent
$script:MDiagnosticButton.ForeColor=[Drawing.Color]::White
$script:MDiagnosticButton.FlatStyle='Flat'
$script:MDiagnosticButton.Add_Click({ Read-MStatus })
$diagTab.Controls.Add($script:MDiagnosticButton)
$export=New-Object Windows.Forms.Button
$export.Text='Exportar diagnóstico'
$export.Location=New-Object Drawing.Point(169,14)
$export.Size=New-Object Drawing.Size(175,33)
$export.Add_Click({ Export-MStatus })
$diagTab.Controls.Add($export)
$diagHelp=New-Object Windows.Forms.Label
$diagHelp.Text='Revisa antivirus, actualizaciones, aplicaciones de inicio, almacenamiento y firewall sin hacer cambios.'
$diagHelp.Location=New-Object Drawing.Point(355,20)
$diagHelp.Size=New-Object Drawing.Size(755,25)
$diagHelp.Anchor='Top,Left,Right'
$diagHelp.ForeColor=$script:MColors.Muted
$diagTab.Controls.Add($diagHelp)

$script:MDiagnostics=New-Object System.Data.DataTable
foreach($col in @('Área','Componente','Estado','Detalle','Recomendación')){[void]$script:MDiagnostics.Columns.Add($col,[string])}
$diagGrid=New-Object Windows.Forms.DataGridView
$diagGrid.Location=New-Object Drawing.Point(14,58)
$diagGrid.Size=New-Object Drawing.Size(1135,490)
$diagGrid.Anchor='Top,Bottom,Left,Right'
$diagGrid.ReadOnly=$true
$diagGrid.AllowUserToAddRows=$false
$diagGrid.AllowUserToDeleteRows=$false
$diagGrid.SelectionMode='FullRowSelect'
$diagGrid.AutoGenerateColumns=$false
$diagGrid.AutoSizeColumnsMode='DisplayedCells'
$diagGrid.RowHeadersVisible=$false
$diagGrid.BackgroundColor=$script:MColors.Panel
$diagGrid.EnableHeadersVisualStyles=$false
$diagGrid.ColumnHeadersDefaultCellStyle.BackColor=[Drawing.Color]::FromArgb(39,53,72)
$diagGrid.ColumnHeadersDefaultCellStyle.ForeColor=$script:MColors.Text
$diagGrid.DefaultCellStyle.BackColor=$script:MColors.Panel
$diagGrid.DefaultCellStyle.ForeColor=$script:MColors.Text
$diagGrid.DefaultCellStyle.SelectionBackColor=[Drawing.Color]::FromArgb(39,104,169)
$diagGrid.DefaultCellStyle.SelectionForeColor=[Drawing.Color]::White
foreach($name in @('Área','Componente','Estado','Detalle','Recomendación')){
    $col=New-Object Windows.Forms.DataGridViewTextBoxColumn
    $col.Name=$name;$col.DataPropertyName=$name;$col.HeaderText=$name
    [void]$diagGrid.Columns.Add($col)
}
$diagGrid.DataSource=$script:MDiagnostics.DefaultView
$diagTab.Controls.Add($diagGrid)

$cleanNotice=New-Object Windows.Forms.Label
$cleanNotice.Text='Solo archivos .tmp, .temp, .cache, .bak y .old con más de 7 días (usuario) o 14 días (Windows). Se omiten enlaces, ejecutables y archivos cambiados.'
$cleanNotice.Location=New-Object Drawing.Point(15,9)
$cleanNotice.Size=New-Object Drawing.Size(1130,29)
$cleanNotice.Anchor='Top,Left,Right'
$cleanNotice.ForeColor=$script:MColors.Muted
$cleanTab.Controls.Add($cleanNotice)
$script:MScan=New-Object Windows.Forms.Button
$script:MScan.Text='Escanear temporales'
$script:MScan.Location=New-Object Drawing.Point(14,42)
$script:MScan.Size=New-Object Drawing.Size(165,33)
$script:MScan.BackColor=$script:MColors.Accent
$script:MScan.ForeColor=[Drawing.Color]::White
$script:MScan.FlatStyle='Flat'
$script:MScan.Add_Click({ Scan-MTemp })
$cleanTab.Controls.Add($script:MScan)
$mark=New-Object Windows.Forms.Button
$mark.Text='Seleccionar todos'
$mark.Location=New-Object Drawing.Point(189,42)
$mark.Size=New-Object Drawing.Size(145,33)
$mark.Add_Click({ Mark-MCandidates $true; Update-MCleanEnabled })
$cleanTab.Controls.Add($mark)
$unmark=New-Object Windows.Forms.Button
$unmark.Text='Desmarcar'
$unmark.Location=New-Object Drawing.Point(345,42)
$unmark.Size=New-Object Drawing.Size(115,33)
$unmark.Add_Click({ Mark-MCandidates $false; Update-MCleanEnabled })
$cleanTab.Controls.Add($unmark)
$script:MConfirm=New-Object Windows.Forms.CheckBox
$script:MConfirm.Text='He revisado los archivos y tengo respaldo si lo necesito.'
$script:MConfirm.Location=New-Object Drawing.Point(478,42)
$script:MConfirm.Size=New-Object Drawing.Size(430,33)
$script:MConfirm.ForeColor=$script:MColors.Muted
$script:MConfirm.Checked=$false
$script:MConfirm.Add_CheckedChanged({ Update-MCleanEnabled })
$cleanTab.Controls.Add($script:MConfirm)
$script:MClean=New-Object Windows.Forms.Button
$script:MClean.Text='Limpiar seleccionados'
$script:MClean.Location=New-Object Drawing.Point(936,42)
$script:MClean.Size=New-Object Drawing.Size(210,33)
$script:MClean.Anchor='Top,Right'
$script:MClean.BackColor=[Drawing.Color]::FromArgb(151,69,62)
$script:MClean.ForeColor=[Drawing.Color]::White
$script:MClean.FlatStyle='Flat'
$script:MClean.Enabled=$false
$script:MClean.Add_Click({ Clean-MSelected })
$cleanTab.Controls.Add($script:MClean)

$script:MCandidates=New-Object System.Data.DataTable
[void]$script:MCandidates.Columns.Add('Seleccionar',[bool])
foreach($name in @('Origen','Ruta','Tamaño','Modificado','Identificador')){[void]$script:MCandidates.Columns.Add($name,[string])}
$script:MGrid=New-Object Windows.Forms.DataGridView
$script:MGrid.Location=New-Object Drawing.Point(14,85)
$script:MGrid.Size=New-Object Drawing.Size(1135,468)
$script:MGrid.Anchor='Top,Bottom,Left,Right'
$script:MGrid.AllowUserToAddRows=$false
$script:MGrid.AllowUserToDeleteRows=$false
$script:MGrid.SelectionMode='FullRowSelect'
$script:MGrid.AutoGenerateColumns=$false
$script:MGrid.AutoSizeColumnsMode='Fill'
$script:MGrid.RowHeadersVisible=$false
$script:MGrid.BackgroundColor=$script:MColors.Panel
$script:MGrid.EnableHeadersVisualStyles=$false
$script:MGrid.ColumnHeadersDefaultCellStyle.BackColor=[Drawing.Color]::FromArgb(39,53,72)
$script:MGrid.ColumnHeadersDefaultCellStyle.ForeColor=$script:MColors.Text
$script:MGrid.DefaultCellStyle.BackColor=$script:MColors.Panel
$script:MGrid.DefaultCellStyle.ForeColor=$script:MColors.Text
$script:MGrid.DefaultCellStyle.SelectionBackColor=[Drawing.Color]::FromArgb(39,104,169)
$script:MGrid.DefaultCellStyle.SelectionForeColor=[Drawing.Color]::White
$choose=New-Object Windows.Forms.DataGridViewCheckBoxColumn
$choose.Name='Seleccionar';$choose.DataPropertyName='Seleccionar';$choose.HeaderText='Elegir';$choose.FillWeight=45
[void]$script:MGrid.Columns.Add($choose)
foreach($name in @('Origen','Ruta','Tamaño','Modificado','Identificador')){
    $col=New-Object Windows.Forms.DataGridViewTextBoxColumn
    $col.Name=$name;$col.DataPropertyName=$name;$col.HeaderText=$name
    $col.ReadOnly=$true
    if($name -eq 'Ruta'){$col.FillWeight=410}
    elseif($name -eq 'Identificador'){$col.Visible=$false}
    else{$col.FillWeight=85}
    [void]$script:MGrid.Columns.Add($col)
}
$script:MGrid.DataSource=$script:MCandidates.DefaultView
$script:MGrid.Add_CurrentCellDirtyStateChanged({
    if($script:MGrid.IsCurrentCellDirty){[void]$script:MGrid.CommitEdit([Windows.Forms.DataGridViewDataErrorContexts]::Commit)}
})
$script:MGrid.Add_CellValueChanged({ Update-MCleanEnabled })
$cleanTab.Controls.Add($script:MGrid)

$toolsText=New-Object Windows.Forms.Label
$toolsText.Text='Estas funciones solo abren herramientas oficiales de Windows. SFC y DISM son verificaciones voluntarias que NO reparan archivos.'
$toolsText.Location=New-Object Drawing.Point(22,18)
$toolsText.Size=New-Object Drawing.Size(1100,44)
$toolsText.ForeColor=$script:MColors.Muted
$toolsTab.Controls.Add($toolsText)
$tools=@(
    @('Windows Update',20,75,{ Open-MSettings 'ms-settings:windowsupdate' }),
    @('Aplicaciones de inicio',260,75,{ Open-MSettings 'ms-settings:startupapps' }),
    @('Sensor de almacenamiento',500,75,{ Open-MSettings 'ms-settings:storagesense' }),
    @('Seguridad de Windows',740,75,{ Open-MSettings 'ms-settings:windowsdefender' }),
    @('Ver reportes e historial',20,133,{ Open-MReports }),
    @('Verificar SFC (sin reparar)',260,133,{ Start-MIntegrity 'SFC' }),
    @('Analizar DISM (sin reparar)',500,133,{ Start-MIntegrity 'DISM' }),
    @('Vaciar Papelera (manual)',740,133,{ Empty-MRecycleBin })
)
foreach($action in $tools){
    $button=New-Object Windows.Forms.Button
    $button.Text=[string]$action[0]
    $button.Location=New-Object Drawing.Point([int]$action[1],[int]$action[2])
    $button.Size=New-Object Drawing.Size(230,42)
    $button.Add_Click($action[3])
    $toolsTab.Controls.Add($button)
}
$caution=New-Object Windows.Forms.Label
$caution.Text='Nunca borrar: registro, Windows Update, WinSxS, Prefetch, Defender, controladores, Descargas, Documentos o perfiles de navegador.'+
    [Environment]::NewLine+'Papelera: requiere doble confirmación y no permite deshacer de forma garantizada. Cierra programas y guarda tus archivos antes de limpiar.'
$caution.Location=New-Object Drawing.Point(23,215)
$caution.Size=New-Object Drawing.Size(1100,82)
$caution.Anchor='Top,Left,Right'
$caution.ForeColor=[Drawing.Color]::FromArgb(246,184,92)
$toolsTab.Controls.Add($caution)

$script:MStatus=New-Object Windows.Forms.Label
$script:MStatus.Text='Listo. No se ha ejecutado ninguna limpieza ni reparación.'
$script:MStatus.Location=New-Object Drawing.Point(21,711)
$script:MStatus.Size=New-Object Drawing.Size(1160,25)
$script:MStatus.Anchor='Bottom,Left,Right'
$script:MStatus.ForeColor=$script:MColors.Muted
$script:MForm.Controls.Add($script:MStatus)

if($SmokeTest){
    if($script:MGrid.Columns.Count -ne 6){throw 'Fallo inicialización columnas de limpieza.'}
    if($diagGrid.Columns.Count -ne 5){throw 'Fallo inicialización columnas de mantenimiento.'}
    if($script:MClean.Enabled){throw 'La limpieza no puede estar habilitada por defecto.'}
    if($script:MConfirm.Checked){throw 'La confirmación no puede estar marcada por defecto.'}
    Write-Host 'OK: panel mantenimiento (5 columnas), limpieza (6 columnas), borrado deshabilitado.'
    $script:MForm.Dispose()
    return
}
if($SafetyTest){
    $testRoot=Join-Path ([IO.Path]::GetTempPath()) ('WinCare-Test-'+[guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $testRoot -Force)
    try {
        $good=Join-Path $testRoot 'archivo.tmp'
        $bad=Join-Path ([IO.Path]::GetDirectoryName($testRoot)) 'fuera-de-root.tmp'
        [IO.File]::WriteAllText($good,'archivo prueba; no borrar')
        $f=Get-Item -LiteralPath $good
        $f.LastWriteTimeUtc=[datetime]::UtcNow.AddDays(-20)
        $f=Get-Item -LiteralPath $good
        if(-not (Test-MWithinRoot $testRoot $good)){throw 'Falla ruta válida.'}
        if(Test-MWithinRoot $testRoot $bad){throw 'Falla ruta fuera.'}
        if(-not (Test-MCandidate $f $testRoot ([datetime]::UtcNow.AddDays(-7)))){throw 'Falla candidato válido.'}
        $badExtension=Join-Path $testRoot 'archivo.exe'
        [IO.File]::WriteAllText($badExtension,'solo para pruebas')
        $f2=Get-Item -LiteralPath $badExtension
        $f2.LastWriteTimeUtc=[datetime]::UtcNow.AddDays(-20)
        $f2=Get-Item -LiteralPath $badExtension
        if(Test-MCandidate $f2 $testRoot ([datetime]::UtcNow.AddDays(-7))){throw 'Falla bloqueo extensión .exe.'}
        Write-Host 'OK: ruta interna aprobada, externa bloqueada, .tmp antiguo permitido, .exe bloqueado. Ninguna limpieza ejecutada.'
    } finally {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        $script:MForm.Dispose()
    }
    return
}
$script:MForm.Add_Shown({ [Windows.Forms.Application]::DoEvents(); Read-MStatus })
try {
    if($Owner){[void]$script:MForm.ShowDialog($Owner)}
    else{[void]$script:MForm.ShowDialog()}
} finally { $script:MForm.Dispose() }
